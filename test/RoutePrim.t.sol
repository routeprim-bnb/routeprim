// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RoutePrim} from "../src/RoutePrim.sol";
import {IRoutePrim} from "../src/interfaces/IRoutePrim.sol";

contract RoutePrimTest is Test {
    RoutePrim routeprim;

    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address alice;
    uint256 aliceKey;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        routeprim = new RoutePrim(PERMIT2);
    }

    function test_domainSeparator() public view {
        assertNotEq(routeprim.DOMAIN_SEPARATOR(), bytes32(0));
    }

    function test_revertExpiredDeadline() public {
        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn: address(0),
            tokenOut: address(0),
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: alice,
            deadline: block.timestamp - 1,
            permitSig: ""
        });

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer: alice,
            nonce: 0,
            deadline: block.timestamp - 1,
            signature: ""
        });

        vm.expectRevert(IRoutePrim.DeadlineExpired.selector);
        routeprim.route(params, auth);
    }

    function test_revertInvalidSignature() public {
        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn: address(0),
            tokenOut: address(0),
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: alice,
            deadline: block.timestamp + 1 hours,
            permitSig: ""
        });

        // Sign with wrong key
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        bytes32 digest = keccak256(abi.encodePacked("garbage"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer: alice,
            nonce: 1,
            deadline: block.timestamp + 1 hours,
            signature: sig
        });

        vm.expectRevert(IRoutePrim.InvalidSignature.selector);
        routeprim.route(params, auth);
    }
}
