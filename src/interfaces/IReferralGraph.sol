// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IReferralGraph
 * @notice Interface for the ReferralGraph contract that manages referral relationships
 */
interface IReferralGraph {
    /// @notice Emitted when a user registers with a referrer
    event UserRegistered(address indexed user, address indexed referrer);

    /// @notice Emitted when an oracle is authorized for a group
    event OracleAuthorized(bytes32 indexed groupId, address indexed oracle);

    /// @notice Emitted when an oracle is unauthorized for a group
    event OracleUnauthorized(bytes32 indexed groupId, address indexed oracle);

    /// @notice Emitted when an address is added to a group's skip list
    event AddressSkiplisted(bytes32 indexed groupId, address indexed user);

    /// @notice Emitted when an address is removed from a group's skip list
    event AddressUnskiplisted(bytes32 indexed groupId, address indexed user);

    /// @notice Error when user address is invalid (zero address)
    error InvalidUserAddress();

    /// @notice Error when referrer address is invalid (zero address or not in tree)
    error InvalidReferrerAddress();

    /// @notice Error when oracle address is invalid (zero address)
    error InvalidOracleAddress();

    /// @notice Error when trying to refer oneself
    error SelfReferralNotAllowed();

    /// @notice Error when referrer is not in the referral tree
    error ReferrerNotInTree();

    /// @notice Error when user is already registered
    error UserAlreadyRegistered();

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

    /// @notice Get ancestors with skiplisted addresses removed (does not count them toward maxLevels)
    /// @param user The user to get ancestors for
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of non-skiplisted ancestors to return
    /// @return Array of non-skiplisted ancestors, starting with the nearest eligible referrer
    function getPayoutAncestors(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory);

    /// @notice Build the payout chain starting from `user`, omitting skiplisted addresses
    /// @param user First candidate recipient (omitted if skiplisted; walk continues upward)
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of paid recipients to return
    /// @return chain Non-skiplisted addresses from `user` upward, capped at `maxLevels`
    function getPayoutChain(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory chain);

    /// @notice Check if a user is registered in a group
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if the user has a referrer in the group
    function isRegistered(address user, bytes32 groupId) external view returns (bool);

    /// @notice Check if an address is on the skip list for a group
    /// @param user The address to check
    /// @param groupId The group ID
    /// @return True if skiplisted
    function isSkiplisted(address user, bytes32 groupId) external view returns (bool);

    /// @notice Get all skiplisted addresses for a group
    /// @param groupId The group to query
    /// @return Array of skiplisted addresses
    function getSkiplisted(bytes32 groupId) external view returns (address[] memory);

    /// @notice Add or remove an address from a group's skip list
    /// @param user The address to update
    /// @param groupId The group ID
    /// @param skiplisted True to skiplist, false to remove
    /// @dev Only callable by an oracle authorized for `groupId`
    function setSkiplisted(address user, bytes32 groupId, bool skiplisted) external;

    /// @notice Register a user with a referrer in a group
    /// @param user The user being registered
    /// @param referrer The referrer address (must be in the group's referral tree, or REFERRAL_ROOT for root registration)
    /// @param groupId The group ID (group is auto-created on first registration)
    /// @dev Groups are implicitly created when the first user registers. A user is in a group's referral tree if they have been referred or have referred others.
    function register(address user, address referrer, bytes32 groupId) external;

    /// @notice Batch register multiple users with the same referrer in a group
    /// @param users Array of users to register
    /// @param referrer The referrer for all users
    /// @param groupId The group ID
    function batchRegister(address[] calldata users, address referrer, bytes32 groupId) external;

    /// @notice Authorize an oracle to register referrals in a group
    /// @param oracle The oracle address to authorize
    /// @param groupId The group the oracle is authorized for
    function authorizeOracle(address oracle, bytes32 groupId) external;

    /// @notice Unauthorize an oracle for a group
    /// @param oracle The oracle address to unauthorize
    /// @param groupId The group to remove authorization from
    function unauthorizeOracle(address oracle, bytes32 groupId) external;

    /// @notice Check if an address is an authorized oracle for a group
    /// @param oracle The address to check
    /// @param groupId The group to check authorization for
    /// @return True if authorized for the group
    function isAuthorizedOracle(address oracle, bytes32 groupId) external view returns (bool);

    /// @notice Get all authorized oracles for a group
    /// @param groupId The group to query
    /// @return Array of authorized oracle addresses for the group
    function getAuthorizedOracles(bytes32 groupId) external view returns (address[] memory);
}
