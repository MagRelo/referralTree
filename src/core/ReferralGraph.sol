// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IReferralGraph} from "../interfaces/IReferralGraph.sol";
import {IRewardCalculator} from "../interfaces/IRewardCalculator.sol";
import {IERC1271} from "../interfaces/IERC1271.sol";

/**
 * @title ReferralGraph
 * @notice Manages referral relationships in a tree structure
 */
contract ReferralGraph is IReferralGraph, Owned, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    /// @notice Maximum paid recipients, matching RewardCalculator
    uint256 public constant MAX_PAYOUT_LEVELS = 10;
    /// @notice Basis-point denominator. 10000 bps = 100%.
    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// @notice Hard cap on the protocol fee. 1000 bps = 10%.
    uint256 public constant MAX_FEE_BPS = 1_000;
    /// @notice Special address representing the root of all referral trees
    address public constant REFERRAL_ROOT = address(0x0000000000000000000000000000000000000001);

    /// @notice Maps group -> user -> referrer
    mapping(bytes32 => mapping(address => address)) private _referrers;

    /// @notice Maps group -> referrer -> children
    mapping(bytes32 => mapping(address => address[])) private _children;

    /// @notice Authorized oracle addresses per group that can register referrals
    mapping(bytes32 => mapping(address => bool)) private _authorizedOracles;

    /// @notice List of authorized oracles per group for enumeration
    mapping(bytes32 => address[]) private _authorizedOraclesList;

    /// @notice Skiplisted addresses per group (omitted from payout chain resolution)
    mapping(bytes32 => mapping(address => bool)) private _skiplisted;

    /// @notice List of skiplisted addresses per group for enumeration
    mapping(bytes32 => address[]) private _skiplistedList;

    /// @notice Successful registrations per group (excludes REFERRAL_ROOT; never decrements)
    mapping(bytes32 => uint256) private _registeredCount;

    /// @notice Geometric split used by settle
    IRewardCalculator public rewardCalculator;

    /// @notice Global protocol fee in basis points. Defaults to 0 (no charge).
    uint16 public feeBps;

    /// @notice Recipient of the protocol fee charged on settle
    address public feeRecipient;

    /// @notice groupId => settlementId => already settled. Doubles as the EIP-712 settle nonce.
    mapping(bytes32 => mapping(bytes32 => bool)) private _settled;

    /*//////////////////////////////////////////////////////////////
                            EIP-712 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 typehash for an oracle-signed settlement
    /// @dev `payer` is the address that submits `settle` and whose tokens are pulled (`msg.sender`).
    bytes32 public constant SETTLE_TYPEHASH = keccak256(
        "Settle(bytes32 groupId,bytes32 settlementId,address user,address token,uint256 totalAmount,address payer,uint256 deadline)"
    );

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /**
     * @notice Constructor
     * @param initialOwner The initial owner of the contract
     * @param initialOracle Initial oracle address to authorize (optional, can be address(0))
     * @param initialGroupId Group to authorize the initial oracle for
     */
    constructor(address initialOwner, address initialOracle, bytes32 initialGroupId) Owned(initialOwner) {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        if (initialOracle != address(0)) {
            _authorizedOracles[initialGroupId][initialOracle] = true;
            _authorizedOraclesList[initialGroupId].push(initialOracle);
            emit OracleAuthorized(initialGroupId, initialOracle);
        }
    }

    /// @notice Check if a user is registered in a group
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if the user has a referrer in the group
    function isRegistered(address user, bytes32 groupId) external view returns (bool) {
        return _referrers[groupId][user] != address(0);
    }

    /// @notice Get the referrer of a user in a group
    /// @param user The user to query
    /// @param groupId The group ID
    /// @return The address of the referrer, or address(0) if not registered
    function getReferrer(address user, bytes32 groupId) external view returns (address) {
        return _referrers[groupId][user];
    }

    /// @notice Get the children of a referrer in a group
    /// @param referrer The referrer to query
    /// @param groupId The group ID
    /// @return Array of addresses that were referred by this referrer
    function getChildren(address referrer, bytes32 groupId) external view returns (address[] memory) {
        return _children[groupId][referrer];
    }

    /// @notice Get the ancestor chain for a user in a group
    /// @param user The user to get ancestors for
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of levels to traverse
    /// @return Array of ancestors, starting with immediate referrer
    function getAncestors(address user, bytes32 groupId, uint256 maxLevels) external view returns (address[] memory) {
        if (user == address(0) || user == REFERRAL_ROOT) {
            return new address[](0);
        }

        address[] memory ancestors = new address[](maxLevels);
        uint256 count = 0;
        address current = _referrers[groupId][user];

        while (current != address(0) && current != REFERRAL_ROOT && count < maxLevels) {
            ancestors[count] = current;
            current = _referrers[groupId][current];
            count++;
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ancestors[i];
        }

        return result;
    }

    /// @inheritdoc IReferralGraph
    function getPayoutAncestors(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory)
    {
        if (user == address(0) || user == REFERRAL_ROOT || maxLevels == 0) {
            return new address[](0);
        }

        address[] memory ancestors = new address[](maxLevels);
        uint256 count = 0;
        address current = _referrers[groupId][user];

        while (current != address(0) && current != REFERRAL_ROOT && count < maxLevels) {
            if (!_skiplisted[groupId][current]) {
                ancestors[count] = current;
                count++;
            }
            current = _referrers[groupId][current];
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ancestors[i];
        }

        return result;
    }

    /// @inheritdoc IReferralGraph
    function getPayoutChain(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory chain)
    {
        if (user == address(0) || user == REFERRAL_ROOT || maxLevels == 0) {
            return new address[](0);
        }

        address[] memory buffer = new address[](maxLevels);
        uint256 length = 0;
        address current = user;

        while (current != address(0) && current != REFERRAL_ROOT && length < maxLevels) {
            if (!_skiplisted[groupId][current]) {
                buffer[length++] = current;
            }
            current = _referrers[groupId][current];
        }

        chain = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            chain[i] = buffer[i];
        }
    }

    /// @inheritdoc IReferralGraph
    function isSkiplisted(address user, bytes32 groupId) external view returns (bool) {
        return _skiplisted[groupId][user];
    }

    /// @inheritdoc IReferralGraph
    function getSkiplisted(bytes32 groupId) external view returns (address[] memory) {
        return _skiplistedList[groupId];
    }

    /// @inheritdoc IReferralGraph
    function registeredCount(bytes32 groupId) external view returns (uint256) {
        return _registeredCount[groupId];
    }

    /// @inheritdoc IReferralGraph
    function skiplistedCount(bytes32 groupId) external view returns (uint256) {
        return _skiplistedList[groupId].length;
    }

    /// @inheritdoc IReferralGraph
    function setSkiplisted(address user, bytes32 groupId, bool skiplisted)
        external
        onlyAuthorizedOracle(groupId)
    {
        if (user == address(0) || user == REFERRAL_ROOT) revert InvalidUserAddress();

        if (skiplisted) {
            if (!_skiplisted[groupId][user]) {
                _skiplisted[groupId][user] = true;
                _skiplistedList[groupId].push(user);
                emit AddressSkiplisted(groupId, user);
            }
        } else if (_skiplisted[groupId][user]) {
            _skiplisted[groupId][user] = false;

            address[] storage list = _skiplistedList[groupId];
            for (uint256 i = 0; i < list.length; i++) {
                if (list[i] == user) {
                    list[i] = list[list.length - 1];
                    list.pop();
                    break;
                }
            }

            emit AddressUnskiplisted(groupId, user);
        }
    }

    /// @notice Check if a user is in a group's referral tree
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if user appears in the referral tree (has been referred or has referred others, or is root)
    function _isInReferralTree(address user, bytes32 groupId) internal view returns (bool) {
        if (user == REFERRAL_ROOT && REFERRAL_ROOT != address(0)) return true;
        return _referrers[groupId][user] != address(0) || _children[groupId][user].length > 0;
    }

    /// @notice Internal function to register a user with a referrer
    /// @param user The user being registered
    /// @param referrer The referrer address
    /// @param groupId The group ID
    function _register(address user, address referrer, bytes32 groupId) internal {
        if (user == address(0) || user == REFERRAL_ROOT) revert InvalidUserAddress();
        if (referrer == address(0)) revert InvalidReferrerAddress();
        if (referrer == user) revert SelfReferralNotAllowed();
        if (_referrers[groupId][user] != address(0)) revert UserAlreadyRegistered();

        if (referrer != REFERRAL_ROOT && !_isInReferralTree(referrer, groupId)) {
            revert ReferrerNotInTree();
        }

        _referrers[groupId][user] = referrer;
        _children[groupId][referrer].push(user);

        unchecked {
            _registeredCount[groupId] += 1;
        }

        emit UserRegistered(groupId, user, referrer);
    }

    /// @notice Modifier to restrict functions to oracles authorized for a group
    modifier onlyAuthorizedOracle(bytes32 groupId) {
        if (!_authorizedOracles[groupId][msg.sender]) {
            revert UnauthorizedOracle();
        }
        _;
    }

    /// @inheritdoc IReferralGraph
    function register(address user, address referrer, bytes32 groupId) external onlyAuthorizedOracle(groupId) {
        _register(user, referrer, groupId);
    }

    /// @notice Batch register multiple users with the same referrer in a group
    /// @param users Array of users to register
    /// @param referrer The referrer for all users
    /// @param groupId The group ID
    function batchRegister(address[] calldata users, address referrer, bytes32 groupId)
        external
        onlyAuthorizedOracle(groupId)
    {
        for (uint256 i = 0; i < users.length; i++) {
            _register(users[i], referrer, groupId);
        }
    }

    /// @inheritdoc IReferralGraph
    function authorizeOracle(address oracle, bytes32 groupId) external onlyOwner {
        if (oracle == address(0)) revert InvalidOracleAddress();
        if (!_authorizedOracles[groupId][oracle]) {
            _authorizedOracles[groupId][oracle] = true;
            _authorizedOraclesList[groupId].push(oracle);
            emit OracleAuthorized(groupId, oracle);
        }
    }

    /// @inheritdoc IReferralGraph
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

    /// @inheritdoc IReferralGraph
    function isAuthorizedOracle(address oracle, bytes32 groupId) external view returns (bool) {
        return _authorizedOracles[groupId][oracle];
    }

    /// @inheritdoc IReferralGraph
    function getAuthorizedOracles(bytes32 groupId) external view returns (address[] memory) {
        return _authorizedOraclesList[groupId];
    }

    /// @inheritdoc IReferralGraph
    function setRewardCalculator(address calculator) external onlyOwner {
        if (calculator == address(0)) revert InvalidRewardCalculator();
        rewardCalculator = IRewardCalculator(calculator);
        emit RewardCalculatorSet(calculator);
    }

    /// @inheritdoc IReferralGraph
    function setProtocolFee(uint16 bps, address recipient) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh();
        if (bps > 0 && recipient == address(0)) revert InvalidFeeRecipient();
        feeBps = bps;
        feeRecipient = recipient;
        emit ProtocolFeeSet(bps, recipient);
    }

    /// @inheritdoc IReferralGraph
    function settle(
        bytes32 groupId,
        bytes32 settlementId,
        address user,
        address token,
        uint256 totalAmount,
        uint256 deadline,
        address oracle,
        bytes calldata signature
    ) external nonReentrant {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (!_authorizedOracles[groupId][oracle]) revert InvalidSigner();

        bytes32 digest = _settleDigest(groupId, settlementId, user, token, totalAmount, deadline);
        if (!_isValidOracleSignature(oracle, digest, signature)) revert InvalidSigner();

        if (address(rewardCalculator) == address(0)) revert RewardCalculatorNotSet();
        if (token == address(0)) revert InvalidToken();
        // Defense in depth: SafeTransferLib (solmate 89365b8) already fails a transfer to a codeless token, but do not
        // rely on the library for this. Rejects undeployed CREATE2 targets / removed code before any state write, so
        // the settlementId stays usable.
        if (token.code.length == 0) revert InvalidToken();
        if (totalAmount == 0) revert InvalidAmount();
        if (user == address(0) || user == REFERRAL_ROOT) revert InvalidUserAddress();
        if (_referrers[groupId][user] == address(0)) revert UserNotRegistered();
        if (_settled[groupId][settlementId]) revert SettlementAlreadyUsed();

        // Deduct protocol fee from the settle total up front. Caller pays `totalAmount` only.
        uint256 protocolFee = _protocolFee(totalAmount);
        uint256 distributable = totalAmount - protocolFee; // emitted as ReferralSettlement.distributedAmount

        address[] memory chain = this.getPayoutChain(user, groupId, MAX_PAYOUT_LEVELS);
        if (chain.length == 0) revert EmptyPayoutChain();

        uint256[] memory amounts = rewardCalculator.calculateRewards(distributable, chain.length);
        if (amounts.length != chain.length) revert InvalidSplit();

        uint256 sum;
        for (uint256 i = 0; i < amounts.length; i++) {
            sum += amounts[i];
        }
        if (sum != distributable) revert InvalidSplit();

        _settled[groupId][settlementId] = true;

        ERC20 payoutToken = ERC20(token);
        if (protocolFee > 0) {
            address recipient = feeRecipient;
            payoutToken.safeTransferFrom(msg.sender, recipient, protocolFee);
            emit ProtocolFeeCharged(groupId, settlementId, token, recipient, protocolFee);
        }
        for (uint256 i = 0; i < chain.length; i++) {
            if (amounts[i] == 0) continue;
            payoutToken.safeTransferFrom(msg.sender, chain[i], amounts[i]);
        }

        emit ReferralSettlement(groupId, settlementId, user, token, distributable, chain, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-712 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 domain separator (name "ReferralGraph", version "1"). Recomputed if the chain id changes (fork).
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ReferralGraph")),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /// @dev EIP-712 digest of a Settle struct with `payer = msg.sender`.
    function _settleDigest(
        bytes32 groupId,
        bytes32 settlementId,
        address user,
        address token,
        uint256 totalAmount,
        uint256 deadline
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(SETTLE_TYPEHASH, groupId, settlementId, user, token, totalAmount, msg.sender, deadline)
                )
            )
        );
    }

    /// @dev Minimal signature check (Solady SignatureCheckerLib used as reference only). Order:
    ///      1. If `signature` is 65 bytes (r, s, v) or 64 bytes (EIP-2098 r, vs): ecrecover(digest). Valid if the
    ///         recovered address == oracle and != address(0), regardless of `oracle`'s code length. This keeps
    ///         EIP-7702-delegated EOAs (code = 0xef0100 || delegate) working with plain ECDSA even when the
    ///         delegate has no isValidSignature. Like solmate permit, high-s signatures are not rejected;
    ///         malleation cannot replay because `settlementId` is consumed.
    ///      2. Otherwise, if `oracle` has code: ERC-1271. Low-level staticcall of isValidSignature(digest, signature);
    ///         valid iff the call succeeds, returns >= 32 bytes, and the first word is exactly 0x1626ba7e.
    ///         Reverts, short/empty or garbage returndata yield false (InvalidSigner), never a bubbled revert.
    ///         Only 32 bytes of returndata are copied. All remaining gas is forwarded (the oracle is owner-authorized).
    ///      3. Otherwise invalid.
    ///      No ERC-6492 (counterfactual wallet) support: a contract oracle must already be deployed.
    function _isValidOracleSignature(address oracle, bytes32 digest, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (signature.length == 65 || signature.length == 64) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            if (signature.length == 65) {
                assembly ("memory-safe") {
                    r := calldataload(signature.offset)
                    s := calldataload(add(signature.offset, 0x20))
                    v := byte(0, calldataload(add(signature.offset, 0x40)))
                }
            } else {
                bytes32 vs;
                assembly ("memory-safe") {
                    r := calldataload(signature.offset)
                    vs := calldataload(add(signature.offset, 0x20))
                }
                s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                v = uint8(uint256(vs >> 255)) + 27;
            }

            address recoveredAddress = ecrecover(digest, v, r, s);
            if (recoveredAddress != address(0) && recoveredAddress == oracle) return true;
        }

        if (oracle.code.length == 0) return false;

        bytes memory data = abi.encodeCall(IERC1271.isValidSignature, (digest, signature));
        bool success;
        bytes32 result;
        assembly ("memory-safe") {
            success := staticcall(gas(), oracle, add(data, 0x20), mload(data), 0x00, 0x20)
            if lt(returndatasize(), 0x20) { success := 0 }
            result := mload(0x00)
        }
        return success && result == bytes32(IERC1271.isValidSignature.selector);
    }

    /// @dev Protocol fee taken from `totalAmount` before the referral split. Zero when `feeBps` is 0 or the amount rounds down.
    function _protocolFee(uint256 totalAmount) internal view returns (uint256) {
        uint16 bps = feeBps;
        if (bps == 0) return 0;
        return (totalAmount * bps) / BPS_DENOMINATOR;
    }
}
