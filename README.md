# Multi-Level Referral Reward System

## Overview

**Build viral growth through multi-level referral rewards.** When a user joins your platform, they can earn rewards not just from their own referrals, but also from their referrer's referrals, and their referrer's referrer's referrals - creating a powerful incentive for your users to grow the network.

## Contracts

- **ReferralGraph**: Attribution, skiplist, payout-chain resolution, and `settle`. Pulls the fee and forwards it in that call. Does not keep a balance.
- **RewardCalculator**: Geometric split math (`0.6` decay, max 10, remainder to index 0). Does not hold funds.

An authorized oracle signs an EIP-712 `Settle` message; the payer (any address, e.g. your app's payout contract) submits it to `settle`. The graph pulls the fee from `msg.sender`, pays the chain, and emits `ReferralSettlement`. Incentive Exchange indexes that event (see [Indexing](#indexing-referralsettlement)).

## How It Works

Imagine Alice refers Bob to your platform. Bob then refers Carol, and Carol refers Dave. When a referral bonus is distributed with `user` set to Carol, **everyone from Carol up the referral chain gets rewarded**:

```
Referral Tree:           Reward Distribution (user = Carol):

    User0                     User0 (11.38)
     │                        ▲
     ▼                        │
    User1                    User1  (18.72)
     │                        ▲
     ▼                        │
   User2                    User2   (31.21)
     │                        ▲
     ▼                        │
   User3                    User3   (52.01)
     │                        ▲
     ▼                        │
   User4 (Carol)            User4   (86.68)
     │
   User5 (Dave)
```

**The reward pool flows upward** from the seed user through the referral tree, with each level receiving a geometrically decreasing portion. Your app resolves the chain and amounts on-chain, then transfers tokens itself.

### Exponential Network Growth

In reality, each user refers multiple people, creating exponential growth. Here's a full referral tree showing how Alice can earn from dozens of users:

```
Referral Tree (each person refers multiple users):

          Alice (earns from ALL below)
        /   |   \
       /    |    \
      ▼     ▼     ▼
     Bob   Charlie Diana
    / \     │     │
   ▼   ▼    ▼     ▼
  Eve Fred Gina   Hal
   │   │    │     │
   └───┴────┴─────┘ (and many more...)
```

**Exponential Growth:** If each user refers just 3 others, Alice could eventually earn referral income from hundreds of users in her network. Each person below Alice (Bob, Charlie, Diana) refers their own users, who then refer more users, creating a cascading effect where early adopters like Alice benefit from exponential network growth.

### Example: 1000 token referral bonus (`user` = User4)

| Level | User  | Amount | Cumulative |
| ----- | ----- | ------ | ---------- |
| 0     | User4 | 434.06 | 434.06     |
| 1     | User3 | 260.08 | 694.14     |
| 2     | User2 | 156.05 | 850.19     |
| 3     | User1 | 93.63  | 943.82     |
| 4     | User0 | 56.18  | 1000.00    |

**Total Distributed:** 1000.00 tokens

### Group Incentives

Groups create competitive referral markets where early group members and creators can earn significant rewards:

- **Group creators** automatically become the first members and can position themselves at the top of referral chains
- **Early joiners** get first-mover advantage in building referral networks within their group
- **Isolated networks** mean successful groups create their own reward economies

## Usage

### 1. Build Referral Networks

Groups are automatically created when the first user registers. Simply register users with their referrers:

```solidity
bytes32 groupId = keccak256("project-a-users");

/// @notice Register a user with a referrer in a group
/// @param user The user being registered
/// @param referrer The referrer address (must be in the group's referral tree, or REFERRAL_ROOT for root registration)
/// @param groupId The group ID
/// @dev Groups are implicitly created when the first user registers. A user is in a group's referral tree if they have been referred or have referred others.
referralGraph.register(user1, root, groupId);

// User1 refers User2 in the same group
referralGraph.register(user2, user1, groupId);

// User2 refers User3 in the same group
referralGraph.register(user3, user2, groupId);

// Batch register multiple users
address[] memory newUsers = [user4, user5, user6];
referralGraph.batchRegister(newUsers, user3, groupId);
```

**Note:** Groups are implicit - they exist once the first referral relationship is stored. A user is in a group's referral tree if they have been referred OR have referred others.

### 2. Settle

`settle` is authorized by an EIP-712 signature from an oracle authorized for `groupId` (there is no `tx.origin` or caller whitelist). Anyone may submit the signature, but the signed `payer` must be the address that calls `settle`, because that is who the tokens are pulled from. An oracle settling for itself signs with `payer = oracle` and submits. The submitter passes the signing `oracle` address and the `signature` bytes. `register` still requires `msg.sender` itself to be the oracle.

The graph resolves the chain, splits, pulls the tokens from `msg.sender`, pays, and emits. If a transfer fails, the call reverts and there is no event. `token` must be a deployed contract: a zero or codeless address (e.g. a CREATE2 token not yet deployed) reverts with `InvalidToken` before anything is written, so the `settlementId` remains usable.

**Signed payload** (domain: `name = "ReferralGraph"`, `version = "1"`, `chainId`, `verifyingContract = graph`):

```
Settle(bytes32 groupId,bytes32 settlementId,address user,address token,uint256 totalAmount,address payer,uint256 deadline)
```

- `settlementId` is the nonce: each id settles at most once per group, whoever submits it.
- `deadline` is inclusive (`block.timestamp <= deadline`).
- The signer's oracle authorization is checked when `settle` executes, so `unauthorizeOracle` invalidates that oracle's outstanding signatures.
- `DOMAIN_SEPARATOR()` is cached for the deploy chain id and recomputed if the chain id changes (fork), as in solmate `ERC20.permit`. High-s signatures are not rejected (also as in solmate); since `settlementId` is consumed on first use, a malleated signature cannot replay a settlement.

**Verification order.** `oracle` must be authorized for `groupId` (checked first). Then:

1. **ECDSA first:** if `signature` is 65 bytes (`r‖s‖v`) or 64 bytes (EIP-2098 compact `r‖vs`) and `ecrecover(digest) == oracle` (non-zero), it is valid — regardless of whether `oracle` has code. This covers plain EOAs and **EIP-7702-delegated EOAs** (code `0xef0100‖delegate`), even if the delegate has no `isValidSignature`.
2. **ERC-1271 fallback:** otherwise, if `oracle` has code (a Safe, smart account, or 7702 EOA whose delegate implements 1271, e.g. with session keys), the graph `staticcall`s `oracle.isValidSignature(digest, signature)` and accepts only if the call succeeds and returns exactly the magic value `0x1626ba7e` (ABI-encoded, at least 32 bytes). A reverting or garbage-returning wallet makes `settle` revert with `InvalidSigner`.
3. Otherwise invalid (`InvalidSigner`).

- **Trust:** a contract oracle decides for itself what counts as a valid signature, so authorizing one delegates settle authority for the group to that contract's logic (and its upgrades/modules).
- **Gas:** all remaining gas is forwarded to `isValidSignature`; the payer pays for it. Only 32 bytes of returndata are copied.
- **7702:** a delegated EOA's own key always remains valid via step 1; the delegate cannot revoke it.
- **Not supported:** ERC-6492 (signatures from not-yet-deployed wallets) — a contract oracle must be deployed.

The global protocol fee defaults to **0** and is hard-capped at `MAX_FEE_BPS` (1000 bps = 10%). When the owner sets `feeBps`, settle deducts `totalAmount * feeBps / 10000` from the settle total at the start and sends that share to `feeRecipient`. The remainder is split across the referral chain. The caller pays exactly `totalAmount` (not an extra top-up). `ReferralSettlement.distributedAmount` is the net referral amount (`totalAmount - protocolFee`); `distributedAmount + ProtocolFeeCharged.amount == totalAmount`.

```solidity
// Off-chain: oracle signs Settle{groupId, settlementId, user, token, totalAmount, payer, deadline}
//   EOA: signature = abi.encodePacked(r, s, v) (or 64-byte EIP-2098); contract oracle: whatever its isValidSignature expects
// On-chain, from `payer`:
token.approve(address(graph), totalAmount);
graph.settle(groupId, settlementId, user, address(token), totalAmount, deadline, oracle, signature);
```

Skiplisted addresses are omitted from the payout chain (no pay, no level consumed). `settlementId` cannot be reused for that group. Approve the exact `totalAmount` for the call, not an unlimited allowance.

### 3. Skip List

Authorized registration oracles can exclude addresses from payout resolution without rewriting the referral graph:

```solidity
// Omit user2 from future payout chains in this group
referralGraph.setSkiplisted(user2, groupId, true);

// Later, restore them
referralGraph.setSkiplisted(user2, groupId, false);
```

## Indexing: `ReferralSettlement`

`ReferralGraph.settle` emits this event after the transfers succeed. Indexers watch the graph contract. A later backend log is not a settlement.

```solidity
/// @notice Emitted by ReferralGraph.settle
/// @param groupId Referral group
/// @param settlementId Caller-chosen idempotency key (e.g. keccak256(abi.encode(contestId)))
/// @param triggerUser Seed passed to getPayoutChain
/// @param token ERC20 that was pulled and forwarded
/// @param distributedAmount Net referral amount actually transferred to recipients (settle totalAmount minus protocol fee; not winner-pool, not gross contest)
/// @param recipients Skiplist-aware payout chain, at most 10
/// @param amounts Geometric split of distributedAmount, same order as recipients (sums to distributedAmount)
event ReferralSettlement(
    bytes32 indexed groupId,
    bytes32 indexed settlementId,
    address indexed triggerUser,
    address token,
    uint256 distributedAmount,
    address[] recipients,
    uint256[] amounts
);
```

Indexers key on `topic0 = keccak256("ReferralSettlement(bytes32,bytes32,address,address,uint256,address[],uint256[])")` = `0xc1d7413a8f588edf973af385db8ba0409e45acbef501d8191166c42dd88ce3b3` at the graph address. (The fifth field was renamed from `totalAmount` to `distributedAmount`; parameter names are not part of topic0, so the selector and log encoding are unchanged — only ABI-JSON-based decoders see the new name.)

**Amounts and the protocol fee.** `distributedAmount` is net of the protocol fee. When a fee is charged, the same transaction also emits `ProtocolFeeCharged(groupId, settlementId, token, recipient, amount)`, and `distributedAmount + ProtocolFeeCharged.amount == settle totalAmount` (gross). Referral paid-out = sum of `distributedAmount`; gross settle volume = paid-out + sum of `ProtocolFeeCharged.amount` (join on `groupId`/`settlementId`). Don't add the fee to `distributedAmount` and call it paid-out.

A listing is reporting-complete when:

- Payouts go through `settle` on that graph (the event is not optional)
- `distributedAmount` is the referral-network amount paid to the chain (net of any protocol fee; not winner-pool, not gross contest)
- Graph oracles / skiplist policy are documented
- IE can read `registeredCount` and `skiplistedCount` on the graph, and derive settlement count, `totalPaid(token)`, paid participants, and recency from this event

Listings that only have a v1 graph (no `groupId` on `UserRegistered`, no counters) may show verification of terms, not live paid-out.

## Initial Setup

**1. Deploy Contracts**

This is a **new deploy** (v2). Live Base / Base Sepolia ReferralGraph contracts are not upgradeable; leave them in place. Existing Play the Cut traffic can keep the v1 graph until they opt in.

```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast

# Or deploy individually:
forge create src/core/ReferralGraph.sol:ReferralGraph --constructor-args <owner> <initialOracle> <initialGroupId>
forge create src/core/RewardCalculator.sol:RewardCalculator
```

Pass `address(0)` for `initialOracle` and `bytes32(0)` for `initialGroupId` to skip constructor-time authorization and authorize oracles after deployment.

**2. Authorize Project Oracles**

Registration and skiplist management are restricted to authorized oracles. Authorization is **per group** — an oracle authorized for Project A cannot act on Project B unless explicitly authorized there too:

```solidity
bytes32 projectAGroupId = keccak256("project-a-users");
bytes32 projectBGroupId = keccak256("project-b-users");

referralGraph.authorizeOracle(projectAOracle, projectAGroupId);
referralGraph.authorizeOracle(projectBOracle, projectBGroupId);
```

## API Reference

### ReferralGraph Functions

#### Referral Management

- `register(address user, address referrer, bytes32 groupId)` - Register referral in group (oracle-only, group auto-created on first registration). Root registration uses `REFERRAL_ROOT` (`0x…01`), not `address(0)`.
- `batchRegister(address[] users, address referrer, bytes32 groupId)` - Batch register users (oracle-only)

#### Skip List

- `setSkiplisted(address user, bytes32 groupId, bool skiplisted)` - Add/remove an address from the skip list (oracle-only for that group)
- `isSkiplisted(address user, bytes32 groupId)` - Check if an address is skiplisted
- `getSkiplisted(bytes32 groupId)` - Enumerate skiplisted addresses for a group
- `getPayoutAncestors(address user, bytes32 groupId, uint256 maxLevels)` - Ancestors with skiplisted addresses omitted
- `getPayoutChain(address user, bytes32 groupId, uint256 maxLevels)` - Seed + ancestors with skiplisted addresses omitted (used for rewards)

#### Oracle Management

- `authorizeOracle(address oracle, bytes32 groupId)` - Authorize an oracle to register referrals / manage skip list in a group (owner only)
- `unauthorizeOracle(address oracle, bytes32 groupId)` - Remove oracle authorization for a group (owner only)
- `isAuthorizedOracle(address oracle, bytes32 groupId)` - Check if an oracle is authorized for a group
- `getAuthorizedOracles(bytes32 groupId)` - Get all authorized oracles for a group
- `getReferrer(address user, bytes32 groupId)` - Get referrer in group
- `getChildren(address referrer, bytes32 groupId)` - Get referrals in group
- `getAncestors(address user, bytes32 groupId, uint256 maxLevels)` - Get raw referral chain (includes skiplisted)
- `isRegistered(address user, bytes32 groupId)` - Check registration in group
- `registeredCount(bytes32 groupId)` - Successful registrations in the group (excludes `REFERRAL_ROOT`; never decrements)
- `skiplistedCount(bytes32 groupId)` - Current skiplist length (no extra storage)
- `setRewardCalculator(address calculator)` - Set the geometric splitter used by `settle` (owner only)
- `settle(bytes32 groupId, bytes32 settlementId, address user, address token, uint256 totalAmount, uint256 deadline, address oracle, bytes signature)` - Verify `oracle`'s EIP-712 `Settle` signature (ECDSA against `oracle` first, then ERC-1271 if `oracle` has code; `payer = msg.sender`), pull the referral fee from `msg.sender`, pay the payout chain, emit `ReferralSettlement`
- `DOMAIN_SEPARATOR()` / `SETTLE_TYPEHASH()` - EIP-712 domain separator and `Settle` typehash for off-chain signers
- `setProtocolFee(uint16 bps, address recipient)` - Global protocol fee in bps of `totalAmount`, deducted from the settle total before the referral split (owner only; defaults to 0; capped at `MAX_FEE_BPS` = 1000, i.e. 10%)
- `feeBps()` / `feeRecipient()` - Current protocol fee config

`UserRegistered` is `event UserRegistered(bytes32 indexed groupId, address indexed user, address indexed referrer)` (**breaking ABI** vs v1; any subgraph / listener must be updated).

### RewardCalculator Functions

- `calculateRewards(uint256 totalReward, uint256 numRecipients)` - Geometric 0.6 decay split; caps at 10 recipients; remainder goes to the first recipient so the array sums exactly to `totalReward`

## Audits

- [Security Audit Report — referralTree](https://bafkreiht462u57pucb7h6n7ntznycby7cauzaupbvuswvl7hytd5ov3dc4.ipfs.community.bgipfs.com/)

## Development

```bash
# Install dependencies
forge install

# Run tests
forge test

# Run specific test contract
forge test --match-contract ReferralGraphTest

# Deploy locally
anvil
forge script script/Deploy.s.sol
```
