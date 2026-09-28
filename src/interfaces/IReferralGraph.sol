// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IReferralGraph
 * @notice Interface for the ReferralGraph contract that manages referral relationships
 */
interface IReferralGraph {
    /// @notice Emitted when a user registers with a referrer
    /// @dev Breaking ABI vs v1: `groupId` is indexed so indexers can attribute registrations per project
    event UserRegistered(bytes32 indexed groupId, address indexed user, address indexed referrer);

    /// @notice Emitted when an oracle is authorized for a group
    event OracleAuthorized(bytes32 indexed groupId, address indexed oracle);

    /// @notice Emitted when an oracle is unauthorized for a group
    event OracleUnauthorized(bytes32 indexed groupId, address indexed oracle);

    /// @notice Emitted when an address is added to a group's skip list
    event AddressSkiplisted(bytes32 indexed groupId, address indexed user);

    /// @notice Emitted when an address is removed from a group's skip list
    event AddressUnskiplisted(bytes32 indexed groupId, address indexed user);

    /// @notice Emitted by rewardRoots after the payout chain has been paid
    /// @dev topic0 is stable for indexers. Recipients are the skiplist-aware payout chain.
    ///      `distributedAmount` is the net amount split across `recipients` (sum of `amounts`), i.e. the gross
    ///      `totalAmount` minus the protocol fee. `distributedAmount + ProtocolFeeCharged.amount == totalAmount` (gross);
    ///      when no fee is charged there is no ProtocolFeeCharged event and `distributedAmount == totalAmount`.
    /// @param distributedAmount Net referral amount paid to `recipients` (excludes the protocol fee)
    event RootsRewarded(
        bytes32 indexed groupId,
        bytes32 indexed rewardId,
        address indexed triggerUser,
        address token,
        uint256 distributedAmount,
        address[] recipients,
        uint256[] amounts
    );

    /// @notice Emitted by rewardLeaf after `user` has been paid directly
    /// @dev Same net/gross semantics as RootsRewarded: `distributedAmount + ProtocolFeeCharged.amount == totalAmount`.
    /// @param distributedAmount Net amount paid to `user` (excludes the protocol fee)
    event LeafRewarded(
        bytes32 indexed groupId,
        bytes32 indexed rewardId,
        address indexed user,
        address token,
        uint256 distributedAmount
    );

    /// @notice Emitted when the owner sets the reward calculator used by rewardRoots
    event RewardCalculatorSet(address indexed calculator);

    /// @notice Emitted when the owner sets the global protocol fee
    event ProtocolFeeSet(uint16 bps, address indexed recipient);

    /// @notice Emitted when rewardRoots or rewardLeaf takes the protocol fee from `totalAmount`
    /// @dev Emitted in the same call as RootsRewarded or LeafRewarded (same groupId/rewardId), only when the fee is
    ///      non-zero. `distributedAmount + amount == totalAmount` (gross). To get gross volume, sum both; do not add
    ///      `amount` to a gross figure.
    event ProtocolFeeCharged(
        bytes32 indexed groupId, bytes32 indexed rewardId, address indexed token, address recipient, uint256 amount
    );

    /// @notice Error when user address is invalid (zero address)
    error InvalidUserAddress();

    /// @notice Error when referrer address is invalid (zero address or not in tree)
    error InvalidReferrerAddress();

    /// @notice Error when oracle address is invalid (zero address)
    error InvalidOracleAddress();

    /// @notice Error when trying to refer oneself
    error SelfReferralNotAllowed();

    /// @notice Error when referrer is not in the referral tree
    error ReferrerNotInTree();

    /// @notice Error when user is already registered
    error UserAlreadyRegistered();

    /// @notice Error when caller is not an authorized oracle
    error UnauthorizedOracle();

    /// @notice Error when rewardRoots is called before a reward calculator is set
    error RewardCalculatorNotSet();

    /// @notice Error when the reward calculator address is zero
    error InvalidRewardCalculator();

    /// @notice Error when the payout token is the zero address
    error InvalidToken();

    /// @notice Error when the reward amount is zero
    error InvalidAmount();

    /// @notice Error when the trigger user is not registered in the group
    error UserNotRegistered();

    /// @notice Error when getPayoutChain returns no recipients
    error EmptyPayoutChain();

    /// @notice Error when this rewardId was already used for the group (by rewardRoots or rewardLeaf)
    error RewardIdUsed();

    /// @notice Error when the calculator split does not match the payout chain
    error InvalidSplit();

    /// @notice Error when the protocol fee is above MAX_FEE_BPS (10%)
    error FeeTooHigh();

    /// @notice Error when a non-zero protocol fee has no recipient
    error InvalidFeeRecipient();

