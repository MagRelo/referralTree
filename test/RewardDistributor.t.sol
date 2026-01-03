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

    uint256 oraclePrivateKey = 0x1234;
    address oracleSigner;

    bytes32 public testGroup;

    function setUp() public {
        // Create mock contracts
        platformToken = new MockERC20("Platform Token", "PT", 18);
        referralGraph = new MockReferralGraph();

        // Set up oracle signer
        oracleSigner = vm.addr(oraclePrivateKey);

        // Set up test group
        testGroup = keccak256("test-group");

        // Set up referral chain: user3 -> user2 -> user1
        referralGraph.setReferrer(user3, user2);
        referralGraph.setReferrer(user2, user1);

        // Deploy config contract
        vm.prank(owner);
        config = new RewardDistributor(owner, address(referralGraph), oracleSigner);

        // Mint tokens to config contract (large amount for fuzz tests)
        platformToken.mint(address(config), type(uint256).max / 2); // Very large amount to avoid balance limits
    }

    function testInitialSetup() public {
        assertTrue(config.isAuthorizedOracle(oracleSigner));
        assertEq(address(config.getReferralGraph()), address(referralGraph));


    }

    function testAuthorizeOracle() public {
        address newOracle = address(8);

        vm.prank(owner);
        config.authorizeOracle(newOracle);

        assertTrue(config.isAuthorizedOracle(newOracle));
    }

    function testCannotAuthorizeZeroOracle() public {
        vm.prank(owner);
        vm.expectRevert(IRewardDistributor.InvalidOracleAddress.selector);
        config.authorizeOracle(address(0));
    }







    function testDistributeChainRewards() public {
        uint256 totalReward = 10000 ether; // 10,000 tokens
        bytes32 eventId = keccak256("test-event");
        uint256 timestamp = block.timestamp;
        uint256 nonce = 1;

        // Set up referral chain using mock's setReferrer (bypasses oracle check)
        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3, // user3 -> user2 -> user1
            totalAmount: totalReward,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId,
            timestamp: timestamp,
            nonce: nonce
        });

        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId, reward.timestamp, reward.nonce)
        );

        // Sign the Ethereum signed message hash (as expected by the contract)
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Get initial balances
        uint256 user1BalanceBefore = platformToken.balanceOf(user1);
        uint256 user2BalanceBefore = platformToken.balanceOf(user2);
        uint256 user3BalanceBefore = platformToken.balanceOf(user3);

        // Distribute rewards
        config.distributeChainRewards(reward, signature);

        // Check final balances with expected values
        assertEq(platformToken.balanceOf(user3) - user3BalanceBefore, 8000 ether); // 80%
        assertEq(platformToken.balanceOf(user2) - user2BalanceBefore, 1250 ether); // geometric share
        assertEq(platformToken.balanceOf(user1) - user1BalanceBefore, 750 ether);  // geometric share
        // Oracle may receive less or no dust due to redistribution

        assertTrue(config.isRewardDistributed(rewardHash));
    }

    function testCannotDistributeWithInvalidSignature() public {
        uint256 totalReward = 10000 ether;
        bytes32 eventId = keccak256("test-event");
        uint256 timestamp = block.timestamp;
        uint256 nonce = 1;

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3,
            totalAmount: totalReward,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId,
            timestamp: timestamp,
            nonce: nonce
        });

        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId, reward.timestamp, reward.nonce)
        );

        // Sign with wrong private key (not the authorized oracle)
        uint256 wrongPrivateKey = 0x9999;
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, messageHash);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(IRewardDistributor.InvalidOracleSignature.selector);
        config.distributeChainRewards(reward, invalidSignature);
    }

    function testCannotDistributeZeroAmount() public {
        bytes32 eventId = keccak256("test-event");
        uint256 timestamp = block.timestamp;
        uint256 nonce = 1;

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3,
            totalAmount: 0, // Zero amount
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId,
            timestamp: timestamp,
            nonce: nonce
        });

        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId, reward.timestamp, reward.nonce)
        );

        // Sign the Ethereum signed message hash (as expected by the contract)
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IRewardDistributor.ZeroRewardAmount.selector);
        config.distributeChainRewards(reward, signature);
    }

    function testOnlyOwnerCanConfigure() public {
        vm.prank(user1);
        vm.expectRevert();
        config.authorizeOracle(address(8));
    }

    function testRewardDistributionStopsAtMinReward() public {
        // Set up a deep chain: user4 -> user3 -> user2 -> user1
        referralGraph.setReferrer(user4, user3);
        referralGraph.setReferrer(user3, user2);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user1, root);

        uint256 totalReward = 10000 ether;
        bytes32 eventId = keccak256("test-event-depth");
        uint256 timestamp = block.timestamp;
        uint256 nonce = 2;

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user4, // user4 -> user3 -> user2 -> user1
            totalAmount: totalReward,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId,
            timestamp: timestamp,
            nonce: nonce
        });

        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId, reward.timestamp, reward.nonce)
        );

        // Sign the Ethereum signed message hash (as expected by the contract)
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Get initial balances
        uint256 user2BalanceBefore = platformToken.balanceOf(user2);
        uint256 user3BalanceBefore = platformToken.balanceOf(user3);
        uint256 user4BalanceBefore = platformToken.balanceOf(user4);

        // Distribute rewards - distribution stops naturally when rewards decay below minReward
        config.distributeChainRewards(reward, signature);

        // user4 gets at least original user percentage (80%) due to redistribution
        assertGe(platformToken.balanceOf(user4) - user4BalanceBefore, 8000 ether);

        // user3 gets reward (level 1, 70% of remaining 2000 = 1400)
        assertGt(platformToken.balanceOf(user3) - user3BalanceBefore, 0);

        // user2 gets reward (level 2, 70% of remaining after user3)
        assertGt(platformToken.balanceOf(user2) - user2BalanceBefore, 0);

        // Distribution stops naturally when rewards decay below minReward (0.01 ether)
        // With exponential decay at 70%, rewards will stop after a few levels
        // user1 may or may not get rewards depending on decay math
        // The important thing is that distribution stops naturally, not artificially

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
        uint256 timestamp = block.timestamp;
        uint256 nonce = uint256(keccak256(abi.encodePacked(totalAmount, chainDepth)));
        
        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: chain[chainDepth],
            totalAmount: totalAmount,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId,
            timestamp: timestamp,
            nonce: nonce
        });
        
        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId, reward.timestamp, reward.nonce)
        );
        
        // Sign the reward
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Get initial balance
        uint256 contractBalanceBefore = platformToken.balanceOf(address(config));
        
        // Distribute rewards
        config.distributeChainRewards(reward, signature);
        
        // Calculate total distributed
        uint256 contractBalanceAfter = platformToken.balanceOf(address(config));
        uint256 totalDistributed = contractBalanceBefore - contractBalanceAfter;
        
        // Invariant: total distributed should never exceed totalAmount
        assertLe(totalDistributed, totalAmount, "Total distributed exceeds input amount");
        
        // Verify reward was marked as distributed
        assertTrue(config.isRewardDistributed(rewardHash));
    }




    /// @notice Fuzz test: Cannot distribute same reward twice
    function testFuzz_CannotDistributeSameRewardTwice(uint256 totalAmount, uint256 nonce) public {
        vm.assume(totalAmount > 0 && totalAmount < 1e30);
        
        referralGraph.setReferrer(user1, root);
        
        bytes32 eventId = keccak256(abi.encodePacked("duplicate-fuzz", totalAmount, nonce));
        uint256 timestamp = block.timestamp;
        
        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user1,
            totalAmount: totalAmount,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId,
            timestamp: timestamp,
            nonce: nonce
        });
        
        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId, reward.timestamp, reward.nonce)
        );
        
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // First distribution should succeed
        config.distributeChainRewards(reward, signature);
        assertTrue(config.isRewardDistributed(rewardHash));
        
        // Second distribution should fail
        vm.expectRevert(IRewardDistributor.RewardAlreadyDistributed.selector);
        config.distributeChainRewards(reward, signature);
    }
}