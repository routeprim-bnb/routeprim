// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title IPancakeV3Router
/// @notice Minimal interface for the PancakeSwap V3 SmartRouter exactInput path
/// @dev BSC mainnet:  0x13f4EA83D0bd40E75C8222255bc855a974568Dd4
///      BSC testnet:  0x9a489505a00cE272eAa5e07Dba6491314CaE3796
interface IPancakeV3Router {
    struct ExactInputParams {
        /// @dev abi.encodePacked(tokenIn, fee, tokenOut) for single-hop;
        ///      chain additional (fee, token) segments for multi-hop
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another
    ///         along the specified path, enforcing `amountOutMinimum`.
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
