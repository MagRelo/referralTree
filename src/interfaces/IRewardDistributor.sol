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
        address user;           // User who triggered the event
        uint256 totalAmount;    // Base amount from which referral percentages are calculated
        address rewardToken;    // Token to distribute as rewards
        bytes32 groupId;        // User group for referral chain calculation
        bytes32 eventId;        // Unique event identifier
        uint256 timestamp;      // When distribution was computed
        uint256 nonce;          // Prevents replay attacks
    }

    /// @notice Emitted when an oracle is authorized
    event OracleAuthorized(address indexed oracle);

    /// @notice Emitted when an oracle is unauthorized
    event OracleUnauthorized(address indexed oracle);

    /// @notice Emitted when chain rewards are distributed
    /// @dev totalAmount is the base amount, amounts array shows actual distributed amounts
    event ChainRewardsDistributed(
        address indexed user,
        uint256 totalAmount,
        bytes32 indexed eventId,
        address[] recipients,
        uint256[] amounts
    );

    /// @notice Error when oracle signature is invalid
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

    /// @notice Get the percentage allocated to the original user
    /// @return Percentage in basis points (e.g., 8000 = 80%)
    function getOriginalUserPercentage() external view returns (uint256);

    /// @notice Check if a reward has been distributed
    /// @param rewardHash The hash of the reward data
    /// @return True if distributed
    function isRewardDistributed(bytes32 rewardHash) external view returns (bool);

    /// @notice Authorize an oracle to sign reward distributions
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

    /// @notice Set the percentage allocated to the original user
    /// @param percentage Percentage in basis points (max 10000 = 100%)
    function setOriginalUserPercentage(uint256 percentage) external;

    /// @notice Distribute rewards across referral chain
    /// @param reward The chain reward data containing base amount for percentage calculations
    /// @param signature Oracle signature of the reward data
    /// @dev Only distributes to referrers based on decay percentages, not the full totalAmount
    function distributeChainRewards(ChainRewardData calldata reward, bytes calldata signature) external;
}