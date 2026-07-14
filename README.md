# Multi-Level Referral Reward System

## Overview

**Build viral growth through multi-level referral rewards.** When a user joins your platform, they can earn rewards not just from their own referrals, but also from their referrer's referrals, and their referrer's referrer's referrals - creating a powerful incentive for your users to grow the network.

## Contracts

- **ReferralGraph**: Manages referral relationships
- **RewardDistributor**: Distribute rewards up through the referral tree

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

**The reward pool flows upward** from the first referrer through the referral tree, with each level receiving a geometrically decreasing portion.

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

### Example: Oracle grants 1000 token referral bonus (`user` = User4)

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

### 2. Distribute Rewards

Projects distribute rewards using their tokens:

```solidity
bytes32 eventId = keccak256(abi.encodePacked(user3, "purchase"));
bytes32 groupId = keccak256("project-a-users");

// Oracle resolves the filtered payout chain (skiplisted addresses omitted) at signing time
address[] memory chain = referralGraph.getPayoutChain(user2, groupId, 10);
bytes32 chainHash = keccak256(abi.encode(chain));

ChainRewardData memory reward = ChainRewardData({
    user: user2,              // Seed address for the payout chain
    totalAmount: 1000e18,     // Referral bonus pool
    rewardToken: projectAToken,
    groupId: groupId,
    eventId: eventId,
    chainHash: chainHash      // Must match on-chain filtered chain
});

// Any contract can relay the call; oracle signs off-chain
// Hash is bound to chainid + verifying contract to prevent cross-deployment replay
bytes32 rewardHash = keccak256(
    abi.encodePacked(
        block.chainid,
        address(rewardDistributor),
        reward.user,
        reward.totalAmount,
        reward.rewardToken,
        reward.groupId,
        reward.eventId,
        reward.chainHash
    )
);
bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rewardHash));
bytes memory signature = signWithOracleKey(messageHash);

rewardDistributor.distributeChainRewards(reward, signature);
```

The recovered signer must be authorized for `reward.groupId`. Registration still requires the oracle to call `register` directly. Skiplisted addresses are omitted from the payout chain (no pay, no level consumed).

### 3. Skip List

Authorized registration oracles can exclude addresses from payout resolution without rewriting the referral graph:

```solidity
// Omit user2 from future payout chains in this group
referralGraph.setSkiplisted(user2, groupId, true);

// Later, restore them
referralGraph.setSkiplisted(user2, groupId, false);
```

## Initial Setup

**1. Deploy Contracts**

```bash
# Deploy shared referral graph (with optional initial oracle for a specific group)
forge create src/core/ReferralGraph.sol:ReferralGraph --constructor-args <owner> <initialOracle> <initialGroupId>

# Deploy shared reward distributor
forge create src/core/RewardDistributor.sol:RewardDistributor --constructor-args <owner> <referralGraph> <initialOracle> <initialGroupId>
```

Pass `address(0)` for `initialOracle` and `bytes32(0)` for `initialGroupId` to skip constructor-time authorization and authorize oracles after deployment.

**2. Authorize Project Oracles**

**Important:** Registration and reward distribution are restricted to authorized oracles. Authorization is **per group** — an oracle authorized for Project A cannot act on Project B unless explicitly authorized there too. You must authorize oracles in both contracts:

```solidity
bytes32 projectAGroupId = keccak256("project-a-users");
bytes32 projectBGroupId = keccak256("project-b-users");

// Authorize Project A's oracle for Project A's group only
referralGraph.authorizeOracle(projectAOracle, projectAGroupId);
rewardDistributor.authorizeOracle(projectAOracle, projectAGroupId);

// Authorize Project B's oracle for Project B's group only
referralGraph.authorizeOracle(projectBOracle, projectBGroupId);
rewardDistributor.authorizeOracle(projectBOracle, projectBGroupId);
```

**Note:** Typically, you'll authorize the same oracles in both contracts for the same group. The same oracle address can be authorized for multiple groups independently.

**3. Configure Reward Distribution**

No configuration is needed. `totalAmount` is distributed upward from `user` using geometric decay.

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

### RewardDistributor Functions

#### Oracle Management

- `authorizeOracle(address oracle, bytes32 groupId)` - Authorize an oracle to distribute rewards in a group (owner only)
- `unauthorizeOracle(address oracle, bytes32 groupId)` - Remove oracle authorization for a group (owner only)
- `isAuthorizedOracle(address oracle, bytes32 groupId)` - Check if an oracle is authorized for a group
- `getAuthorizedOracles(bytes32 groupId)` - Get all authorized oracles for a group

#### Reward Distribution

- `distributeChainRewards(ChainRewardData reward, bytes signature)` - Distribute rewards (signer must be authorized for `reward.groupId`; callable by any address). Requires matching `chainHash` of the filtered payout chain. Failed transfers credit claimable balances instead of reverting the batch.
- `claim(address token)` / `claimFor(address recipient, address token)` - Withdraw claimable balances after a failed transfer
- `claimable(address recipient, address token)` - View claimable balance
- `rescueTokens(address token, address to, uint256 amount)` - Owner rescue (cannot drain reserved claimable amounts)

## Audits

- [Security Review — RewardDistributor.sol](https://bafkreicija67gjpc7nognuidf4hfuf73xhwbszqx5gukl7h5ms2c7znvvi.ipfs.community.bgipfs.com/)
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
