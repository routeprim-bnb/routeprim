// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title IWBNB
/// @notice Minimal interface for Wrapped BNB (BSC canonical: 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c)
interface IWBNB {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
