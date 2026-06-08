// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SignatureLib
/// @notice Minimal EIP-191 signature helpers for oracle authorization
library SignatureLib {
    /// @notice Error when a signature is malformed or does not recover to a valid signer
    error InvalidSignature();

    /// @notice Wrap a hash in the Ethereum signed message envelope
    /// @param hash The 32-byte payload hash to sign
    /// @return The EIP-191 digest for `ecrecover`
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /// @notice Recover the signer of a 65-byte ECDSA signature
    /// @param digest The hash that was signed
    /// @param signature The packed `r || s || v` signature
    /// @return signer The recovered signer address
    function recover(bytes32 digest, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) revert InvalidSignature();

        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
}
