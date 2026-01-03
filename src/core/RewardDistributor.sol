// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {IReferralGraph} from "../interfaces/IReferralGraph.sol";
import {RewardCalculator} from "./RewardCalculator.sol";

/**
 * @title RewardDistributor
 * @notice Core reward distribution contract with oracle-based chain rewards
 * @dev Manages oracle integration and reward distribution across referral chains
 */
contract RewardDistributor is IRewardDistributor, Ownable {
    using ECDSA for bytes32;

    /// @notice Special address representing the root of all referral trees
    address public constant REFERRAL_ROOT = address(0x0000000000000000000000000000000000000001);

    /// @notice Referral graph contract
    IReferralGraph public immutable referralGraph;

    /// @notice Reward calculator contract
    RewardCalculator public immutable rewardCalculator;

    /// @notice Authorized oracle addresses that can sign rewards
    mapping(address => bool) private _authorizedOracles;

    /// @notice List of authorized oracles for enumeration
    address[] private _authorizedOraclesList;

    /// @notice Percentage for original user (basis points, default 80%)
    uint256 private _originalUserPercentage;

    /// @notice Tracks distributed rewards to prevent double distribution
    mapping(bytes32 => bool) private _distributedRewards;

    /**
     * @notice Constructor
     * @param initialOwner The initial owner of the contract
     * @param _referralGraph Address of the referral graph contract
     * @param initialOracle Initial oracle address to authorize
     */
    constructor(
        address initialOwner,
        address _referralGraph,
        address initialOracle
    ) Ownable(initialOwner) {
        referralGraph = IReferralGraph(_referralGraph);
        rewardCalculator = new RewardCalculator();
        if (initialOracle != address(0)) {
            _authorizedOracles[initialOracle] = true;
            _authorizedOraclesList.push(initialOracle);
        }

        _originalUserPercentage = 8000; // 80%
    }

    /// @inheritdoc IRewardDistributor
    function getReferralGraph() external view returns (IReferralGraph) {
        return referralGraph;
    }

    /// @inheritdoc IRewardDistributor
    function getOriginalUserPercentage() external view returns (uint256) {
        return _originalUserPercentage;
    }

    /// @inheritdoc IRewardDistributor
    function isRewardDistributed(bytes32 rewardHash) external view returns (bool) {
        return _distributedRewards[rewardHash];
    }

    /// @inheritdoc IRewardDistributor
    function authorizeOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert InvalidParameters();
        if (!_authorizedOracles[oracle]) {
            _authorizedOracles[oracle] = true;
            _authorizedOraclesList.push(oracle);
            emit OracleAuthorized(oracle);
        }
    }

    /// @inheritdoc IRewardDistributor
    function unauthorizeOracle(address oracle) external onlyOwner {
        if (_authorizedOracles[oracle]) {
            _authorizedOracles[oracle] = false;

            // Remove from list
            for (uint256 i = 0; i < _authorizedOraclesList.length; i++) {
                if (_authorizedOraclesList[i] == oracle) {
                    _authorizedOraclesList[i] = _authorizedOraclesList[_authorizedOraclesList.length - 1];
                    _authorizedOraclesList.pop();
                    break;
                }
            }

            emit OracleUnauthorized(oracle);
        }
    }

    /// @inheritdoc IRewardDistributor
    function isAuthorizedOracle(address oracle) external view returns (bool) {
        return _authorizedOracles[oracle];
    }

    /// @inheritdoc IRewardDistributor
    function getAuthorizedOracles() external view returns (address[] memory) {
        return _authorizedOraclesList;
    }

    /// @inheritdoc IRewardDistributor
    function setOriginalUserPercentage(uint256 percentage) external onlyOwner {
        if (percentage > 10000) revert InvalidParameters(); // Max 100%
        _originalUserPercentage = percentage;
    }

    /// @inheritdoc IRewardDistributor
    function distributeChainRewards(ChainRewardData calldata reward, bytes calldata signature) external {
        // Validate reward data
        if (reward.totalAmount == 0) revert ZeroRewardAmount();

        // Create reward hash for uniqueness check
        bytes32 rewardHash = keccak256(
            abi.encodePacked(
                reward.user,
                reward.totalAmount,
                reward.rewardToken,
                reward.groupId,
                reward.eventId,
                reward.timestamp,
                reward.nonce
            )
        );

        // Check if already distributed
        if (_distributedRewards[rewardHash]) revert RewardAlreadyDistributed();

        // Verify oracle signature
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(rewardHash);
        address signer = ECDSA.recover(messageHash, signature);
        if (!_authorizedOracles[signer]) revert InvalidOracleSignature();

        // Mark as distributed
        _distributedRewards[rewardHash] = true;

        // Get referral chain for the user in the group
        address[] memory chain = _getReferralChain(reward.user, reward.groupId);

        // Calculate and distribute rewards across the chain
        (address[] memory recipients, uint256[] memory amounts) = _calculateChainRewards(reward.totalAmount, chain, signer);

        // Transfer tokens to all recipients
        IERC20 rewardToken = IERC20(reward.rewardToken);
        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0) {
                rewardToken.transfer(recipients[i], amounts[i]);
            }
        }

        emit ChainRewardsDistributed(reward.user, reward.totalAmount, reward.eventId, recipients, amounts);
    }

    /**
     * @notice Get the referral chain for a user (from user up the chain)
     * @param user The user to get chain for
     * @param groupId The group ID for the referral chain
     * @return Array of addresses in the referral chain (including the user)
     * @dev Only builds the chain needed for reward distribution (max 11 addresses: user + 10 ancestors)
     */
    function _getReferralChain(address user, bytes32 groupId) internal view returns (address[] memory) {
        // We only pay up to 10 ancestors + original user = 11 total
        address[] memory chain = new address[](11);
        uint256 length = 0;

        address current = user;
        // Include the original user
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
     * @param chain Referral chain starting with the user who triggered the reward
     * @return recipients Array of addresses to receive rewards
     * @return amounts Array of reward amounts corresponding to recipients
     * @dev Distributes 80% to original user, remaining to chain using geometric decay
     */
    function _calculateChainRewards(uint256 totalAmount, address[] memory chain, address /*dustRecipient*/)
        internal
        view
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        // Determine numRecipients (exclude original user, cap at 10)
        // Chain already stops at REFERRAL_ROOT, so distribute to all ancestors (up to 10)
        uint256 numRecipients = chain.length > 1 ? chain.length - 1 : 0;
        if (numRecipients > 10) {
            numRecipients = 10;
        }

        // Original user gets 80%
        uint256 originalUserReward = (totalAmount * _originalUserPercentage) / 10000;
        uint256 remainingForChain = totalAmount - originalUserReward;

        // Calculate chain rewards using geometric decay
        uint256[] memory chainAmounts = rewardCalculator.calculateRewards(remainingForChain, numRecipients);

        // Build final arrays: original user + chain recipients
        recipients = new address[](numRecipients + 1);
        amounts = new uint256[](numRecipients + 1);
        recipients[0] = chain[0];
        amounts[0] = originalUserReward;
        for (uint256 i = 0; i < numRecipients; i++) {
            recipients[i + 1] = chain[i + 1];
            amounts[i + 1] = chainAmounts[i];
        }
    }
}
