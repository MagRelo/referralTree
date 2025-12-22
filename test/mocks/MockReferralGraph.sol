// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IReferralGraph} from "../../src/interfaces/IReferralGraph.sol";

contract MockReferralGraph is IReferralGraph {
    mapping(address => address) private _referrers;
    mapping(address => address[]) private _children;
    mapping(address => bool) private _allowedReferrers;
    bool private _allowlistEnabled;
    address private _root;
    mapping(address => bool) private _authorizedOracles;
    address[] private _authorizedOraclesList;

    constructor(address root) {
        _root = root;
        // In mock, authorize address(0) as default oracle to allow any caller
        _authorizedOracles[address(0)] = true;
    }

    function setReferrer(address user, address referrer) external {
        _referrers[user] = referrer;
    }

    function getReferrer(address user, bytes32 /* groupId */) external view returns (address) {
        return _referrers[user]; // Mock ignores group for simplicity
    }


    function getReferrers(address user) external view returns (address[] memory) {
        // Simplified implementation for testing
        address[] memory result = new address[](5);
        uint256 count = 0;
        address current = user;

        while (current != address(0) && count < 5) {
            current = _referrers[current];
            if (current != address(0)) {
                result[count] = current;
                count++;
            }
        }

        // Resize array
        address[] memory finalResult = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            finalResult[i] = result[i];
        }

        return finalResult;
    }

    function getAncestors(address user, uint256 maxLevels) external view returns (address[] memory) {
        address[] memory ancestors = new address[](maxLevels);
        uint256 count = 0;
        address current = _referrers[user];

        while (current != address(0) && count < maxLevels) {
            ancestors[count] = current;
            count++;
            current = _referrers[current];
        }

        // Resize array
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ancestors[i];
        }

        return result;
    }

    function getChildren(address referrer, bytes32 /* groupId */) external view returns (address[] memory) {
        return _children[referrer]; // Mock ignores group for simplicity
    }


    function addReferral(address user, address referrer) external {
        _referrers[user] = referrer;
    }

    function register(address user, address referrer, bytes32 /* groupId */) external {
        _referrers[user] = referrer; // Mock ignores group for simplicity
    }



    function getReferralDepth(address user) external view returns (uint256) {
        uint256 depth = 0;
        address current = user;

        while (current != address(0) && depth < 10) {
            current = _referrers[current];
            if (current != address(0)) {
                depth++;
            }
        }

        return depth;
    }

    function isValidReferral(address user, address referrer) external view returns (bool) {
        return _referrers[user] == referrer;
    }

    function isRegistered(address user, bytes32 /* groupId */) external view returns (bool) {
        return _referrers[user] != address(0); // Mock ignores group for simplicity
    }


    function isAllowedReferrer(address referrer) external view returns (bool) {
        return _allowedReferrers[referrer];
    }

    function allowReferrer(address referrer) external {
        _allowedReferrers[referrer] = true;
    }

    function disallowReferrer(address referrer) external {
        _allowedReferrers[referrer] = false;
    }

    function setAllowlistEnabled(bool enabled) external {
        _allowlistEnabled = enabled;
    }

    function isAllowlistEnabled() external view returns (bool) {
        return _allowlistEnabled;
    }

    function getReferralChain(address user) external view returns (address[] memory) {
        address[] memory chain = new address[](10);
        uint256 length = 0;
        address current = user;

        while (current != address(0) && length < 10) {
            chain[length] = current;
            length++;
            current = _referrers[current];
        }

        // Resize array
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = chain[i];
        }

        return result;
    }


    function getAncestors(address /* user */, bytes32 /* groupId */, uint256 /* maxLevels */) external pure returns (address[] memory) {
        // Simplified mock implementation
        return new address[](0);
    }

    function batchRegister(address[] calldata users, address referrer, bytes32 groupId) external {
        // Mock implementation - do nothing
    }

    function getRoot() external view returns (address) {
        return _root;
    }

    function authorizeOracle(address oracle) external {
        if (!_authorizedOracles[oracle]) {
            _authorizedOracles[oracle] = true;
            _authorizedOraclesList.push(oracle);
            emit OracleAuthorized(oracle);
        }
    }

    function unauthorizeOracle(address oracle) external {
        if (_authorizedOracles[oracle]) {
            _authorizedOracles[oracle] = false;
            for (uint256 i = 0; i < _authorizedOraclesList.length; i++) {
                if (_authorizedOraclesList[i] == oracle) {
                    _authorizedOraclesList[i] = _authorizedOraclesList[_authorizedOraclesList.length - 1];
                    _authorizedOraclesList.pop();
                    break;
                }
            }
            emit OracleUnauthorized(oracle);
        }
    }

    function isAuthorizedOracle(address /* oracle */) external pure returns (bool) {
        // In mock, allow any caller (for testing simplicity)
        return true;
    }

    function getAuthorizedOracles() external view returns (address[] memory) {
        return _authorizedOraclesList;
    }
}