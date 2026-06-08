// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Owned} from "solmate/auth/Owned.sol";
import {IReferralGraph} from "../interfaces/IReferralGraph.sol";

/**
 * @title ReferralGraph
 * @notice Manages referral relationships in a tree structure
 */
contract ReferralGraph is IReferralGraph, Owned {
    /// @notice Special address representing the root of all referral trees
    address public constant REFERRAL_ROOT = address(0x0000000000000000000000000000000000000001);

    /// @notice Maps group -> user -> referrer
    mapping(bytes32 => mapping(address => address)) private _referrers;

    /// @notice Maps group -> referrer -> children
    mapping(bytes32 => mapping(address => address[])) private _children;

    /// @notice Authorized oracle addresses per group that can register referrals
    mapping(bytes32 => mapping(address => bool)) private _authorizedOracles;

    /// @notice List of authorized oracles per group for enumeration
    mapping(bytes32 => address[]) private _authorizedOraclesList;

     /**
      * @notice Constructor
      * @param initialOwner The initial owner of the contract
      * @param initialOracle Initial oracle address to authorize (optional, can be address(0))
      * @param initialGroupId Group to authorize the initial oracle for
      */
    constructor(
        address initialOwner,
        address initialOracle,
        bytes32 initialGroupId
    ) Owned(initialOwner) {
        if (initialOracle != address(0)) {
            _authorizedOracles[initialGroupId][initialOracle] = true;
            _authorizedOraclesList[initialGroupId].push(initialOracle);
            emit OracleAuthorized(initialGroupId, initialOracle);
        }
    }

    /// @notice Check if a user is registered in a group
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if the user has a referrer in the group
    function isRegistered(address user, bytes32 groupId) external view returns (bool) {
        return _referrers[groupId][user] != address(0);
    }


    /// @notice Get the referrer of a user in a group
    /// @param user The user to query
    /// @param groupId The group ID
    /// @return The address of the referrer, or address(0) if not registered
    function getReferrer(address user, bytes32 groupId) external view returns (address) {
        return _referrers[groupId][user];
    }

    /// @notice Get the children of a referrer in a group
    /// @param referrer The referrer to query
    /// @param groupId The group ID
    /// @return Array of addresses that were referred by this referrer
    function getChildren(address referrer, bytes32 groupId) external view returns (address[] memory) {
        return _children[groupId][referrer];
    }

    /// @notice Get the ancestor chain for a user in a group
    /// @param user The user to get ancestors for
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of levels to traverse
    /// @return Array of ancestors, starting with immediate referrer
    function getAncestors(address user, bytes32 groupId, uint256 maxLevels) external view returns (address[] memory) {
        if (user == address(0) || user == REFERRAL_ROOT) {
            return new address[](0);
        }

        address[] memory ancestors = new address[](maxLevels);
        uint256 count = 0;
        address current = _referrers[groupId][user];

        while (current != address(0) && current != REFERRAL_ROOT && count < maxLevels) {
            ancestors[count] = current;
            current = _referrers[groupId][current];
            count++;
        }

        // Trim the array to actual length
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ancestors[i];
        }

        return result;
    }

    /// @notice Check if a user is in a group's referral tree
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if user appears in the referral tree (has been referred or has referred others, or is root)
    function _isInReferralTree(address user, bytes32 groupId) internal view returns (bool) {
        // Root is always considered in the tree if set
        if (user == REFERRAL_ROOT && REFERRAL_ROOT != address(0)) return true;
        // User is in tree if they have been referred OR they have referred others
        return _referrers[groupId][user] != address(0) || _children[groupId][user].length > 0;
    }

    /// @notice Internal function to register a user with a referrer
    /// @param user The user being registered
    /// @param referrer The referrer address
    /// @param groupId The group ID
    function _register(address user, address referrer, bytes32 groupId) internal {
        if (user == address(0)) revert InvalidUserAddress();
        if (referrer == address(0)) revert InvalidReferrerAddress();
        if (referrer == user) revert SelfReferralNotAllowed();
        if (_referrers[groupId][user] != address(0)) revert UserAlreadyRegistered();

        // If referrer provided, they must be in the referral tree
        // Exception: root is always allowed as referrer if set (for first registration)
        if (referrer != REFERRAL_ROOT && !_isInReferralTree(referrer, groupId)) {
            revert ReferrerNotInTree();
        }

        _referrers[groupId][user] = referrer;
        _children[groupId][referrer].push(user);

        emit UserRegistered(user, referrer);
    }

    /// @notice Modifier to restrict functions to oracles authorized for a group
    modifier onlyAuthorizedOracle(bytes32 groupId) {
        if (!_authorizedOracles[groupId][msg.sender]) {
            revert UnauthorizedOracle();
        }
        _;
    }

    /// @inheritdoc IReferralGraph
    function register(address user, address referrer, bytes32 groupId) external onlyAuthorizedOracle(groupId) {
        _register(user, referrer, groupId);
    }

    /// @notice Batch register multiple users with the same referrer in a group
    /// @param users Array of users to register
    /// @param referrer The referrer for all users
    /// @param groupId The group ID
    function batchRegister(address[] calldata users, address referrer, bytes32 groupId)
        external
        onlyAuthorizedOracle(groupId)
    {
        for (uint256 i = 0; i < users.length; i++) {
            _register(users[i], referrer, groupId);
        }
    }

    /// @inheritdoc IReferralGraph
    function authorizeOracle(address oracle, bytes32 groupId) external onlyOwner {
        if (oracle == address(0)) revert InvalidOracleAddress();
        if (!_authorizedOracles[groupId][oracle]) {
            _authorizedOracles[groupId][oracle] = true;
            _authorizedOraclesList[groupId].push(oracle);
            emit OracleAuthorized(groupId, oracle);
        }
    }

    /// @inheritdoc IReferralGraph
    function unauthorizeOracle(address oracle, bytes32 groupId) external onlyOwner {
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

    /// @inheritdoc IReferralGraph
    function isAuthorizedOracle(address oracle, bytes32 groupId) external view returns (bool) {
        return _authorizedOracles[groupId][oracle];
    }

    /// @inheritdoc IReferralGraph
    function getAuthorizedOracles(bytes32 groupId) external view returns (address[] memory) {
        return _authorizedOraclesList[groupId];
    }
}