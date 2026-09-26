// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1271} from "../../src/interfaces/IERC1271.sol";

/// @notice EIP-7702 delegate without ERC-1271 (e.g. a batching-only implementation).
contract NoopDelegate {
    function ping() external pure returns (uint256) {
        return 7702;
    }

    receive() external payable {}
}

/// @notice EIP-7702 delegate implementing ERC-1271 with a session key. Signature format is
///         0x01 || 65-byte ECDSA by `sessionKey` (66 bytes), so it never matches the plain-ECDSA path.
contract SessionKey1271Delegate is IERC1271 {
    address public immutable sessionKey;

    constructor(address _sessionKey) {
        sessionKey = _sessionKey;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (signature.length != 66 || signature[0] != 0x01) return 0xffffffff;
        bytes32 r = bytes32(signature[1:33]);
        bytes32 s = bytes32(signature[33:65]);
        uint8 v = uint8(signature[65]);
        address signer = ecrecover(hash, v, r, s);
        return signer != address(0) && signer == sessionKey ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}