    /// @notice Error when a reward signature is past its deadline
    error SignatureExpired();

    /// @notice Error when the claimed oracle is not authorized for the group or its signature is invalid
    error InvalidSigner();

    /// @notice Get the referrer of a user in a group
    /// @param user The user to query
    /// @param groupId The group ID
    /// @return The address of the referrer, or address(0) if not registered
    function getReferrer(address user, bytes32 groupId) external view returns (address);

    /// @notice Get the children of a referrer in a group
    /// @param referrer The referrer to query
    /// @param groupId The group ID
    /// @return Array of addresses that were referred by this referrer
    function getChildren(address referrer, bytes32 groupId) external view returns (address[] memory);

    /// @notice Get the ancestor chain for a user in a group (from user up to root)
    /// @param user The user to get ancestors for
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of levels to traverse
    /// @return Array of ancestors, starting with immediate referrer
    function getAncestors(address user, bytes32 groupId, uint256 maxLevels) external view returns (address[] memory);

    /// @notice Get ancestors with skiplisted addresses removed (does not count them toward maxLevels)
    /// @param user The user to get ancestors for
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of non-skiplisted ancestors to return
    /// @return Array of non-skiplisted ancestors, starting with the nearest eligible referrer
    function getPayoutAncestors(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory);

    /// @notice Build the payout chain starting from `user`, omitting skiplisted addresses
    /// @param user First candidate recipient (omitted if skiplisted; walk continues upward)
    /// @param groupId The group ID
    /// @param maxLevels Maximum number of paid recipients to return
    /// @return chain Non-skiplisted addresses from `user` upward, capped at `maxLevels`
    function getPayoutChain(address user, bytes32 groupId, uint256 maxLevels)
        external
        view
        returns (address[] memory chain);

    /// @notice Check if a user is registered in a group
    /// @param user The user to check
    /// @param groupId The group ID
    /// @return True if the user has a referrer in the group
    function isRegistered(address user, bytes32 groupId) external view returns (bool);

    /// @notice Check if an address is on the skip list for a group
    /// @param user The address to check
    /// @param groupId The group ID
    /// @return True if skiplisted
    function isSkiplisted(address user, bytes32 groupId) external view returns (bool);

    /// @notice Get all skiplisted addresses for a group
    /// @param groupId The group to query
    /// @return Array of skiplisted addresses
    function getSkiplisted(bytes32 groupId) external view returns (address[] memory);

    /// @notice Number of successfully registered users in a group (excludes REFERRAL_ROOT)
    /// @param groupId The group to query
    /// @return Count of registrations; never decrements
    function registeredCount(bytes32 groupId) external view returns (uint256);

    /// @notice Number of currently skiplisted addresses in a group
    /// @param groupId The group to query
    /// @return Length of the skiplist (no extra storage)
    function skiplistedCount(bytes32 groupId) external view returns (uint256);

    /// @notice Add or remove an address from a group's skip list
    /// @param user The address to update
    /// @param groupId The group ID
    /// @param skiplisted True to skiplist, false to remove
    /// @dev Only callable by an oracle authorized for `groupId`
    function setSkiplisted(address user, bytes32 groupId, bool skiplisted) external;

    /// @notice Register a user with a referrer in a group
    /// @param user The user being registered
    /// @param referrer The referrer address (must be in the group's referral tree, or REFERRAL_ROOT for root registration)
    /// @param groupId The group ID (group is auto-created on first registration)
    /// @dev Groups are implicitly created when the first user registers. A user is in a group's referral tree if they have been referred or have referred others.
    function register(address user, address referrer, bytes32 groupId) external;

    /// @notice Batch register multiple users with the same referrer in a group
    /// @param users Array of users to register
    /// @param referrer The referrer for all users
    /// @param groupId The group ID
    function batchRegister(address[] calldata users, address referrer, bytes32 groupId) external;

    /// @notice Authorize an oracle to register referrals in a group
    /// @param oracle The oracle address to authorize
    /// @param groupId The group the oracle is authorized for
    function authorizeOracle(address oracle, bytes32 groupId) external;

    /// @notice Unauthorize an oracle for a group
    /// @param oracle The oracle address to unauthorize
    /// @param groupId The group to remove authorization from
    function unauthorizeOracle(address oracle, bytes32 groupId) external;

    /// @notice Check if an address is an authorized oracle for a group
    /// @param oracle The address to check
    /// @param groupId The group to check authorization for
    /// @return True if authorized for the group
    function isAuthorizedOracle(address oracle, bytes32 groupId) external view returns (bool);

    /// @notice Get all authorized oracles for a group
    /// @param groupId The group to query
    /// @return Array of authorized oracle addresses for the group
    function getAuthorizedOracles(bytes32 groupId) external view returns (address[] memory);

