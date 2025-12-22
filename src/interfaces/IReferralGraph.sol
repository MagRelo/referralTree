// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IReferralGraph
 * @notice Interface for the ReferralGraph contract that manages referral relationships
 */
interface IReferralGraph {
    /// @notice Emitted when a user registers with a referrer
    event UserRegistered(address indexed user, address indexed referrer);

    /// @notice Emitted when a referrer is added to the allowlist
    event ReferrerAllowed(address indexed referrer);

    /// @notice Emitted when a referrer is removed from the allowlist
    event ReferrerDisallowed(address indexed referrer);

    /// @notice Emitted when an oracle is authorized
    event OracleAuthorized(address indexed oracle);

    /// @notice Emitted when an oracle is unauthorized
    event OracleUnauthorized(address indexed oracle);

    /// @notice Error when trying to register with invalid referrer
    error InvalidReferrer();

    /// @notice Error when user is already registered
    error AlreadyRegistered();

    /// @notice Error when trying to create a cycle in referral graph
    error CycleDetected();

    /// @notice Error when referrer is not in allowlist (if allowlist is enabled)
    error ReferrerNotAllowed();

    /// @notice Error when caller is not an authorized oracle
    error UnauthorizedOracle();

    /// @notice Get the referrer of a user in a group
    /// @param user The user to query
    /// @param groupId The group ID
    /// @return The address of the referrer, or address(0) if not registered
    function getReferrer(address user, bytes32 groupId) external view returns (address);

    /// @notice Get the children of a referrer in a group
    /// @param referrer The referrer to query
    /// @param groupId The group ID
    /// @return Array of addresses that were referred by this referrer
    function getChildren(address referrer, bytes32 groupId) external view returns (address[] memory);

    /// @notice Get the ancestor chain for a user in a group (from user up to root)
    /// @param user The user to get ancestors for
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of levels to traverse
    /// @return Array of ancestors, starting with immediate referrer
    function getAncestors(address user, bytes32 groupId, uint256 maxLevels) external view returns (address[] memory);

    /// @notice Check if a user is registered in a group
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if the user has a referrer in the group
    function isRegistered(address user, bytes32 groupId) external view returns (bool);

    /// @notice Check if an address is an allowed referrer
    /// @param referrer The address to check
    /// @return True if the address can be a referrer
    function isAllowedReferrer(address referrer) external view returns (bool);

    /// @notice Register a user with a referrer in a group
    /// @param user The user being registered
    /// @param referrer The referrer address (must be in the group's referral tree, or address(0) for root registration)
    /// @param groupId The group ID (group is auto-created on first registration)
    /// @dev Groups are implicitly created when the first user registers. A user is in a group's referral tree if they have been referred or have referred others.
    function register(address user, address referrer, bytes32 groupId) external;

    /// @notice Batch register multiple users with the same referrer in a group
    /// @param users Array of users to register
    /// @param referrer The referrer for all users
    /// @param groupId The group ID
    function batchRegister(address[] calldata users, address referrer, bytes32 groupId) external;

    /// @notice Add a referrer to the allowlist
    /// @param referrer The referrer to allow
    function allowReferrer(address referrer) external;

    /// @notice Remove a referrer from the allowlist
    /// @param referrer The referrer to disallow
    function disallowReferrer(address referrer) external;

    /// @notice Enable or disable the referrer allowlist
    /// @param enabled True to enable allowlist, false to disable
    function setAllowlistEnabled(bool enabled) external;

    /// @notice Check if the allowlist is enabled
    /// @return True if allowlist is enabled
    function isAllowlistEnabled() external view returns (bool);

    /// @notice Get the root address
    /// @return The root address
    function getRoot() external view returns (address);

    /// @notice Authorize an oracle to register referrals
    /// @param oracle The oracle address to authorize
    function authorizeOracle(address oracle) external;

    /// @notice Unauthorize an oracle
    /// @param oracle The oracle address to unauthorize
    function unauthorizeOracle(address oracle) external;

    /// @notice Check if an address is an authorized oracle
    /// @param oracle The address to check
    /// @return True if authorized
    function isAuthorizedOracle(address oracle) external view returns (bool);

    /// @notice Get all authorized oracles
    /// @return Array of authorized oracle addresses
    function getAuthorizedOracles() external view returns (address[] memory);
}

