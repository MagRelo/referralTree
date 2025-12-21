// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {IReferralGraph} from "../interfaces/IReferralGraph.sol";

/**
 * @title RewardDistributor
 * @notice Core reward distribution contract with oracle-based chain rewards
 * @dev Manages oracle integration and reward distribution across referral chains
 */
contract RewardDistributor is IRewardDistributor, Ownable {
    using ECDSA for bytes32;

    /// @notice Referral graph contract
    IReferralGraph public immutable referralGraph;

    /// @notice Authorized oracle addresses that can sign rewards
    mapping(address => bool) private _authorizedOracles;

    /// @notice List of authorized oracles for enumeration
    address[] private _authorizedOraclesList;

    /// @notice Type of decay function for referral rewards
    IRewardDistributor.DecayType private _decayType;

    /// @notice Decay factor/rate (basis points, e.g., 500 = 5% for linear, 9500 = 95% for exponential)
    uint256 private _decayFactor;

    /// @notice Minimum reward per level (wei)
    uint256 private _minReward;

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
        if (initialOracle != address(0)) {
            _authorizedOracles[initialOracle] = true;
            _authorizedOraclesList.push(initialOracle);
        }

        // Default decay: Exponential decay with 70% retention per level (sequential distribution), min 0.01 ether
        _decayType = IRewardDistributor.DecayType.EXPONENTIAL;
        _decayFactor = 7000; // 70% retention per level (30% decay)
        _minReward = 0.01 ether;
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
    function getDecayConfig() external view returns (IRewardDistributor.DecayType decayType, uint256 decayFactor, uint256 minReward) {
        return (_decayType, _decayFactor, _minReward);
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
    function setDecayConfig(IRewardDistributor.DecayType decayType, uint256 decayFactor, uint256 minReward) external onlyOwner {
        if (decayFactor > 10000) revert InvalidParameters(); // Max 100%
        if (minReward > 100 ether) revert InvalidParameters(); // Reasonable upper bound

        _decayType = decayType;
        _decayFactor = decayFactor;
        _minReward = minReward;
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
     * @dev Retrieves the referral chain up to a reasonable limit. Distribution stops naturally when rewards decay below _minReward.
     */
    function _getReferralChain(address user, bytes32 groupId) internal view returns (address[] memory) {
        // Use a reasonable fixed size - most chains will be much shorter
        // Distribution will stop naturally when rewards decay below _minReward
        address[] memory chain = new address[](200);
        uint256 chainLength = 0;
        address root = referralGraph.getRoot();

        address current = user;
        while (current != address(0) && current != root && chainLength < chain.length) {
            chain[chainLength] = current;
            chainLength++;
            current = referralGraph.getReferrer(current, groupId);
        }

        // Resize array to actual length
        address[] memory result = new address[](chainLength);
        for (uint256 i = 0; i < chainLength; i++) {
            result[i] = chain[i];
        }

        return result;
    }

    /**
     * @notice Calculate reward for a specific level using the configured decay function
     * @param baseAmount The base amount to apply decay to
     * @param level The referral level (0 = first referrer, 1 = second referrer, etc.)
     * @return The reward amount for this level
     */
    function _calculateLevelReward(uint256 baseAmount, uint256 level) internal view returns (uint256) {
        if (_decayType == IRewardDistributor.DecayType.LINEAR) {
            // Linear decay: reward = max(minReward, baseAmount * (1 - decayRate * level))
            // decayFactor is in basis points (e.g., 2000 = 20%)
            uint256 decayAmount = (baseAmount * _decayFactor * level) / 10000;
            if (decayAmount >= baseAmount) {
                return _minReward;
            }
            uint256 reward = baseAmount - decayAmount;
            return reward > _minReward ? reward : _minReward;

        } else if (_decayType == IRewardDistributor.DecayType.EXPONENTIAL) {
            // Exponential decay: each level gets decayFactor% of the previous level's reward
            // This creates a geometric series that naturally decays
            // decayFactor is in basis points (e.g., 8500 = 85%)
            uint256 reward = baseAmount;
            for (uint256 i = 0; i < level; i++) {
                reward = (reward * _decayFactor) / 10000;
                if (reward < _minReward) {
                    return _minReward;
                }
            }
            return reward;

        } else if (_decayType == IRewardDistributor.DecayType.FIXED) {
            // Fixed amount per level (until minReward reached)
            // decayFactor here represents the fixed amount
            return _decayFactor > _minReward ? _decayFactor : _minReward;
        }

        return _minReward; // Fallback
    }

    /**
     * @notice Calculate reward distribution across the referral chain using mathematical decay
     * @param totalAmount Base amount from which referral rewards are calculated
     * @param chain Array of addresses in the referral chain (user at index 0)
     * @return recipients Array of addresses to receive rewards
     * @return amounts Array of amounts each recipient gets
     * @dev Original user gets originalUserPercentage, referrers get decayed amounts
     */
    function _calculateChainRewards(uint256 totalAmount, address[] memory chain, address dustRecipient)
        internal
        view
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        // Original user gets their percentage
        uint256 originalUserReward = (totalAmount * _originalUserPercentage) / 10000;
        uint256 remainingForChain = totalAmount - originalUserReward;

        // Calculate rewards for referral chain (excluding original user)
        uint256 numReferrers = chain.length - 1; // chain[0] is original user
        recipients = new address[](numReferrers + 2); // +1 for original user, +1 for potential oracle
        amounts = new uint256[](numReferrers + 2);

        // Original user reward
        recipients[0] = chain[0];
        amounts[0] = originalUserReward;

        // Referral chain rewards with sequential decay distribution
        uint256 remainingToDistribute = remainingForChain;
        uint256 totalDistributed = originalUserReward;
        uint256 recipientCount = 1; // Start with 1 (original user)

        for (uint256 i = 0; i < numReferrers; i++) {
            if (remainingToDistribute < _minReward) {
                break; // Not enough left to distribute
            }

            uint256 levelReward;
            if (_decayType == IRewardDistributor.DecayType.LINEAR) {
                // Linear: take decayFactor% of remaining
                levelReward = (remainingToDistribute * _decayFactor) / 10000;
            } else if (_decayType == IRewardDistributor.DecayType.EXPONENTIAL) {
                // Exponential: take decayFactor% of remaining, then reduce remaining
                levelReward = (remainingToDistribute * _decayFactor) / 10000;
            } else if (_decayType == IRewardDistributor.DecayType.FIXED) {
                // Fixed: take min of fixed amount or remaining
                levelReward = _decayFactor < remainingToDistribute ? _decayFactor : remainingToDistribute;
            }

            // Ensure minimum reward and don't exceed remaining
            if (levelReward < _minReward) {
                levelReward = remainingToDistribute >= _minReward ? _minReward : 0;
            }

            if (levelReward > 0 && levelReward <= remainingToDistribute) {
                recipients[recipientCount] = chain[i + 1];
                amounts[recipientCount] = levelReward;
                remainingToDistribute -= levelReward;
                totalDistributed += levelReward;
                recipientCount++;
            } else {
                break;
            }
        }

        // Send any remaining dust to the signing oracle
        if (remainingToDistribute > 0) {
            recipients[recipientCount] = dustRecipient;
            amounts[recipientCount] = remainingToDistribute;
            totalDistributed += remainingToDistribute;
            recipientCount++;
        }

        // Resize arrays to actual length
        address[] memory finalRecipients = new address[](recipientCount);
        uint256[] memory finalAmounts = new uint256[](recipientCount);

        for (uint256 i = 0; i < recipientCount; i++) {
            finalRecipients[i] = recipients[i];
            finalAmounts[i] = amounts[i];
        }

        return (finalRecipients, finalAmounts);
    }
}

