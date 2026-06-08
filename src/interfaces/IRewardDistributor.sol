// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IReferralGraph} from "./IReferralGraph.sol";

/**
 * @title IRewardDistributor
 * @notice Interface for the reward distribution contract with oracle-based chain rewards
 */
interface IRewardDistributor {
    /// @notice Chain reward distribution data
    struct ChainRewardData {
        address user;           // First referrer in the payout chain (largest share)
        uint256 totalAmount;    // Bonus amount to distribute across referral recipients
        address rewardToken;    // Token to distribute as rewards
        bytes32 groupId;        // User group for referral chain lookup
        bytes32 eventId;        // Unique event identifier
    }

    /// @notice Emitted when an oracle is authorized for a group
    event OracleAuthorized(bytes32 indexed groupId, address indexed oracle);

    /// @notice Emitted when an oracle is unauthorized for a group
    event OracleUnauthorized(bytes32 indexed groupId, address indexed oracle);

    /// @notice Emitted when chain rewards are distributed
    /// @param user First referrer in the payout chain
    /// @param totalAmount Total referral bonus distributed
    /// @param eventId Unique event identifier from the signed reward data
    /// @param recipients Addresses that received rewards, ordered from first referrer upward
    /// @param amounts Reward amount for each entry in `recipients`
    event ChainRewardsDistributed(
        address indexed user,
        uint256 totalAmount,
        bytes32 indexed eventId,
        address[] recipients,
        uint256[] amounts
    );

    /// @notice Error when oracle address is invalid (zero address)
    error InvalidOracleAddress();

    /// @notice Error when oracle signature is invalid or signer is not authorized for the group
    error InvalidOracleSignature();

    /// @notice Error when reward has already been distributed
    error RewardAlreadyDistributed();

    /// @notice Error when trying to set invalid parameters
    error InvalidParameters();

    /// @notice Error when app is not authorized
    error UnauthorizedApp();

    /// @notice Error when reward amount is zero
    error ZeroRewardAmount();

    /// @notice Get the referral graph contract
    /// @return Referral graph address
    function getReferralGraph() external view returns (IReferralGraph);

    /// @notice Check if a reward has been distributed
    /// @param rewardHash The hash of the reward data
    /// @return True if distributed
    function isRewardDistributed(bytes32 rewardHash) external view returns (bool);

    /// @notice Authorize an oracle to distribute rewards in a group
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

    /// @notice Distribute rewards across a referral chain
    /// @param reward The chain reward data
    /// @param signature Oracle signature over the reward hash (EIP-191)
    /// @dev Callable by any address. Signer must be authorized for `reward.groupId`. Walks upward from `reward.user` through referrers and distributes full `totalAmount`
    function distributeChainRewards(ChainRewardData calldata reward, bytes calldata signature) external;
}