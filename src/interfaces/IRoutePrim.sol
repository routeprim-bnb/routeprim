// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title IRoutePrim
/// @notice Interface for the RoutePrim payment routing primitive
interface IRoutePrim {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct RouteParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        address recipient;
        uint256 deadline;
        bytes permitSig;
        /// @dev PancakeSwap V3 path: abi.encodePacked(tokenIn, fee, tokenOut) for single-hop.
        ///      For routeNative, path must start with WBNB address.
        bytes swapData;
    }

    struct AuthParams {
        address signer;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Routed(
        address indexed sender,
        address indexed recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event AuthoritySet(address indexed account, address indexed authority);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error DeadlineExpired();
    error InvalidSignature();
    error InsufficientOutput(uint256 expected, uint256 actual);
    error Unauthorized();
    error SwapFailed();

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Route a payment using Permit2-style authorization
    function route(RouteParams calldata params, AuthParams calldata auth) external returns (uint256 amountOut);

    /// @notice Route native BNB
    function routeNative(RouteParams calldata params, AuthParams calldata auth)
        external
        payable
        returns (uint256 amountOut);

    /// @notice Delegate authority via EIP-7702
    function setAuthority(address authority, AuthParams calldata auth) external;
}
