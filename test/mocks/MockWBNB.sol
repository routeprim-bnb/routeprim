// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MockERC20} from "./MockERC20.sol";

/// @dev MockWBNB mirrors real WBNB: deposit() wraps BNB, withdraw() unwraps it.
///      Deploy and then vm.etch(WBNB_ADDR, address(mock).code) in test setUp.
contract MockWBNB is MockERC20 {
    constructor() MockERC20("Wrapped BNB", "WBNB") {}

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply            += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "MockWBNB: insufficient balance");
        balanceOf[msg.sender] -= wad;
        totalSupply            -= wad;
        emit Transfer(msg.sender, address(0), wad);
        payable(msg.sender).transfer(wad);
    }

    receive() external payable {}
}
