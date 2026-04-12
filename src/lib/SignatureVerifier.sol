// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title SignatureVerifier
/// @notice EIP-712 structured-data signature verification library
/// @dev All functions are pure — no storage reads, safe to call from any context.
library SignatureVerifier {
    bytes32 internal constant AUTH_TYPEHASH =
        keccak256("AuthParams(address signer,uint256 nonce,uint256 deadline)");

    /// @notice Compute the EIP-712 struct hash for an AuthParams tuple
    function hash(address signer, uint256 nonce, uint256 deadline)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(AUTH_TYPEHASH, signer, nonce, deadline));
    }

    /// @notice Build the EIP-712 typed-data digest (ready to pass to ecrecover)
    function digest(bytes32 domainSeparator, bytes32 structHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /// @notice Recover the signer from a compact 65-byte ECDSA signature.
    /// @dev Returns address(0) on a malleable / zero-point signature rather than
    ///      reverting, so callers can handle the result uniformly.
    function recover(
        bytes32 domainSeparator,
        bytes32 structHash,
        bytes calldata sig
    ) internal pure returns (address recovered) {
        if (sig.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8   v;

        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }

        // Reject high-s signatures (EIP-2: canonical form only)
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        recovered = ecrecover(digest(domainSeparator, structHash), v, r, s);
        // ecrecover returns address(0) on failure — propagate as-is for caller to reject
    }
}
