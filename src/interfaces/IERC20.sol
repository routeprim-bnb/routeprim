// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title IERC20
/// @notice Minimal ERC-20 interface used by RoutePrim for swap router approvals
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
