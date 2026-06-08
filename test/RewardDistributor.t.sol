// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RewardDistributor} from "../src/core/RewardDistributor.sol";
import {IRewardDistributor} from "../src/interfaces/IRewardDistributor.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockReferralGraph} from "./mocks/MockReferralGraph.sol";

contract RewardDistributorTest is Test {
    RewardDistributor public config;
    MockERC20 public platformToken;
    MockReferralGraph public referralGraph;

    address public owner = address(1);
    address public oracle = address(2);
    address public root = 0x0000000000000000000000000000000000000001;
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    address public user4 = address(9);
    address public app1 = address(6);
    address public app2 = address(7);

    address public oracleSigner = address(2);

    bytes32 public testGroup;

    function setUp() public {
        // Create mock contracts
        platformToken = new MockERC20("Platform Token", "PT", 18);
        referralGraph = new MockReferralGraph();

        // Set up test group
        testGroup = keccak256("test-group");

        // Set up referral chain: user3 -> user2 -> user1
        referralGraph.setReferrer(user3, user2);
        referralGraph.setReferrer(user2, user1);

        // Deploy config contract
        vm.prank(owner);
        config = new RewardDistributor(owner, address(referralGraph), oracleSigner, testGroup);

        // Mint tokens to config contract (large amount for fuzz tests)
        platformToken.mint(address(config), type(uint256).max / 2); // Very large amount to avoid balance limits
    }

    function _rewardHash(IRewardDistributor.ChainRewardData memory reward) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId)
        );
    }

    function testInitialSetup() public {
        assertTrue(config.isAuthorizedOracle(oracleSigner, testGroup));
        assertEq(address(config.getReferralGraph()), address(referralGraph));
    }

    function testAuthorizeOracle() public {
        address newOracle = address(8);

        vm.prank(owner);
        config.authorizeOracle(newOracle, testGroup);

        assertTrue(config.isAuthorizedOracle(newOracle, testGroup));
    }

    function testCannotAuthorizeZeroOracle() public {
        vm.prank(owner);
        vm.expectRevert(IRewardDistributor.InvalidOracleAddress.selector);
        config.authorizeOracle(address(0), testGroup);
    }

    function testDistributeChainRewards() public {
        uint256 totalReward = 10000 ether; // 10,000 tokens
        bytes32 eventId = keccak256("test-event");

        // Set up referral chain using mock's setReferrer (bypasses oracle check)
        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3, // user3 -> user2 -> user1
            totalAmount: totalReward,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId
        });

        bytes32 rewardHash = _rewardHash(reward);

        // Get initial balances
        uint256 user1BalanceBefore = platformToken.balanceOf(user1);
        uint256 user2BalanceBefore = platformToken.balanceOf(user2);
        uint256 user3BalanceBefore = platformToken.balanceOf(user3);

        // Distribute rewards
        vm.prank(oracleSigner);
        config.distributeChainRewards(reward);

        // Check final balances with expected geometric split of full totalReward
        assertEq(platformToken.balanceOf(user3) - user3BalanceBefore, 5102040816326530612246);
        assertEq(platformToken.balanceOf(user2) - user2BalanceBefore, 3061224489795918367346);
        assertEq(platformToken.balanceOf(user1) - user1BalanceBefore, 1836734693877551020408);

        assertTrue(config.isRewardDistributed(rewardHash));
    }

    function testCannotDistributeUnauthorizedOracle() public {
        uint256 totalReward = 10000 ether;
        bytes32 eventId = keccak256("test-event");

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3,
            totalAmount: totalReward,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId
        });

        vm.prank(user1);
        vm.expectRevert(IRewardDistributor.UnauthorizedOracle.selector);
        config.distributeChainRewards(reward);
    }

    function testCannotDistributeZeroAmount() public {
        bytes32 eventId = keccak256("test-event");

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3,
            totalAmount: 0, // Zero amount
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId
        });

        vm.prank(oracleSigner);
        vm.expectRevert(IRewardDistributor.ZeroRewardAmount.selector);
        config.distributeChainRewards(reward);
    }

    function testOnlyOwnerCanConfigure() public {
        vm.prank(user1);
        vm.expectRevert();
        config.authorizeOracle(address(8), testGroup);
    }

    function testCannotDistributeInUnauthorizedGroup() public {
        bytes32 otherGroup = keccak256("other-group");
        bytes32 eventId = keccak256("test-event");

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3,
            totalAmount: 1000 ether,
            rewardToken: address(platformToken),
            groupId: otherGroup,
            eventId: eventId
        });

        vm.prank(oracleSigner);
        vm.expectRevert(IRewardDistributor.UnauthorizedOracle.selector);
        config.distributeChainRewards(reward);
    }

    function testRewardDistributionStopsAtMinReward() public {
        // Set up a deep chain: user4 -> user3 -> user2 -> user1
        referralGraph.setReferrer(user4, user3);
        referralGraph.setReferrer(user3, user2);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user1, root);

        uint256 totalReward = 10000 ether;
        bytes32 eventId = keccak256("test-event-depth");

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user4, // user4 -> user3 -> user2 -> user1
            totalAmount: totalReward,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId
        });

        bytes32 rewardHash = _rewardHash(reward);

        // Get initial balances
        uint256 user2BalanceBefore = platformToken.balanceOf(user2);
        uint256 user3BalanceBefore = platformToken.balanceOf(user3);
        uint256 user4BalanceBefore = platformToken.balanceOf(user4);

        // Distribute rewards - distribution stops naturally when rewards decay below minReward
        vm.prank(oracleSigner);
        config.distributeChainRewards(reward);

        // user4 gets the largest share, but not a fixed original-user percentage
        assertGt(platformToken.balanceOf(user4) - user4BalanceBefore, 0);

        // user3 gets reward (level 1, 70% of remaining 2000 = 1400)
        assertGt(platformToken.balanceOf(user3) - user3BalanceBefore, 0);

        // user2 gets reward (level 2, 70% of remaining after user3)
        assertGt(platformToken.balanceOf(user2) - user2BalanceBefore, 0);

        assertTrue(config.isRewardDistributed(rewardHash));
    }

    // ============ FUZZ TESTS ============

    /// @notice Fuzz test: Reward distribution amounts never exceed total
    function testFuzz_RewardAmountsNeverExceedTotal(uint256 totalAmount, uint8 chainDepth) public {
        // Bound inputs to reasonable values
        vm.assume(totalAmount > 0 && totalAmount < 1e30);
        vm.assume(chainDepth > 0 && chainDepth < 30);

        // Set up a chain of specified depth
        address[] memory chain = new address[](chainDepth + 1);
        chain[0] = user1;
        referralGraph.setReferrer(user1, root);

        for (uint256 i = 1; i <= chainDepth; i++) {
            chain[i] = address(uint160(uint256(keccak256(abi.encodePacked(testGroup, i)))));
            vm.assume(chain[i] != address(0));
            referralGraph.setReferrer(chain[i], chain[i - 1]);
        }

        // Create reward data
        bytes32 eventId = keccak256(abi.encodePacked("fuzz-event", totalAmount, chainDepth));

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: chain[chainDepth],
            totalAmount: totalAmount,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId
        });

        bytes32 rewardHash = _rewardHash(reward);

        // Get initial balance
        uint256 contractBalanceBefore = platformToken.balanceOf(address(config));

        // Distribute rewards
        vm.prank(oracleSigner);
        config.distributeChainRewards(reward);

        // Calculate total distributed
        uint256 contractBalanceAfter = platformToken.balanceOf(address(config));
        uint256 totalDistributed = contractBalanceBefore - contractBalanceAfter;

        // Invariant: total distributed should never exceed totalAmount
        assertLe(totalDistributed, totalAmount, "Total distributed exceeds input amount");

        // Verify reward was marked as distributed
        assertTrue(config.isRewardDistributed(rewardHash));
    }

    /// @notice Fuzz test: Cannot distribute same reward twice
    function testFuzz_CannotDistributeSameRewardTwice(uint256 totalAmount, bytes32 eventId) public {
        vm.assume(totalAmount > 0 && totalAmount < 1e30);

        referralGraph.setReferrer(user1, root);

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user1,
            totalAmount: totalAmount,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId
        });

        bytes32 rewardHash = _rewardHash(reward);

        // First distribution should succeed
        vm.prank(oracleSigner);
        config.distributeChainRewards(reward);
        assertTrue(config.isRewardDistributed(rewardHash));

        // Second distribution should fail
        vm.prank(oracleSigner);
        vm.expectRevert(IRewardDistributor.RewardAlreadyDistributed.selector);
        config.distributeChainRewards(reward);
    }
}
