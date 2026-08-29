// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IReferralGraph} from "../../src/interfaces/IReferralGraph.sol";

contract MockReferralGraph is IReferralGraph {
    address public constant REFERRAL_ROOT = address(0x0000000000000000000000000000000000000001);

    mapping(address => address) private _referrers;
    mapping(address => address[]) private _children;
    mapping(bytes32 => mapping(address => bool)) private _authorizedOracles;
    mapping(bytes32 => address[]) private _authorizedOraclesList;
    mapping(bytes32 => mapping(address => bool)) private _skiplisted;
    mapping(bytes32 => address[]) private _skiplistedList;

    function setReferrer(address user, address referrer) external {
        _referrers[user] = referrer;
    }

    function getReferrer(address user, bytes32 /* groupId */) external view returns (address) {
        return _referrers[user];
    }

    function getChildren(address referrer, bytes32 /* groupId */) external view returns (address[] memory) {
        return _children[referrer];
    }

    function getAncestors(address user, bytes32 /* groupId */, uint256 maxLevels)
        external
        view
        returns (address[] memory)
    {
        address[] memory ancestors = new address[](maxLevels);
        uint256 count = 0;
        address current = _referrers[user];

        while (current != address(0) && current != REFERRAL_ROOT && count < maxLevels) {
            ancestors[count] = current;
            count++;
            current = _referrers[current];
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ancestors[i];
        }
        return result;
    }

    function getPayoutAncestors(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory)
    {
        if (user == address(0) || user == REFERRAL_ROOT || maxLevels == 0) {
            return new address[](0);
        }

        address[] memory ancestors = new address[](maxLevels);
        uint256 count = 0;
        address current = _referrers[user];

        while (current != address(0) && current != REFERRAL_ROOT && count < maxLevels) {
            if (!_skiplisted[groupId][current]) {
                ancestors[count] = current;
                count++;
            }
            current = _referrers[current];
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ancestors[i];
        }
        return result;
    }

    function getPayoutChain(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory chain)
    {
        if (user == address(0) || user == REFERRAL_ROOT || maxLevels == 0) {
            return new address[](0);
        }

        address[] memory buffer = new address[](maxLevels);
        uint256 length = 0;
        address current = user;

        while (current != address(0) && current != REFERRAL_ROOT && length < maxLevels) {
            if (!_skiplisted[groupId][current]) {
                buffer[length++] = current;
            }
            current = _referrers[current];
        }

        chain = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            chain[i] = buffer[i];
        }
    }

    function isSkiplisted(address user, bytes32 groupId) external view returns (bool) {
        return _skiplisted[groupId][user];
    }

    function getSkiplisted(bytes32 groupId) external view returns (address[] memory) {
        return _skiplistedList[groupId];
    }

    function registeredCount(bytes32 /* groupId */) external pure returns (uint256) {
        return 0;
    }

    function skiplistedCount(bytes32 groupId) external view returns (uint256) {
        return _skiplistedList[groupId].length;
    }

    function setSkiplisted(address user, bytes32 groupId, bool skiplisted) external {
        if (user == address(0) || user == REFERRAL_ROOT) revert InvalidUserAddress();

        if (skiplisted) {
            if (!_skiplisted[groupId][user]) {
                _skiplisted[groupId][user] = true;
                _skiplistedList[groupId].push(user);
                emit AddressSkiplisted(groupId, user);
            }
        } else if (_skiplisted[groupId][user]) {
            _skiplisted[groupId][user] = false;
            address[] storage list = _skiplistedList[groupId];
            for (uint256 i = 0; i < list.length; i++) {
                if (list[i] == user) {
                    list[i] = list[list.length - 1];
                    list.pop();
                    break;
                }
            }
            emit AddressUnskiplisted(groupId, user);
        }
    }

    function register(address user, address referrer, bytes32 /* groupId */) external {
        _referrers[user] = referrer;
    }

    function batchRegister(address[] calldata users, address referrer, bytes32 /* groupId */) external {
        for (uint256 i = 0; i < users.length; i++) {
            _referrers[users[i]] = referrer;
        }
    }

    function isRegistered(address user, bytes32 /* groupId */) external view returns (bool) {
        return _referrers[user] != address(0);
    }

    function authorizeOracle(address oracle, bytes32 groupId) external {
        if (!_authorizedOracles[groupId][oracle]) {
            _authorizedOracles[groupId][oracle] = true;
            _authorizedOraclesList[groupId].push(oracle);
            emit OracleAuthorized(groupId, oracle);
        }
    }

    function unauthorizeOracle(address oracle, bytes32 groupId) external {
        if (_authorizedOracles[groupId][oracle]) {
            _authorizedOracles[groupId][oracle] = false;
            address[] storage oracles = _authorizedOraclesList[groupId];
            for (uint256 i = 0; i < oracles.length; i++) {
                if (oracles[i] == oracle) {
                    oracles[i] = oracles[oracles.length - 1];
                    oracles.pop();
                    break;
                }
            }
            emit OracleUnauthorized(groupId, oracle);
        }
    }

    function isAuthorizedOracle(address /* oracle */, bytes32 /* groupId */) external pure returns (bool) {
        return true;
    }

    function getAuthorizedOracles(bytes32 groupId) external view returns (address[] memory) {
        return _authorizedOraclesList[groupId];
    }
}
