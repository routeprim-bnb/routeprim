// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {RoutePrim} from "../src/RoutePrim.sol";

contract DeployRoutePrim is Script {
    // Permit2 is deployed at the same address on all EVM chains
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external {
        vm.startBroadcast();

        RoutePrim routeprim = new RoutePrim(PERMIT2);
        console2.log("RoutePrim deployed at:", address(routeprim));
        console2.log("Chain ID:", block.chainid);

        vm.stopBroadcast();
    }
}
