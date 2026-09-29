// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IERC1271
/// @notice Standard signature validation for contracts (https://eips.ethereum.org/EIPS/eip-1271)
interface IERC1271 {
    /// @notice Returns the magic value 0x1626ba7e if `signature` is valid for `hash`
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}
