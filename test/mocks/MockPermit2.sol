// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPermit2} from "../../src/interfaces/IPermit2.sol";
import {IERC20}   from "../../src/interfaces/IERC20.sol";

/// @dev Test-only Permit2 stub. Skips signature verification and executes
///      a plain transferFrom so tests can focus on RoutePrim auth logic.
contract MockPermit2 {
    function permitTransferFrom(
        IPermit2.PermitTransferFrom calldata permit,
        IPermit2.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata /*signature*/
    ) external {
        IERC20(permit.permitted.token).transferFrom(
            owner,
            transferDetails.to,
            transferDetails.requestedAmount
        );
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        IERC20(token).transferFrom(from, to, uint256(amount));
    }

    function allowance(address, address, address)
        external
        pure
        returns (uint160, uint48, uint48)
    {
        return (type(uint160).max, type(uint48).max, 0);
    }
}
