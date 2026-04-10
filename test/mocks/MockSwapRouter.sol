// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20}    from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Test-only PancakeSwap V3 router stub.
///      Pulls tokenIn from the caller (RoutePrim), mints tokenOut to recipient.
///      Rate is configurable; defaults to 1:1 (1e18 = 100%).
contract MockSwapRouter {
    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    MockERC20 public immutable tokenOut;
    uint256   public rate = 1e18; // amountOut = amountIn * rate / 1e18

    constructor(address _tokenOut) {
        tokenOut = MockERC20(_tokenOut);
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut) {
        // Decode tokenIn from first 20 bytes of the path
        address tokenIn;
        bytes memory path = params.path;
        assembly {
            tokenIn := shr(96, mload(add(path, 32)))
        }

        // Pull tokenIn from RoutePrim (must have approved this contract)
        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        amountOut = params.amountIn * rate / 1e18;
        require(amountOut >= params.amountOutMinimum, "MockSwapRouter: slippage exceeded");

        // Mint tokenOut directly to recipient
        tokenOut.mint(params.recipient, amountOut);
    }
}
