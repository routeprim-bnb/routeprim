// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {RoutePrim} from "../src/RoutePrim.sol";

contract DeployRoutePrim is Script {
    // Permit2 — same canonical address on all EVM-compatible chains
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // PancakeSwap V3 SmartRouter
    address constant PANCAKE_V3_MAINNET = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address constant PANCAKE_V3_TESTNET = 0x9a489505a00cE272eAa5e07Dba6491314CaE3796;

    // BNB Chain IDs
    uint256 constant BSC_MAINNET = 56;
    uint256 constant BSC_TESTNET = 97;

    function run() external {
        address swapRouter = block.chainid == BSC_MAINNET
            ? PANCAKE_V3_MAINNET
            : PANCAKE_V3_TESTNET;

        vm.startBroadcast();

        RoutePrim routeprim = new RoutePrim(PERMIT2, swapRouter);

        console2.log("RoutePrim deployed at:", address(routeprim));
        console2.log("Chain ID:             ", block.chainid);
        console2.log("PERMIT2:              ", PERMIT2);
        console2.log("SWAP_ROUTER:          ", swapRouter);

        vm.stopBroadcast();
    }
}
