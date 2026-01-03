// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RewardCalculator
 * @notice Calculates reward distributions using geometric decay
 * @dev Provides performant reward splitting for referral chains
 */
contract RewardCalculator {
    /**
     * @notice Calculate reward distribution across recipients
     * @param totalReward Total amount to distribute
     * @param numRecipients Number of recipients (capped at 10)
     * @return amounts Array of reward amounts for each recipient
     * @dev Uses geometric decay with 0.6 ratio, ensures exact sum
     */
    function calculateRewards(uint256 totalReward, uint256 numRecipients) external pure returns (uint256[] memory amounts) {
        if (numRecipients == 0) {
            return new uint256[](0);
        }

        if (numRecipients > 10) {
            numRecipients = 10;
        }

        // Geometric weights for 0.6 decay ratio (basis points)
        uint256[10] memory weights = [uint256(10000), 6000, 3600, 2160, 1296, 777, 466, 279, 167, 100];

        // Cumulative sums for 1-10 recipients
        uint256[11] memory cumSums = [uint256(0), 10000, 16000, 19600, 21760, 23056, 23833, 24299, 24578, 24745, 24845];

        amounts = new uint256[](numRecipients);
        uint256 totalSum = cumSums[numRecipients];

        for (uint256 i = 0; i < numRecipients; i++) {
            amounts[i] = totalReward * weights[i] / totalSum;
        }

        // Distribute remainder to first position to maintain geometric decay
        uint256 calculatedSum = 0;
        for (uint256 i = 0; i < numRecipients; i++) {
            calculatedSum += amounts[i];
        }
        uint256 remainder = totalReward - calculatedSum;
        amounts[0] += remainder;
    }
}