    /// @notice Set the reward calculator. Only the owner.
    /// @param calculator RewardCalculator address
    function setRewardCalculator(address calculator) external;

    /// @notice Global protocol fee in basis points. 10000 = 100%; capped at MAX_FEE_BPS (1000 = 10%). Defaults to 0.
    function feeBps() external view returns (uint16);

    /// @notice Recipient of the protocol fee charged on rewardRoots / rewardLeaf
    function feeRecipient() external view returns (address);

    /// @notice Set the global protocol fee. Only the owner.
    /// @dev `bps == 0` charges nothing. A non-zero fee requires a recipient. Reverts with FeeTooHigh above MAX_FEE_BPS (1000 = 10%).
    /// @param bps Fee in basis points of `totalAmount`, deducted from `totalAmount` before the reward is paid
    /// @param recipient Address that receives the protocol fee
    function setProtocolFee(uint16 bps, address recipient) external;

    /// @notice EIP-712 domain separator for oracle-signed rewards (name "ReferralGraph", version "1")
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice EIP-712 typehash:
    ///         RewardRoots(bytes32 groupId,bytes32 rewardId,address user,address token,uint256 totalAmount,address payer,uint256 deadline)
    function REWARD_ROOTS_TYPEHASH() external view returns (bytes32);

    /// @notice EIP-712 typehash:
    ///         RewardLeaf(bytes32 groupId,bytes32 rewardId,address user,address token,uint256 totalAmount,address payer,uint256 deadline)
    function REWARD_LEAF_TYPEHASH() external view returns (bytes32);

    /// @notice Pull `totalAmount` of `token` from the caller, take any protocol fee from it, split the remainder across
    ///         `user`'s skiplist-aware payout chain, and emit RootsRewarded
    /// @dev Authorization is an EIP-712 `RewardRoots` signature from `oracle`, which must be authorized for `groupId`
    ///      (checked at execution time, so unauthorizing an oracle invalidates its outstanding signatures). A 65- or
    ///      64-byte (EIP-2098) signature is first checked with ecrecover against `oracle` (EOAs, including
    ///      EIP-7702-delegated EOAs); if that does not match and `oracle` has code, ERC-1271 `isValidSignature` is used
    ///      (no ERC-6492). Anyone may submit, but the signed `payer` must equal `msg.sender`; all tokens are pulled from
    ///      `msg.sender`. `rewardId` is the nonce, shared with rewardLeaf: each id is used at most once per group.
    ///      `user` must be registered in the group. Does not retain a token balance.
    /// @param groupId The referral group
    /// @param rewardId Oracle-chosen idempotency key / signature nonce
    /// @param user Registered seed passed to getPayoutChain
    /// @param token ERC20 to pull and forward
    /// @param totalAmount Gross amount. Protocol fee (if any) is deducted first; the remainder is split across the referral chain. Caller approves exactly `totalAmount`.
    /// @param deadline Last timestamp (inclusive) at which the signature is valid
    /// @param oracle Oracle that signed (EOA or ERC-1271 contract); must be authorized for `groupId`
    /// @param signature ECDSA signature or ERC-1271 signature blob over the RewardRoots digest
    function rewardRoots(
        bytes32 groupId,
        bytes32 rewardId,
        address user,
        address token,
        uint256 totalAmount,
        uint256 deadline,
        address oracle,
        bytes calldata signature
    ) external;

    /// @notice Pull `totalAmount` of `token` from the caller, take any protocol fee from it, pay the remainder to
    ///         `user` directly, and emit LeafRewarded
    /// @dev Same authorization, deadline, payer binding, rewardId namespace, fee and `user` checks as rewardRoots, but
    ///      signed over the distinct `RewardLeaf` typehash, so a RewardRoots signature cannot be used here and vice versa.
    /// @param groupId The referral group
    /// @param rewardId Oracle-chosen idempotency key / signature nonce (shared namespace with rewardRoots)
    /// @param user Registered user to pay
    /// @param token ERC20 to pull and forward
    /// @param totalAmount Gross amount. Protocol fee (if any) is deducted first; `user` receives the remainder. Caller approves exactly `totalAmount`.
    /// @param deadline Last timestamp (inclusive) at which the signature is valid
    /// @param oracle Oracle that signed (EOA or ERC-1271 contract); must be authorized for `groupId`
    /// @param signature ECDSA signature or ERC-1271 signature blob over the RewardLeaf digest
    function rewardLeaf(
        bytes32 groupId,
        bytes32 rewardId,
        address user,
        address token,
        uint256 totalAmount,
        uint256 deadline,
        address oracle,
        bytes calldata signature
    ) external;
}
