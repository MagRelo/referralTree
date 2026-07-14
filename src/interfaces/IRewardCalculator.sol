// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRewardCalculator
 * @notice Interface for geometric referral reward splitting
 */
interface IRewardCalculator {
    /**
     * @notice Calculate reward distribution across recipients
     * @param totalReward Total amount to distribute
     * @param numRecipients Number of recipients (capped at 10)
     * @return amounts Array of reward amounts for each recipient
     */
    function calculateRewards(uint256 totalReward, uint256 numRecipients)
        external
        pure
        returns (uint256[] memory amounts);
}
