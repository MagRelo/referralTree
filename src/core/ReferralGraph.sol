// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IReferralGraph} from "../interfaces/IReferralGraph.sol";

/**
 * @title ReferralGraph
 * @notice Manages referral relationships in a tree structure
 */
contract ReferralGraph is IReferralGraph, Ownable {
    /// @notice Special address representing the root of all referral trees
    address public constant REFERRAL_ROOT = address(0x0000000000000000000000000000000000000001);

    /// @notice Maps group -> user -> referrer
    mapping(bytes32 => mapping(address => address)) private _referrers;

    /// @notice Maps group -> referrer -> children
    mapping(bytes32 => mapping(address => address[])) private _children;

    /// @notice Authorized oracle addresses that can register referrals
    mapping(address => bool) private _authorizedOracles;

    /// @notice List of authorized oracles for enumeration
    address[] private _authorizedOraclesList;

     /**
      * @notice Constructor
      * @param initialOwner The initial owner of the contract
      * @param initialOracle Initial oracle address to authorize (optional, can be address(0))
      */
    constructor(
        address initialOwner,
        address initialOracle
    ) Ownable(initialOwner) {

        // If initial oracle is set, authorize it
        if (initialOracle != address(0)) {
            _authorizedOracles[initialOracle] = true;
            _authorizedOraclesList.push(initialOracle);
            emit OracleAuthorized(initialOracle);
        }
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

    /// @notice Check if a user is registered in a group
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if the user has a referrer in the group
    function isRegistered(address user, bytes32 groupId) external view returns (bool) {
        return _referrers[groupId][user] != address(0);
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

    /// @notice Modifier to restrict functions to authorized oracles only
    modifier onlyAuthorizedOracle() {
        if (!_authorizedOracles[msg.sender]) {
            revert UnauthorizedOracle();
        }
        _;
    }

    /// @notice Internal function to register a user with a referrer
    /// @param user The user being registered
    /// @param referrer The referrer address
    /// @param groupId The group ID
    function _register(address user, address referrer, bytes32 groupId) internal {
        if (user == address(0)) revert InvalidReferrer();
        if (referrer == address(0)) revert InvalidReferrer(); // Must have referrer
        if (referrer == user) revert InvalidReferrer();
        if (_referrers[groupId][user] != address(0)) revert AlreadyRegistered();

        // If referrer provided, they must be in the referral tree
        // Exception: root is always allowed as referrer if set (for first registration)
        if (referrer != REFERRAL_ROOT && !_isInReferralTree(referrer, groupId)) {
            revert InvalidReferrer(); // Referrer must be in the group's referral tree
        }

        _referrers[groupId][user] = referrer;
        _children[groupId][referrer].push(user);

        emit UserRegistered(user, referrer);
    }

    /// @inheritdoc IReferralGraph
    function register(address user, address referrer, bytes32 groupId) external onlyAuthorizedOracle {
        _register(user, referrer, groupId);
    }

    /// @notice Batch register multiple users with the same referrer in a group
    /// @param users Array of users to register
    /// @param referrer The referrer for all users
    /// @param groupId The group ID
    function batchRegister(address[] calldata users, address referrer, bytes32 groupId) external onlyAuthorizedOracle {
        for (uint256 i = 0; i < users.length; i++) {
            _register(users[i], referrer, groupId);
        }
    }



    /// @inheritdoc IReferralGraph
    function authorizeOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert InvalidReferrer();
        if (!_authorizedOracles[oracle]) {
            _authorizedOracles[oracle] = true;
            _authorizedOraclesList.push(oracle);
            emit OracleAuthorized(oracle);
        }
    }

    /// @inheritdoc IReferralGraph
    function unauthorizeOracle(address oracle) external onlyOwner {
        if (_authorizedOracles[oracle]) {
            _authorizedOracles[oracle] = false;

            // Remove from list
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

    /// @inheritdoc IReferralGraph
    function isAuthorizedOracle(address oracle) external view returns (bool) {
        return _authorizedOracles[oracle];
    }

    /// @inheritdoc IReferralGraph
    function getAuthorizedOracles() external view returns (address[] memory) {
        return _authorizedOraclesList;
    }
}