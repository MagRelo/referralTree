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
/// @param referrer The referrer address (must be in the group's referral tree, or address(0) for root registration)
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

ChainRewardData memory reward = ChainRewardData({
    user: user2,              // First referrer in the payout chain
    totalAmount: 1000e18,     // Referral bonus pool
    rewardToken: projectAToken,
    groupId: groupId,
    eventId: eventId
});

// Oracle distributes directly
rewardDistributor.distributeChainRewards(reward);
```

## Initial Setup

**1. Deploy Contracts**

```bash
# Deploy shared referral graph (with optional initial oracle)
forge create src/core/ReferralGraph.sol:ReferralGraph --constructor-args <owner> <initialOracle>

# Deploy shared reward distributor
forge create src/core/RewardDistributor.sol:RewardDistributor --constructor-args <owner> <referralGraph> <initialOracle>
```

**2. Authorize Project Oracles**

**Important:** Registration of referrals is restricted to authorized oracles only. You must authorize oracles in both contracts:

```solidity
// Authorize Project A's oracle in ReferralGraph (for registration)
referralGraph.authorizeOracle(projectAOracle);

// Authorize Project A's oracle in RewardDistributor (for reward distribution)
rewardDistributor.authorizeOracle(projectAOracle);

// Authorize Project B's oracle
referralGraph.authorizeOracle(projectBOracle);
rewardDistributor.authorizeOracle(projectBOracle);
```

**Note:** Typically, you'll authorize the same oracles in both contracts for consistency.

**3. Configure Reward Distribution**

No configuration is needed. `totalAmount` is distributed upward from `user` using geometric decay.

## API Reference

### ReferralGraph Functions

#### Referral Management

- `register(address user, address referrer, bytes32 groupId)` - Register referral in group (oracle-only, group auto-created on first registration)
- `batchRegister(address[] users, address referrer, bytes32 groupId)` - Batch register users (oracle-only)

#### Oracle Management

- `authorizeOracle(address oracle)` - Authorize an oracle to register referrals (owner only)
- `unauthorizeOracle(address oracle)` - Remove oracle authorization (owner only)
- `isAuthorizedOracle(address oracle)` - Check if an address is an authorized oracle
- `getAuthorizedOracles()` - Get all authorized oracles
- `getReferrer(address user, bytes32 groupId)` - Get referrer in group
- `getChildren(address referrer, bytes32 groupId)` - Get referrals in group
- `getAncestors(address user, bytes32 groupId, uint256 maxLevels)` - Get referral chain
- `isRegistered(address user, bytes32 groupId)` - Check registration in group

### RewardDistributor Functions

#### Oracle Management

- `authorizeOracle(address oracle)` - Authorize new oracle (owner only)
- `unauthorizeOracle(address oracle)` - Remove oracle authorization (owner only)
- `isAuthorizedOracle(address oracle)` - Check oracle authorization
- `getAuthorizedOracles()` - Get all authorized oracles

#### Reward Distribution

- `distributeChainRewards(ChainRewardData reward)` - Distribute rewards (oracle-only)

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
