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

    /// @notice Maximum number of recipients paid per distribution
    uint256 public constant MAX_PAYOUT_LEVELS = 10;

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

    /// @notice Claimable balances for recipients whose transfers failed
    mapping(address => mapping(address => uint256)) private _claimable;

    /// @notice Total claimable amount reserved per token (rescue cannot drain below this)
    mapping(address => uint256) private _totalClaimable;

    /**
     * @notice Constructor
     * @param initialOwner The initial owner of the contract
     * @param _referralGraph Address of the referral graph contract
     * @param initialOracle Initial oracle address to authorize
     * @param initialGroupId Group to authorize the initial oracle for
     */
    constructor(address initialOwner, address _referralGraph, address initialOracle, bytes32 initialGroupId)
        Owned(initialOwner)
    {
        if (_referralGraph == address(0)) revert InvalidParameters();
        referralGraph = IReferralGraph(_referralGraph);
        rewardCalculator = new RewardCalculator();
        if (initialOracle != address(0)) {
            _authorizedOracles[initialGroupId][initialOracle] = true;
            _authorizedOraclesList[initialGroupId].push(initialOracle);
            emit OracleAuthorized(initialGroupId, initialOracle);
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
    function claimable(address recipient, address token) external view returns (uint256) {
        return _claimable[recipient][token];
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
        if (reward.user == address(0) || reward.user == REFERRAL_ROOT) revert InvalidRewardUser();
        if (reward.rewardToken.code.length == 0) revert InvalidRewardToken();

        bytes32 rewardHash = keccak256(
            abi.encodePacked(
                block.chainid,
                address(this),
                reward.user,
                reward.totalAmount,
                reward.rewardToken,
                reward.groupId,
                reward.eventId,
                reward.chainHash
            )
        );

        if (_distributedRewards[rewardHash]) revert RewardAlreadyDistributed();

        bytes32 messageHash = SignatureLib.toEthSignedMessageHash(rewardHash);
        address signer = SignatureLib.recover(messageHash, signature);
        if (!_authorizedOracles[reward.groupId][signer]) revert InvalidOracleSignature();

        address[] memory chain = referralGraph.getPayoutChain(reward.user, reward.groupId, MAX_PAYOUT_LEVELS);
        if (chain.length == 0) revert EmptyPayoutChain();
        if (keccak256(abi.encode(chain)) != reward.chainHash) revert ChainMismatch();

        // Mark as distributed after successful chain verification
        _distributedRewards[rewardHash] = true;

        (address[] memory recipients, uint256[] memory amounts) = _calculateChainRewards(reward.totalAmount, chain);

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] == 0) continue;
            if (!_tryTransfer(reward.rewardToken, recipients[i], amounts[i])) {
                _claimable[recipients[i]][reward.rewardToken] += amounts[i];
                _totalClaimable[reward.rewardToken] += amounts[i];
                emit RewardClaimable(recipients[i], reward.rewardToken, amounts[i]);
            }
        }

        emit ChainRewardsDistributed(reward.user, reward.totalAmount, reward.eventId, recipients, amounts);
    }

    /// @inheritdoc IRewardDistributor
    function claim(address token) external nonReentrant {
        _claim(msg.sender, token);
    }

    /// @inheritdoc IRewardDistributor
    function claimFor(address recipient, address token) external nonReentrant {
        if (recipient == address(0)) revert InvalidParameters();
        _claim(recipient, token);
    }

    /// @inheritdoc IRewardDistributor
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidRescueAddress();
        if (token == address(0) || amount == 0) revert InvalidParameters();

        uint256 balance = ERC20(token).balanceOf(address(this));
        uint256 reserved = _totalClaimable[token];
        if (amount > balance - reserved) revert InvalidParameters();

        SafeTransferLib.safeTransfer(ERC20(token), to, amount);
        emit TokensRescued(token, to, amount);
    }

    /**
     * @notice Attempt an ERC20 transfer; returns false on failure instead of reverting the batch
     */
    function _tryTransfer(address token, address to, uint256 amount) internal returns (bool success) {
        try this.safeTransferExternal(token, to, amount) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice External transfer helper for try/catch isolation
     * @dev Must be called via `this.` so failures do not bubble out of distributeChainRewards
     */
    function safeTransferExternal(address token, address to, uint256 amount) external {
        if (msg.sender != address(this)) revert UnauthorizedApp();
        SafeTransferLib.safeTransfer(ERC20(token), to, amount);
    }

    function _claim(address recipient, address token) internal {
        uint256 amount = _claimable[recipient][token];
        if (amount == 0) revert NothingToClaim();

        _claimable[recipient][token] = 0;
        _totalClaimable[token] -= amount;

        SafeTransferLib.safeTransfer(ERC20(token), recipient, amount);
        emit RewardClaimed(recipient, token, amount);
    }

    /**
     * @notice Calculate reward distribution across a referral chain
     * @param totalAmount Total amount to distribute
     * @param chain Payout chain starting with the first referrer
     * @return recipients Array of addresses to receive rewards
     * @return amounts Array of reward amounts corresponding to recipients
     */
    function _calculateChainRewards(uint256 totalAmount, address[] memory chain)
        internal
        view
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        uint256 numRecipients = chain.length;
        if (numRecipients > MAX_PAYOUT_LEVELS) {
            numRecipients = MAX_PAYOUT_LEVELS;
        }

        uint256[] memory chainAmounts = rewardCalculator.calculateRewards(totalAmount, numRecipients);

        recipients = new address[](numRecipients);
        amounts = new uint256[](numRecipients);
        for (uint256 i = 0; i < numRecipients; i++) {
            recipients[i] = chain[i];
            amounts[i] = chainAmounts[i];
        }
    }
}
