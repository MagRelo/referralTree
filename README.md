# Multi-Level Referral Reward System

## Overview

**Build viral growth through multi-level referral rewards.** When a user joins your platform, they can earn rewards not just from their own referrals, but also from their referrer's referrals, and their referrer's referrer's referrals - creating a powerful incentive for your users to grow the network.

## Contracts

- **ReferralGraph**: Attribution, skiplist, and payout-chain resolution. Does not hold funds.
- **RewardCalculator**: Geometric split math (`0.6` decay, max 10, remainder to index 0). Does not hold funds.

Your app still owns token transfers. ReferralTree does not journal payouts. Incentive Exchange indexes live paid-out from a single event your payout contract must emit in the same transaction as the transfers (see [Indexing](#indexing-referralsettlement)).

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

### 2. Resolve Chain and Distribute Rewards

Your app contract owns auth, funding, and transfers. Use the graph + calculator as read utilities, then emit `ReferralSettlement` in the **same transaction** so Incentive Exchange can index the payout:

```solidity
address[] memory chain = graph.getPayoutChain(user, groupId, 10);
require(chain.length > 0, "Empty payout chain");
uint256[] memory amounts = calculator.calculateRewards(totalAmount, chain.length);

for (uint256 i = 0; i < chain.length; i++) {
    if (amounts[i] == 0) continue;
    token.transfer(chain[i], amounts[i]);
}

emit ReferralSettlement(groupId, settlementId, user, address(token), totalAmount, chain, amounts);
```

Skiplisted addresses are omitted from the payout chain (no pay, no level consumed). Replay protection, event eligibility, and failure policy are your integrator’s responsibility.

### 3. Skip List

Authorized registration oracles can exclude addresses from payout resolution without rewriting the referral graph:

```solidity
// Omit user2 from future payout chains in this group
referralGraph.setSkiplisted(user2, groupId, true);

// Later, restore them
referralGraph.setSkiplisted(user2, groupId, false);
```

## Indexing: `ReferralSettlement`

ReferralTree does **not** record payouts. To be indexed (Incentive Exchange live stats, subgraphs, agent reputation), the **app payout contract** must emit this event in the same transaction as the referral transfers. A later backend log is not indexable as a settlement.

```solidity
/// @notice Declared mechanism split. Emit from the payout contract in the same tx as the transfers.
/// @param groupId Referral group
/// @param settlementId Caller-chosen idempotency key (e.g. keccak256(abi.encode(contestId)))
/// @param triggerUser Seed passed to getPayoutChain
/// @param token ERC20; use address(0) if the app paid native ETH
/// @param totalAmount Referral-network fee actually transferred (not winner-pool, not gross contest)
/// @param recipients Same order as getPayoutChain(triggerUser, groupId, 10)
/// @param amounts Same order as RewardCalculator.calculateRewards(totalAmount, recipients.length)
event ReferralSettlement(
    bytes32 indexed groupId,
    bytes32 indexed settlementId,
    address indexed triggerUser,
    address token,
    uint256 totalAmount,
    address[] recipients,
    uint256[] amounts
);
```

Copy the signature exactly. Indexers key on `topic0 = keccak256("ReferralSettlement(bytes32,bytes32,address,address,uint256,address[],uint256[])")`.

A listing is reporting-complete when:

- Every payout that matches the verified trigger emits `ReferralSettlement` in that tx
- `recipients` / `amounts` are the chain and split actually transferred
- `totalAmount` is the referral-network fee (not winner-pool, not gross contest)
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
