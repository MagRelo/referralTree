# Multi-Level Referral Reward System

## Overview

**Build viral growth through multi-level referral rewards.** When a user joins your platform, they can earn rewards not just from their own referrals, but also from their referrer's referrals, and their referrer's referrer's referrals - creating a powerful incentive for your users to grow the network.

## Contracts

- **ReferralGraph**: Manages referral relationships
- **RewardDistributor**: Distribute rewards up through the referral tree

## How It Works

Imagine Alice refers Bob to your platform. Bob then refers Carol, and Carol refers Dave. When Dave earns a reward, **everyone up the referral chain gets rewarded**:

```
Referral Tree:           Reward Distribution:

    Alice                    Alice (12.60)
     │                        ▲
     ▼                        │
    Bob                      Bob   (42.00)
     │                        ▲
     ▼                        │
   Carol                    Carol  (140.00)
     │                        ▲
     ▼                        │
   Dave (earn reward)       Dave   (800.00)
```

**The reward pool flows upward** through the referral tree, with each level receiving a mathematically decreasing portion.

### Example: Oracle grants 1000 tokens

| Level    | User   | Amount | Cumulative |
| -------- | ------ | ------ | ---------- |
| Original | User5  | 800.00 | 800.00     |
| Level 0  | User4  | 140.00 | 940.00     |
| Level 1  | User3  | 42.00  | 982.00     |
| Level 2  | User2  | 12.60  | 994.60     |
| Level 3  | User1  | 3.78   | 998.38     |
| Level 4  | User0  | 1.13   | 999.51     |
| Dust     | Oracle | 0.49   | 1000.00    |

**Total Distributed:** 1000.00 tokens (100% utilization - dust to oracle)

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
bytes32 eventId = keccak256(abi.encodePacked(user3, block.timestamp, "purchase"));
bytes32 groupId = keccak256("project-a-users");

// Project A's reward distribution
ChainRewardData memory reward = ChainRewardData({
    user: user3,              // User who triggered the event
    totalAmount: 1000e18,     // Total reward amount
    rewardToken: projectAToken, // Project A's token
    groupId: groupId,         // Referral chain from this group
    eventId: eventId,
    timestamp: block.timestamp,
    nonce: 1
});

// Oracle signs and distributes
bytes memory signature = signReward(reward, projectAOraclePrivateKey);
/// @notice Distribute rewards across referral chain
/// @param reward The chain reward data containing base amount for percentage calculations
/// @param signature Oracle signature of the reward data
/// @dev Only distributes to referrers based on decay percentages, not the full totalAmount
rewardDistributor.distributeChainRewards(reward, signature);
```

## Initial Setup

**1. Deploy Contracts**

```bash
# Deploy shared referral graph
forge create src/core/ReferralGraph.sol:ReferralGraph --constructor-args <owner> <root> <allowlist>

# Deploy shared reward distributor
forge create src/core/RewardDistributor.sol:RewardDistributor --constructor-args <owner> <referralGraph> <initialOracle>
```

**2. Authorize Project Oracles**

Authorize oracles for different projects:

```solidity
// Authorize Project A's oracle
rewardDistributor.authorizeOracle(projectAOracle);

// Authorize Project B's oracle
rewardDistributor.authorizeOracle(projectBOracle);
```

**3. Configure Reward Distribution**

Set system-wide reward parameters:

```solidity
// Set decay parameters (70% retention per level)
rewardDistributor.setDecayConfig(IRewardDistributor.DecayType.EXPONENTIAL, 7000, 0.01 ether);

// Set original user reward percentage (80%)
rewardDistributor.setOriginalUserPercentage(8000);
```

## API Reference

### ReferralGraph Functions

#### Referral Management

- `register(address user, address referrer, bytes32 groupId)` - Register referral in group (group auto-created on first registration)
- `batchRegister(address[] users, address referrer, bytes32 groupId)` - Batch register users
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

#### Reward Configuration

- `setDecayConfig(DecayType type, uint256 factor, uint256 minReward)` - Configure decay (owner only)
- `setOriginalUserPercentage(uint256 percentage)` - Set user reward percentage (owner only)
- `getDecayConfig()` - Get current decay settings
- `getOriginalUserPercentage()` - Get user percentage

#### Reward Distribution

- `distributeChainRewards(ChainRewardData reward, bytes signature)` - Distribute rewards

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
