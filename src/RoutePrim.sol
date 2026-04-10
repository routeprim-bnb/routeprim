// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IRoutePrim} from "./interfaces/IRoutePrim.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";
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
///        3. RoutePrim verifies the sig, pulls funds via Permit2, swaps/routes
///        4. Output lands at `recipient` — no pre-approval UX needed
contract RoutePrim is IRoutePrim {
    using SignatureVerifier for bytes32;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IPermit2 public immutable PERMIT2;
    bytes32 public immutable DOMAIN_SEPARATOR;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Consumed nonces per signer
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    /// @notice EIP-7702 authority delegations
    mapping(address => address) public authority;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _permit2) {
        PERMIT2 = IPermit2(_permit2);
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

        amountOut = _swap(params);

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

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _verifyAuth(AuthParams calldata auth) internal {
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

    /// @dev Stub — integrate PancakeSwap V3 / deBridge / custom aggregator here
    function _swap(RouteParams calldata params) internal pure returns (uint256) {
        // TODO: integrate swap router
        return params.amountOutMin;
    }
}
