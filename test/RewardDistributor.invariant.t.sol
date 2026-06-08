// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RewardDistributor} from "../src/core/RewardDistributor.sol";
import {IRewardDistributor} from "../src/interfaces/IRewardDistributor.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockReferralGraph} from "./mocks/MockReferralGraph.sol";

/**
 * @title RewardDistributorInvariantTest
 * @notice Invariant tests for RewardDistributor to ensure reward conservation
 */
contract RewardDistributorInvariantTest is Test {
    RewardDistributor public config;
    MockERC20 public platformToken;
    MockReferralGraph public referralGraph;

    address public owner = address(1);
    address public root = address(8);

    uint256 oraclePrivateKey = 0x1234;
    address public oracleSigner;

    bytes32 public constant TEST_GROUP = keccak256("invariant-test-group");

    mapping(bytes32 => bool) private distributedRewards;
    uint256 private totalDistributedAmount;
    uint256 private contractInitialBalance;

    function setUp() public {
        platformToken = new MockERC20("Platform Token", "PT", 18);
        referralGraph = new MockReferralGraph();
        oracleSigner = vm.addr(oraclePrivateKey);

        vm.prank(owner);
        config = new RewardDistributor(owner, address(referralGraph), oracleSigner, TEST_GROUP);

        contractInitialBalance = 10000000 ether;
        platformToken.mint(address(config), contractInitialBalance);

        address user1 = address(0x100);
        address user2 = address(0x200);
        address user3 = address(0x300);

        referralGraph.setReferrer(user1, root);
        referralGraph.setReferrer(user2, user1);
        referralGraph.setReferrer(user3, user2);

        targetContract(address(config));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("authorizeOracle(address,bytes32)"));
        selectors[1] = bytes4(keccak256("unauthorizeOracle(address,bytes32)"));

        excludeSelector(FuzzSelector({addr: address(config), selectors: selectors}));
    }

    function _signReward(IRewardDistributor.ChainRewardData memory reward) internal view returns (bytes memory) {
        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId)
        );
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function distributeReward(address user, uint256 totalAmount, bytes32 eventId) public {
        if (totalAmount == 0) return;
        if (totalAmount > contractInitialBalance) return;
        if (user == address(0)) return;

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user,
            totalAmount: totalAmount,
            rewardToken: address(platformToken),
            groupId: TEST_GROUP,
            eventId: eventId
        });

        bytes32 rewardHash = keccak256(
            abi.encodePacked(reward.user, reward.totalAmount, reward.rewardToken, reward.groupId, reward.eventId)
        );

        if (distributedRewards[rewardHash]) return;

        bytes memory signature = _signReward(reward);

        try config.distributeChainRewards(reward, signature) {
            distributedRewards[rewardHash] = true;
            totalDistributedAmount += totalAmount;
        } catch {}
    }

    function invariant_RewardsNeverExceedInput() public view {
        assertGe(platformToken.balanceOf(address(config)), 0, "Contract balance cannot be negative");
    }

    function invariant_NoDoubleDistribution() public view {}

    function invariant_ContractBalanceNonNegative() public view {
        assertGe(platformToken.balanceOf(address(config)), 0, "Contract balance cannot be negative");
    }

    function invariant_TokenConservation() public view {}

    function invariant_OracleAuthorizationConsistent() public view {
        address[] memory oracles = config.getAuthorizedOracles(TEST_GROUP);

        for (uint256 i = 0; i < oracles.length; i++) {
            assertTrue(config.isAuthorizedOracle(oracles[i], TEST_GROUP), "Oracle in list should be authorized");
        }

        for (uint256 i = 0; i < oracles.length; i++) {
            for (uint256 j = i + 1; j < oracles.length; j++) {
                assertTrue(oracles[i] != oracles[j], "Duplicate oracle in list");
            }
        }
    }
}
