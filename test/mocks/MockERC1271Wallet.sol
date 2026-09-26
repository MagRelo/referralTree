// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1271} from "../../src/interfaces/IERC1271.sol";

/// @notice Owner-key ERC-1271 wallet with configurable (mis)behaviour for signature-verification tests.
contract MockERC1271Wallet is IERC1271 {
    enum Mode {
        Valid, // magic iff `signature` is the owner's 65-byte ECDSA signature over `hash`, else 0xffffffff
        WrongMagic, // always returns a non-magic bytes4
        DirtyMagic, // magic selector with non-zero trailing bytes in the returned word
        Revert, // always reverts
        Empty, // returns no data
        Short, // returns only 4 bytes (the magic value, unpadded)
        GasBurn // burns all forwarded gas
    }

    bytes4 internal constant MAGIC = 0x1626ba7e;

    address public immutable owner;
    Mode public mode;

    constructor(address _owner) {
        owner = _owner;
    }

    function setMode(Mode _mode) external {
        mode = _mode;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        Mode m = mode;
        if (m == Mode.WrongMagic) return 0xdeadbeef;
        if (m == Mode.Revert) revert("NOPE");
        if (m == Mode.Empty) {
            assembly {
                return(0, 0)
            }
        }
        if (m == Mode.Short) {
            assembly {
                mstore(0, shl(224, 0x1626ba7e))
                return(0, 4)
            }
        }
        if (m == Mode.DirtyMagic) {
            assembly {
                mstore(0, or(shl(224, 0x1626ba7e), 1))
                return(0, 32)
            }
        }
        if (m == Mode.GasBurn) {
            uint256 i;
            while (true) {
                unchecked {
                    ++i;
                }
            }
        }

        if (signature.length != 65) return 0xffffffff;
        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);
        uint8 v = uint8(signature[64]);
        address signer = ecrecover(hash, v, r, s);
        return signer != address(0) && signer == owner ? MAGIC : bytes4(0xffffffff);
    }
}
