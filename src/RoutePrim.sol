// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IRoutePrim} from "./interfaces/IRoutePrim.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";
import {IPancakeV3Router} from "./interfaces/IPancakeV3Router.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IWBNB} from "./interfaces/IWBNB.sol";
import {SignatureVerifier} from "./lib/SignatureVerifier.sol";
import {EIP7702Helper} from "./lib/EIP7702Helper.sol";

/// @title RoutePrim
/// @notice Account-abstraction payment routing primitive for BNB Chain
/// @dev Combines EIP-7702 authority delegation with Permit2-style
///      single-signature approvals for gas-efficient, trustless payment flows.
///
///      Flow:
///        1. User signs an AuthParams off-chain (EIP-712)
///        2. Relayer calls `route()` on their behalf
///        3. RoutePrim verifies the sig, pulls funds via Permit2, swaps via PancakeSwap V3
///        4. Output lands at `recipient` — no pre-approval UX needed
contract RoutePrim is IRoutePrim {
    using SignatureVerifier for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VERSION
    //////////////////////////////////////////////////////////////*/

    string public constant VERSION = "1.0.0";

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IPermit2         public immutable PERMIT2;
    IPancakeV3Router public immutable SWAP_ROUTER;
    IWBNB            public immutable WBNB;
    bytes32          public immutable DOMAIN_SEPARATOR;

    /// @dev Canonical WBNB address on BNB Chain
    address internal constant WBNB_ADDR = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Consumed nonces per signer
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    /// @notice EIP-7702 authority delegations registered via setAuthority()
    mapping(address => address) public authority;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _permit2    Canonical Permit2 address (0x000000000022D473030F116dDEE9F6B43aC78BA3)
    /// @param _swapRouter PancakeSwap V3 SmartRouter for the target chain
    constructor(address _permit2, address _swapRouter) {
        PERMIT2     = IPermit2(_permit2);
        SWAP_ROUTER = IPancakeV3Router(_swapRouter);
        WBNB        = IWBNB(WBNB_ADDR);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("RoutePrim"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ROUTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRoutePrim
    function route(RouteParams calldata params, AuthParams calldata auth)
        external
        returns (uint256 amountOut)
    {
        _verifyAuth(auth);

        PERMIT2.permitTransferFrom(
            IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({token: params.tokenIn, amount: params.amountIn}),
                nonce: auth.nonce,
                deadline: params.deadline
            }),
            IPermit2.SignatureTransferDetails({to: address(this), requestedAmount: params.amountIn}),
            auth.signer,
            params.permitSig
        );

        amountOut = _swap(params);

        if (amountOut < params.amountOutMin) {
            revert InsufficientOutput(params.amountOutMin, amountOut);
        }

        emit Routed(
            auth.signer,
            params.recipient,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut
        );
    }

    /// @inheritdoc IRoutePrim
    function routeNative(RouteParams calldata params, AuthParams calldata auth)
        external
        payable
        returns (uint256 amountOut)
    {
        _verifyAuth(auth);
        require(msg.value == params.amountIn, "RoutePrim: incorrect BNB amount");

        // Wrap native BNB → WBNB so _doExactInput can treat it as ERC-20
        WBNB.deposit{value: msg.value}();

        // swapData must encode: abi.encodePacked(WBNB_ADDR, fee, tokenOut)
        amountOut = _doExactInput(
            WBNB_ADDR,
            params.swapData,
            params.recipient,
            params.deadline,
            params.amountIn,
            params.amountOutMin
        );

        if (amountOut < params.amountOutMin) {
            revert InsufficientOutput(params.amountOutMin, amountOut);
        }

        emit Routed(
            auth.signer,
            params.recipient,
            address(0),
            params.tokenOut,
            params.amountIn,
            amountOut
        );
    }

    /// @inheritdoc IRoutePrim
    function setAuthority(address _authority, AuthParams calldata auth) external {
        _verifyAuth(auth);
        authority[auth.signer] = _authority;
        emit AuthoritySet(auth.signer, _authority);
    }

    /// @dev Reject accidental native BNB transfers; all BNB must come through routeNative().
    receive() external payable {
        revert("RoutePrim: use routeNative()");
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _verifyAuth(AuthParams calldata auth) internal {
        if (auth.signer == address(0)) revert InvalidSignature();
        if (block.timestamp > auth.deadline) revert DeadlineExpired();
        if (usedNonces[auth.signer][auth.nonce]) revert Unauthorized();

        bytes32 structHash = SignatureVerifier.hash(auth.signer, auth.nonce, auth.deadline);
        address recovered = SignatureVerifier.recover(DOMAIN_SEPARATOR, structHash, auth.signature);

        // Allow EIP-7702 delegated authority to sign on behalf of signer
        bool valid = recovered == auth.signer
            || (authority[auth.signer] != address(0) && recovered == authority[auth.signer])
            || (EIP7702Helper.isDelegated(auth.signer) && recovered == EIP7702Helper.getDelegate(auth.signer));

        if (!valid) revert InvalidSignature();

        usedNonces[auth.signer][auth.nonce] = true;
    }

    /// @dev ERC-20 swap entry point — delegates to _doExactInput.
    function _swap(RouteParams calldata params) internal returns (uint256) {
        return _doExactInput(
            params.tokenIn,
            params.swapData,
            params.recipient,
            params.deadline,
            params.amountIn,
            params.amountOutMin
        );
    }

    /// @dev Executes a PancakeSwap V3 exactInput swap.
    ///      Grants the router an exact-amount approval, executes the swap,
    ///      then revokes residual allowance. On swap revert, allowance is
    ///      also cleared before propagating the SwapFailed error.
    function _doExactInput(
        address tokenIn,
        bytes memory path,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(SWAP_ROUTER), amountIn);

        try SWAP_ROUTER.exactInput(
            IPancakeV3Router.ExactInputParams({
                path:             path,
                recipient:        recipient,
                deadline:         deadline,
                amountIn:         amountIn,
                amountOutMinimum: amountOutMin
            })
        ) returns (uint256 out) {
            IERC20(tokenIn).approve(address(SWAP_ROUTER), 0);
            amountOut = out;
        } catch {
            IERC20(tokenIn).approve(address(SWAP_ROUTER), 0);
            revert SwapFailed();
        }
    }
}
