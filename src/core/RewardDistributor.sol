// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReferralGraph} from "../interfaces/IReferralGraph.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {RewardCalculator} from "./RewardCalculator.sol";
import {SignatureLib} from "../utils/SignatureLib.sol";

/**
 * @title RewardDistributor
 * @notice Core reward distribution contract with oracle-based chain rewards
 * @dev Manages oracle integration and reward distribution across referral chains
 */
contract RewardDistributor is IRewardDistributor, Owned, ReentrancyGuard {
    using SafeTransferLib for address;

    /// @notice Special address representing the root of all referral trees
    address public constant REFERRAL_ROOT = address(0x0000000000000000000000000000000000000001);

    /// @notice Referral graph contract
    IReferralGraph public immutable referralGraph;

    /// @notice Reward calculator contract
    RewardCalculator public immutable rewardCalculator;

    /// @notice Authorized oracle addresses per group that can distribute rewards
    mapping(bytes32 => mapping(address => bool)) private _authorizedOracles;

    /// @notice List of authorized oracles per group for enumeration
    mapping(bytes32 => address[]) private _authorizedOraclesList;

    /// @notice Tracks distributed rewards to prevent double distribution
    mapping(bytes32 => bool) private _distributedRewards;

     /**
      * @notice Constructor
      * @param initialOwner The initial owner of the contract
      * @param _referralGraph Address of the referral graph contract
      * @param initialOracle Initial oracle address to authorize
      * @param initialGroupId Group to authorize the initial oracle for
      */
    constructor(
        address initialOwner,
        address _referralGraph,
        address initialOracle,
        bytes32 initialGroupId
    ) Owned(initialOwner) {
        referralGraph = IReferralGraph(_referralGraph);
        rewardCalculator = new RewardCalculator();
        if (initialOracle != address(0)) {
            _authorizedOracles[initialGroupId][initialOracle] = true;
            _authorizedOraclesList[initialGroupId].push(initialOracle);
        }
    }

    /// @inheritdoc IRewardDistributor
    function getReferralGraph() external view returns (IReferralGraph) {
        return referralGraph;
    }

    /// @inheritdoc IRewardDistributor
    function isRewardDistributed(bytes32 rewardHash) external view returns (bool) {
        return _distributedRewards[rewardHash];
    }

    /// @inheritdoc IRewardDistributor
    function authorizeOracle(address oracle, bytes32 groupId) external onlyOwner {
        if (oracle == address(0)) revert InvalidOracleAddress();
        if (!_authorizedOracles[groupId][oracle]) {
            _authorizedOracles[groupId][oracle] = true;
            _authorizedOraclesList[groupId].push(oracle);
            emit OracleAuthorized(groupId, oracle);
        }
    }

    /// @inheritdoc IRewardDistributor
    function unauthorizeOracle(address oracle, bytes32 groupId) external onlyOwner {
        if (_authorizedOracles[groupId][oracle]) {
            _authorizedOracles[groupId][oracle] = false;

            address[] storage oracles = _authorizedOraclesList[groupId];
            for (uint256 i = 0; i < oracles.length; i++) {
                if (oracles[i] == oracle) {
                    oracles[i] = oracles[oracles.length - 1];
                    oracles.pop();
                    break;
                }
            }

            emit OracleUnauthorized(groupId, oracle);
        }
    }

    /// @inheritdoc IRewardDistributor
    function isAuthorizedOracle(address oracle, bytes32 groupId) external view returns (bool) {
        return _authorizedOracles[groupId][oracle];
    }

    /// @inheritdoc IRewardDistributor
    function getAuthorizedOracles(bytes32 groupId) external view returns (address[] memory) {
        return _authorizedOraclesList[groupId];
    }

    /// @inheritdoc IRewardDistributor
    function distributeChainRewards(ChainRewardData calldata reward, bytes calldata signature) external nonReentrant {
        if (reward.totalAmount == 0) revert ZeroRewardAmount();

        bytes32 rewardHash = keccak256(
            abi.encodePacked(
                reward.user,
                reward.totalAmount,
                reward.rewardToken,
                reward.groupId,
                reward.eventId
            )
        );

        if (_distributedRewards[rewardHash]) revert RewardAlreadyDistributed();

        bytes32 messageHash = SignatureLib.toEthSignedMessageHash(rewardHash);
        address signer = SignatureLib.recover(messageHash, signature);
        if (!_authorizedOracles[reward.groupId][signer]) revert InvalidOracleSignature();

        // Mark as distributed
        _distributedRewards[rewardHash] = true;

        // Build payout chain upward from the first referrer
        address[] memory chain = _getReferralChain(reward.user, reward.groupId);

        // Calculate rewards across the chain
        (address[] memory recipients, uint256[] memory amounts) = _calculateChainRewards(reward.totalAmount, chain);

        // Transfer tokens to all recipients
        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0) {
                SafeTransferLib.safeTransfer(ERC20(reward.rewardToken), recipients[i], amounts[i]);
            }
        }

        emit ChainRewardsDistributed(reward.user, reward.totalAmount, reward.eventId, recipients, amounts);
    }

    /**
     * @notice Get the payout chain starting from the first referrer
     * @param user First referrer in the payout chain
     * @param groupId The group ID for the referral chain
     * @return Array of addresses to pay, starting with `user` and continuing up through referrers
     * @dev Up to 11 addresses: first referrer plus 10 upstream referrers
     */
    function _getReferralChain(address user, bytes32 groupId) internal view returns (address[] memory) {
        address[] memory chain = new address[](11);
        uint256 length = 0;

        address current = user;
        chain[length++] = current;

        // Add up to 10 ancestors, stopping at REFERRAL_ROOT or end of chain
        while (length < 11) {
            current = referralGraph.getReferrer(current, groupId);
            if (current == address(0) || current == REFERRAL_ROOT) {
                break; // Stop at end or root
            }
            chain[length++] = current;
        }

        // Resize to actual length (will be 1-11)
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = chain[i];
        }

        return result;
    }

    /**
     * @notice Calculate reward distribution across a referral chain
     * @param totalAmount Total amount to distribute
     * @param chain Payout chain starting with the first referrer
     * @return recipients Array of addresses to receive rewards
     * @return amounts Array of reward amounts corresponding to recipients
     * @dev Distributes full `totalAmount` across the chain using geometric decay
     */
    function _calculateChainRewards(uint256 totalAmount, address[] memory chain)
        internal
        view
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        // RewardCalculator supports up to 10 recipients
        uint256 numRecipients = chain.length;
        if (numRecipients > 10) {
            numRecipients = 10;
        }

        // Calculate chain rewards using geometric decay over full totalAmount
        uint256[] memory chainAmounts = rewardCalculator.calculateRewards(totalAmount, numRecipients);

        // Build final arrays with all chain recipients
        recipients = new address[](numRecipients);
        amounts = new uint256[](numRecipients);
        for (uint256 i = 0; i < numRecipients; i++) {
            recipients[i] = chain[i];
            amounts[i] = chainAmounts[i];
        }
    }
}
