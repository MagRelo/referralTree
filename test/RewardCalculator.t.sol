// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RewardCalculator} from "../src/core/RewardCalculator.sol";

/**
 * @title RewardCalculator Tests
 * @notice Unit tests for reward calculation logic
 */
contract RewardCalculatorTest is Test {
    RewardCalculator public calculator;

    function setUp() public {
        calculator = new RewardCalculator();
    }

    function testCalculateRewardsZeroRecipients() public {
        uint256[] memory amounts = calculator.calculateRewards(1000, 0);
        assertEq(amounts.length, 0);
    }

    function testCalculateRewardsOneRecipient() public {
        uint256[] memory amounts = calculator.calculateRewards(1000, 1);
        assertEq(amounts.length, 1);
        assertEq(amounts[0], 1000);
    }

    function testCalculateRewardsThreeRecipients() public {
        uint256[] memory amounts = calculator.calculateRewards(1000, 3);
        assertEq(amounts.length, 3);
        assertEq(amounts[0], 510);
        assertEq(amounts[1], 306);
        assertEq(amounts[2], 184);
        assertEq(amounts[0] + amounts[1] + amounts[2], 1000);
    }

    function testCalculateRewardsSixRecipients() public {
        uint256[] memory amounts = calculator.calculateRewards(1000, 6);
        assertEq(amounts.length, 6);
        assertEq(amounts[0], 419);
        assertEq(amounts[1], 251);
        assertEq(amounts[2], 151);
        assertEq(amounts[3], 90);
        assertEq(amounts[4], 54);
        assertEq(amounts[5], 35); // adjusted for exact sum
        uint256 sum = 0;
        for (uint256 i = 0; i < 6; i++) {
            sum += amounts[i];
        }
        assertEq(sum, 1000);
    }

    function testCalculateRewardsTenRecipients() public {
        uint256[] memory amounts = calculator.calculateRewards(1000, 10);
        assertEq(amounts.length, 10);
        uint256 sum = 0;
        for (uint256 i = 0; i < 10; i++) {
            sum += amounts[i];
        }
        assertEq(sum, 1000);
    }

    function testCalculateRewardsCapAtTen() public {
        uint256[] memory amounts = calculator.calculateRewards(1000, 15);
        assertEq(amounts.length, 10);
        uint256 sum = 0;
        for (uint256 i = 0; i < 10; i++) {
            sum += amounts[i];
        }
        assertEq(sum, 1000);
    }

    function testCalculateRewardsExactSum() public {
        // Test with various amounts
        uint256[] memory amounts = calculator.calculateRewards(1 ether, 5);
        uint256 sum = 0;
        for (uint256 i = 0; i < 5; i++) {
            sum += amounts[i];
        }
        assertEq(sum, 1 ether);
    }
}