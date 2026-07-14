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
    address public root = 0x0000000000000000000000000000000000000001;
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    address public user4 = address(9);

    uint256 oraclePrivateKey = 0x1234;
    address public oracleSigner;

    bytes32 public testGroup;

    function setUp() public {
        platformToken = new MockERC20("Platform Token", "PT", 18);
        referralGraph = new MockReferralGraph();

        oracleSigner = vm.addr(oraclePrivateKey);
        testGroup = keccak256("test-group");

        referralGraph.setReferrer(user3, user2);
        referralGraph.setReferrer(user2, user1);

        vm.prank(owner);
        config = new RewardDistributor(owner, address(referralGraph), oracleSigner, testGroup);

        platformToken.mint(address(config), type(uint256).max / 2);
    }

    function _payoutChain(address user) internal view returns (address[] memory) {
        return referralGraph.getPayoutChain(user, testGroup, 10);
    }

    function _chainHash(address[] memory chain) internal pure returns (bytes32) {
        return keccak256(abi.encode(chain));
    }

    function _rewardHash(IRewardDistributor.ChainRewardData memory reward) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                block.chainid,
                address(config),
                reward.user,
                reward.totalAmount,
                reward.rewardToken,
                reward.groupId,
                reward.eventId,
                reward.chainHash
            )
        );
    }

    function _buildReward(address user, uint256 totalAmount, bytes32 eventId)
        internal
        view
        returns (IRewardDistributor.ChainRewardData memory)
    {
        address[] memory chain = _payoutChain(user);
        return IRewardDistributor.ChainRewardData({
            user: user,
            totalAmount: totalAmount,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: eventId,
            chainHash: _chainHash(chain)
        });
    }

    function _signReward(IRewardDistributor.ChainRewardData memory reward, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 rewardHash = _rewardHash(reward);
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function testInitialSetup() public view {
        assertTrue(config.isAuthorizedOracle(oracleSigner, testGroup));
        assertEq(address(config.getReferralGraph()), address(referralGraph));
    }

    function testConstructorEmitsOracleAuthorized() public {
        MockReferralGraph graph = new MockReferralGraph();
        address newOracle = address(0xBEEF);
        bytes32 groupId = keccak256("emit-group");

        vm.expectEmit(true, true, false, true);
        emit IRewardDistributor.OracleAuthorized(groupId, newOracle);

        vm.prank(owner);
        new RewardDistributor(owner, address(graph), newOracle, groupId);
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
        uint256 totalReward = 10000 ether;
        bytes32 eventId = keccak256("test-event");

        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        IRewardDistributor.ChainRewardData memory reward = _buildReward(user3, totalReward, eventId);
        bytes32 rewardHash = _rewardHash(reward);
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        uint256 user1BalanceBefore = platformToken.balanceOf(user1);
        uint256 user2BalanceBefore = platformToken.balanceOf(user2);
        uint256 user3BalanceBefore = platformToken.balanceOf(user3);

        vm.prank(user1);
        config.distributeChainRewards(reward, signature);

        assertEq(platformToken.balanceOf(user3) - user3BalanceBefore, 5102040816326530612246);
        assertEq(platformToken.balanceOf(user2) - user2BalanceBefore, 3061224489795918367346);
        assertEq(platformToken.balanceOf(user1) - user1BalanceBefore, 1836734693877551020408);
        assertTrue(config.isRewardDistributed(rewardHash));
    }

    function testSkiplistedMidChainCompressesLevels() public {
        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        referralGraph.setSkiplisted(user2, testGroup, true);

        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(user3, 10000 ether, keccak256("skip-mid"));
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        uint256 user1Before = platformToken.balanceOf(user1);
        uint256 user2Before = platformToken.balanceOf(user2);
        uint256 user3Before = platformToken.balanceOf(user3);

        config.distributeChainRewards(reward, signature);

        // chain is [user3, user1] — 2 recipients, 62.5% / 37.5%
        assertEq(platformToken.balanceOf(user3) - user3Before, 6250 ether);
        assertEq(platformToken.balanceOf(user1) - user1Before, 3750 ether);
        assertEq(platformToken.balanceOf(user2) - user2Before, 0);
    }

    function testSkiplistedSeedContinuesToAncestors() public {
        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        referralGraph.setSkiplisted(user3, testGroup, true);

        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(user3, 10000 ether, keccak256("skip-seed"));
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        uint256 user1Before = platformToken.balanceOf(user1);
        uint256 user2Before = platformToken.balanceOf(user2);
        uint256 user3Before = platformToken.balanceOf(user3);

        config.distributeChainRewards(reward, signature);

        // chain is [user2, user1]
        assertEq(platformToken.balanceOf(user3) - user3Before, 0);
        assertEq(platformToken.balanceOf(user2) - user2Before, 6250 ether);
        assertEq(platformToken.balanceOf(user1) - user1Before, 3750 ether);
    }

    function testCannotDistributeWithChainMismatch() public {
        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        IRewardDistributor.ChainRewardData memory reward = _buildReward(user3, 1000 ether, keccak256("mismatch"));
        reward.chainHash = keccak256("wrong");
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        vm.expectRevert(IRewardDistributor.ChainMismatch.selector);
        config.distributeChainRewards(reward, signature);
    }

    function testCannotDistributeInvalidRewardUser() public {
        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: address(0),
            totalAmount: 1000 ether,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: keccak256("zero-user"),
            chainHash: bytes32(0)
        });
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        vm.expectRevert(IRewardDistributor.InvalidRewardUser.selector);
        config.distributeChainRewards(reward, signature);
    }

    function testCannotDistributeReferralRootUser() public {
        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: root,
            totalAmount: 1000 ether,
            rewardToken: address(platformToken),
            groupId: testGroup,
            eventId: keccak256("root-user"),
            chainHash: bytes32(0)
        });
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        vm.expectRevert(IRewardDistributor.InvalidRewardUser.selector);
        config.distributeChainRewards(reward, signature);
    }

    function testCannotDistributeCodelessToken() public {
        address eoaToken = address(0xDEAD);
        referralGraph.setReferrer(user1, root);

        address[] memory chain = _payoutChain(user1);
        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user1,
            totalAmount: 1000 ether,
            rewardToken: eoaToken,
            groupId: testGroup,
            eventId: keccak256("no-code"),
            chainHash: _chainHash(chain)
        });
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        vm.expectRevert(IRewardDistributor.InvalidRewardToken.selector);
        config.distributeChainRewards(reward, signature);
    }

    function testBlockedRecipientBecomesClaimable() public {
        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        platformToken.setBlocked(user2, true);

        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(user3, 10000 ether, keccak256("blocked"));
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        uint256 user1Before = platformToken.balanceOf(user1);
        uint256 user3Before = platformToken.balanceOf(user3);

        config.distributeChainRewards(reward, signature);

        assertGt(platformToken.balanceOf(user3) - user3Before, 0);
        assertGt(platformToken.balanceOf(user1) - user1Before, 0);
        assertEq(platformToken.balanceOf(user2), 0);
        assertEq(config.claimable(user2, address(platformToken)), 3061224489795918367346);

        platformToken.setBlocked(user2, false);
        config.claimFor(user2, address(platformToken));
        assertEq(platformToken.balanceOf(user2), 3061224489795918367346);
        assertEq(config.claimable(user2, address(platformToken)), 0);
    }

    function testRescueTokensRespectsClaimable() public {
        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);
        platformToken.setBlocked(user2, true);

        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(user3, 10000 ether, keccak256("rescue"));
        bytes memory signature = _signReward(reward, oraclePrivateKey);
        config.distributeChainRewards(reward, signature);

        uint256 claimableAmount = config.claimable(user2, address(platformToken));
        uint256 balance = platformToken.balanceOf(address(config));
        uint256 available = balance - claimableAmount;

        vm.prank(owner);
        config.rescueTokens(address(platformToken), owner, available);
        assertEq(platformToken.balanceOf(owner), available);

        vm.prank(owner);
        vm.expectRevert(IRewardDistributor.InvalidParameters.selector);
        config.rescueTokens(address(platformToken), owner, 1);
    }

    function testCannotDistributeWithInvalidSignature() public {
        referralGraph.setReferrer(user1, root);
        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(user3, 10000 ether, keccak256("test-event"));

        bytes memory invalidSignature = _signReward(reward, 0x9999);

        vm.expectRevert(IRewardDistributor.InvalidOracleSignature.selector);
        config.distributeChainRewards(reward, invalidSignature);
    }

    function testCannotDistributeZeroAmount() public {
        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(user3, 0, keccak256("test-event"));

        bytes memory signature = _signReward(reward, oraclePrivateKey);

        vm.expectRevert(IRewardDistributor.ZeroRewardAmount.selector);
        config.distributeChainRewards(reward, signature);
    }

    function testOnlyOwnerCanConfigure() public {
        vm.prank(user1);
        vm.expectRevert();
        config.authorizeOracle(address(8), testGroup);
    }

    function testCannotDistributeInUnauthorizedGroup() public {
        bytes32 otherGroup = keccak256("other-group");

        address[] memory chain = referralGraph.getPayoutChain(user3, otherGroup, 10);
        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user3,
            totalAmount: 1000 ether,
            rewardToken: address(platformToken),
            groupId: otherGroup,
            eventId: keccak256("test-event"),
            chainHash: _chainHash(chain)
        });

        bytes memory signature = _signReward(reward, oraclePrivateKey);

        vm.expectRevert(IRewardDistributor.InvalidOracleSignature.selector);
        config.distributeChainRewards(reward, signature);
    }

    function testRewardDistributionStopsAtMinReward() public {
        referralGraph.setReferrer(user4, user3);
        referralGraph.setReferrer(user3, user2);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user1, root);

        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(user4, 10000 ether, keccak256("test-event-depth"));

        bytes32 rewardHash = _rewardHash(reward);
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        uint256 user2BalanceBefore = platformToken.balanceOf(user2);
        uint256 user3BalanceBefore = platformToken.balanceOf(user3);
        uint256 user4BalanceBefore = platformToken.balanceOf(user4);

        config.distributeChainRewards(reward, signature);

        assertGt(platformToken.balanceOf(user4) - user4BalanceBefore, 0);
        assertGt(platformToken.balanceOf(user3) - user3BalanceBefore, 0);
        assertGt(platformToken.balanceOf(user2) - user2BalanceBefore, 0);
        assertTrue(config.isRewardDistributed(rewardHash));
    }

    function testFuzz_RewardAmountsNeverExceedTotal(uint256 totalAmount, uint8 chainDepth) public {
        vm.assume(totalAmount > 0 && totalAmount < 1e30);
        vm.assume(chainDepth > 0 && chainDepth < 30);

        address[] memory chain = new address[](chainDepth + 1);
        chain[0] = user1;
        referralGraph.setReferrer(user1, root);

        for (uint256 i = 1; i <= chainDepth; i++) {
            chain[i] = address(uint160(uint256(keccak256(abi.encodePacked(testGroup, i)))));
            vm.assume(chain[i] != address(0) && chain[i] != root);
            referralGraph.setReferrer(chain[i], chain[i - 1]);
        }

        IRewardDistributor.ChainRewardData memory reward =
            _buildReward(chain[chainDepth], totalAmount, keccak256(abi.encodePacked("fuzz-event", totalAmount, chainDepth)));

        bytes32 rewardHash = _rewardHash(reward);
        bytes memory signature = _signReward(reward, oraclePrivateKey);
        uint256 contractBalanceBefore = platformToken.balanceOf(address(config));

        config.distributeChainRewards(reward, signature);

        uint256 totalDistributed = contractBalanceBefore - platformToken.balanceOf(address(config));
        assertLe(totalDistributed, totalAmount, "Total distributed exceeds input amount");
        assertTrue(config.isRewardDistributed(rewardHash));
    }

    function testFuzz_CannotDistributeSameRewardTwice(uint256 totalAmount, bytes32 eventId) public {
        vm.assume(totalAmount > 0 && totalAmount < 1e30);

        referralGraph.setReferrer(user1, root);

        IRewardDistributor.ChainRewardData memory reward = _buildReward(user1, totalAmount, eventId);

        bytes32 rewardHash = _rewardHash(reward);
        bytes memory signature = _signReward(reward, oraclePrivateKey);

        config.distributeChainRewards(reward, signature);
        assertTrue(config.isRewardDistributed(rewardHash));

        vm.expectRevert(IRewardDistributor.RewardAlreadyDistributed.selector);
        config.distributeChainRewards(reward, signature);
    }
}
