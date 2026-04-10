// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RoutePrim} from "../src/RoutePrim.sol";
import {IRoutePrim} from "../src/interfaces/IRoutePrim.sol";
import {SignatureVerifier} from "../src/lib/SignatureVerifier.sol";
import {EIP7702Helper} from "../src/lib/EIP7702Helper.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {MockSwapRouter} from "./mocks/MockSwapRouter.sol";

contract RoutePrimTest is Test {
    /*//////////////////////////////////////////////////////////////
                               TEST STATE
    //////////////////////////////////////////////////////////////*/

    RoutePrim      routeprim;
    MockERC20      tokenIn;
    MockERC20      tokenOut;
    MockWBNB       mockWBNB;
    MockPermit2    mockPermit2;
    MockSwapRouter mockRouter;

    address alice;
    uint256 aliceKey;

    address constant WBNB_ADDR = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");

        tokenIn  = new MockERC20("TokenIn",  "TIN");
        tokenOut = new MockERC20("TokenOut", "TOUT");

        // Deploy MockWBNB bytecode at the canonical BSC WBNB address so
        // RoutePrim's hardcoded WBNB_ADDR constant resolves to our mock.
        MockWBNB deployedWBNB = new MockWBNB();
        vm.etch(WBNB_ADDR, address(deployedWBNB).code);
        mockWBNB = MockWBNB(payable(WBNB_ADDR));

        mockPermit2 = new MockPermit2();
        mockRouter  = new MockSwapRouter(address(tokenOut));

        routeprim = new RoutePrim(address(mockPermit2), address(mockRouter));
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER: SIGN AUTH
    //////////////////////////////////////////////////////////////*/

    /// @dev Produces a valid EIP-712 AuthParams signature for the given signer key.
    function _signAuth(uint256 signerKey, address signer, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 structHash = SignatureVerifier.hash(signer, nonce, deadline);
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", routeprim.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                        UNIT TESTS — AUTH LAYER
    //////////////////////////////////////////////////////////////*/

    function test_domainSeparator() public view {
        assertNotEq(routeprim.DOMAIN_SEPARATOR(), bytes32(0));
    }

    function test_revertExpiredDeadline() public {
        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn:      address(0),
            tokenOut:     address(0),
            amountIn:     1e18,
            amountOutMin: 0,
            recipient:    alice,
            deadline:     block.timestamp - 1,
            permitSig:    "",
            swapData:     ""
        });

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer:    alice,
            nonce:     0,
            deadline:  block.timestamp - 1,
            signature: ""
        });

        vm.expectRevert(IRoutePrim.DeadlineExpired.selector);
        routeprim.route(params, auth);
    }

    function test_revertInvalidSignature() public {
        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn:      address(tokenIn),
            tokenOut:     address(tokenOut),
            amountIn:     1e18,
            amountOutMin: 0,
            recipient:    alice,
            deadline:     block.timestamp + 1 hours,
            permitSig:    "",
            swapData:     ""
        });

        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        bytes32 digest = keccak256(abi.encodePacked("garbage"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer:    alice,
            nonce:     1,
            deadline:  block.timestamp + 1 hours,
            signature: sig
        });

        vm.expectRevert(IRoutePrim.InvalidSignature.selector);
        routeprim.route(params, auth);
    }

    /*//////////////////////////////////////////////////////////////
                     INTEGRATION TESTS — HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    /// @notice Full route() flow: valid auth → Permit2 pull → PancakeSwap V3 swap → recipient
    function test_routeHappyPath() public {
        uint256 amountIn     = 100e18;
        uint256 amountOutMin = 90e18;
        uint256 nonce        = 42;
        uint256 deadline     = block.timestamp + 1 hours;

        tokenIn.mint(alice, amountIn);
        vm.prank(alice);
        tokenIn.approve(address(mockPermit2), amountIn);

        // PancakeSwap V3 single-hop path: tokenIn →[0.05% fee]→ tokenOut
        bytes memory path    = abi.encodePacked(address(tokenIn), uint24(500), address(tokenOut));
        bytes memory authSig = _signAuth(aliceKey, alice, nonce, deadline);

        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn:      address(tokenIn),
            tokenOut:     address(tokenOut),
            amountIn:     amountIn,
            amountOutMin: amountOutMin,
            recipient:    alice,
            deadline:     deadline,
            permitSig:    "",
            swapData:     path
        });

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer:    alice,
            nonce:     nonce,
            deadline:  deadline,
            signature: authSig
        });

        uint256 amountOut = routeprim.route(params, auth);

        assertEq(amountOut, amountIn);           // MockSwapRouter defaults to 1:1
        assertEq(tokenOut.balanceOf(alice), amountIn);
        assertTrue(routeprim.usedNonces(alice, nonce));
    }

    /// @notice Nonce replay should revert Unauthorized on the second call
    function test_nonceReuseReverts() public {
        uint256 amountIn = 10e18;
        uint256 nonce    = 99;
        uint256 deadline = block.timestamp + 1 hours;

        tokenIn.mint(alice, amountIn * 2);
        vm.prank(alice);
        tokenIn.approve(address(mockPermit2), amountIn * 2);

        bytes memory path    = abi.encodePacked(address(tokenIn), uint24(500), address(tokenOut));
        bytes memory authSig = _signAuth(aliceKey, alice, nonce, deadline);

        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn:      address(tokenIn),
            tokenOut:     address(tokenOut),
            amountIn:     amountIn,
            amountOutMin: 0,
            recipient:    alice,
            deadline:     deadline,
            permitSig:    "",
            swapData:     path
        });

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer:    alice,
            nonce:     nonce,
            deadline:  deadline,
            signature: authSig
        });

        routeprim.route(params, auth);

        vm.expectRevert(IRoutePrim.Unauthorized.selector);
        routeprim.route(params, auth);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS — EIP-7702 DELEGATION
    //////////////////////////////////////////////////////////////*/

    /// @notice A delegate set via EIP-7702 code prefix can sign on behalf of the EOA
    function test_eip7702DelegationFlow() public {
        (address delegate, uint256 delegateKey) = makeAddrAndKey("delegate");

        uint256 amountIn = 50e18;
        uint256 nonce    = 7;
        uint256 deadline = block.timestamp + 1 hours;

        tokenIn.mint(alice, amountIn);

        // Approve before etching so alice is still a plain EOA for vm.prank
        vm.prank(alice);
        tokenIn.approve(address(mockPermit2), amountIn);

        // Set alice's code to EIP-7702 delegation: 0xef0100 ++ delegate (23 bytes total)
        vm.etch(alice, abi.encodePacked(bytes3(0xef0100), delegate));

        assertTrue(EIP7702Helper.isDelegated(alice));
        assertEq(EIP7702Helper.getDelegate(alice), delegate);

        bytes memory path    = abi.encodePacked(address(tokenIn), uint24(500), address(tokenOut));
        bytes memory authSig = _signAuth(delegateKey, alice, nonce, deadline); // delegate signs

        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn:      address(tokenIn),
            tokenOut:     address(tokenOut),
            amountIn:     amountIn,
            amountOutMin: 0,
            recipient:    alice,
            deadline:     deadline,
            permitSig:    "",
            swapData:     path
        });

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer:    alice,   // signer is still alice
            nonce:     nonce,
            deadline:  deadline,
            signature: authSig  // but signed by her EIP-7702 delegate
        });

        uint256 amountOut = routeprim.route(params, auth);
        assertGt(amountOut, 0);
    }

    /// @notice setAuthority() registers an off-chain delegate; subsequent route() accepts its sig
    function test_setAuthorityAndRoute() public {
        (address delegate, uint256 delegateKey) = makeAddrAndKey("delegate2");

        uint256 authNonce  = 1;
        uint256 routeNonce = 2;
        uint256 deadline   = block.timestamp + 1 hours;

        // Alice registers delegate as her authority via signed AuthParams
        bytes memory setAuthSig = _signAuth(aliceKey, alice, authNonce, deadline);
        routeprim.setAuthority(
            delegate,
            IRoutePrim.AuthParams({
                signer:    alice,
                nonce:     authNonce,
                deadline:  deadline,
                signature: setAuthSig
            })
        );
        assertEq(routeprim.authority(alice), delegate);

        // Delegate signs a route call on alice's behalf
        uint256 amountIn = 20e18;
        tokenIn.mint(alice, amountIn);
        vm.prank(alice);
        tokenIn.approve(address(mockPermit2), amountIn);

        bytes memory path     = abi.encodePacked(address(tokenIn), uint24(500), address(tokenOut));
        bytes memory routeSig = _signAuth(delegateKey, alice, routeNonce, deadline);

        uint256 amountOut = routeprim.route(
            IRoutePrim.RouteParams({
                tokenIn:      address(tokenIn),
                tokenOut:     address(tokenOut),
                amountIn:     amountIn,
                amountOutMin: 0,
                recipient:    alice,
                deadline:     deadline,
                permitSig:    "",
                swapData:     path
            }),
            IRoutePrim.AuthParams({
                signer:    alice,
                nonce:     routeNonce,
                deadline:  deadline,
                signature: routeSig
            })
        );

        assertGt(amountOut, 0);
    }

    /// @notice routeNative: BNB is wrapped to WBNB and swapped via the V3 router
    function test_routeNativeHappyPath() public {
        uint256 amountIn = 1 ether;
        uint256 nonce    = 200;
        uint256 deadline = block.timestamp + 1 hours;

        vm.deal(alice, amountIn);

        // Path must start with WBNB so the router can pull it after deposit()
        bytes memory path    = abi.encodePacked(WBNB_ADDR, uint24(500), address(tokenOut));
        bytes memory authSig = _signAuth(aliceKey, alice, nonce, deadline);

        IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
            tokenIn:      address(0),        // unused — BNB is native
            tokenOut:     address(tokenOut),
            amountIn:     amountIn,
            amountOutMin: 0,
            recipient:    alice,
            deadline:     deadline,
            permitSig:    "",
            swapData:     path
        });

        IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
            signer:    alice,
            nonce:     nonce,
            deadline:  deadline,
            signature: authSig
        });

        vm.prank(alice);
        uint256 amountOut = routeprim.routeNative{value: amountIn}(params, auth);

        assertEq(amountOut, amountIn);           // 1:1 mock rate
        assertEq(tokenOut.balanceOf(alice), amountIn);
    }
}
