// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title EIP7702Helper
/// @notice Utilities for EIP-7702 authority delegation on BNB Chain
/// @dev EIP-7702 allows EOAs to temporarily set their code to a smart contract,
///      enabling batching, sponsorship, and programmable auth flows.
library EIP7702Helper {
    /// @notice Check if an address has delegated its code (EIP-7702 delegation indicator)
    function isDelegated(address account) internal view returns (bool) {
        bytes memory code = account.code;
        // EIP-7702 delegation prefix: 0xef0100
        return code.length == 23 && code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00;
    }

    /// @notice Extract the delegate address from an EIP-7702 delegation
    function getDelegate(address account) internal view returns (address delegate) {
        require(isDelegated(account), "EIP7702Helper: not delegated");
        bytes memory code = account.code;
        assembly {
            delegate := shr(96, mload(add(add(code, 0x20), 3)))
        }
    }
}
