# Query Incentive Network Referral System

## Overview

A composable, multi-tenant referral system that enables projects to create competitive referral markets with isolated user groups. Each group maintains its own referral network while sharing common infrastructure for reward distribution.

## Architecture

### Core Contracts

- **ReferralGraph**: Manages referral relationships within isolated user groups
- **RewardDistributor**: Core reward distribution contract handling mathematical reward distribution using group-scoped referral chains

### Key Features

- **Group Isolation**: Each user group has independent referral networks
- **Multi-Oracle Support**: Multiple authorized oracles for different projects
- **Multi-Token Rewards**: Per-distribution token flexibility
- **Mathematical Decay**: Configurable reward distribution algorithms
- **Shared Infrastructure**: Single deployment serves multiple projects
- **Owner-Controlled**: Centralized oracle authorization and configuration

## Reward Distribution

### Default Configuration

```solidity
Decay Type: EXPONENTIAL (70% retention)
Original User: 80% of total rewards
Referral Chain: 20% distributed via exponential decay
Min Reward: 0.01 ether (dust prevention)
```

### Example: 1000 Tokens, 5-Level Chain

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

## Reward Distribution Limits

Reward distribution stops naturally when rewards decay below the `minReward` threshold (default: 0.01 ether). This provides a practical limit due to diminishing reward values while allowing unlimited tree growth and participation.

### Key Behavior

- **Unlimited Tree Growth**: Users can register at any depth - there is no registration limit
- **Natural Distribution Limit**: Rewards stop distributing when they decay below `minReward`
- **No Artificial Caps**: Distribution continues until rewards become too small to be meaningful

### Example: Deep Tree, Natural Decay

```
Tree Structure (unlimited depth):
Root → User1 → User2 → User3 → User4 → User5 → User6 → User7 → User8 → User9 → User10

Reward Distribution (stops naturally):
User10 triggers reward → Rewards distribute up the chain until they decay below minReward
With exponential decay (70% retention), rewards typically stop after 5-7 levels naturally
```

### Why This Design?

1. **Unlimited Participation**: Users at any depth can refer and participate
2. **Natural Limits**: Rewards stop when they become too small, not artificially
3. **Diminishing Returns**: Rewards naturally become tiny after a few levels due to decay
4. **Simple & Elegant**: No need to configure depth limits - the math handles it

## Group Incentives

Groups create competitive referral markets where early group members and creators can earn significant rewards:

### Group Creation Incentives

- **Group creators** automatically become the first members and can position themselves at the top of referral chains
- **Early joiners** get first-mover advantage in building referral networks within their group
- **Isolated networks** mean successful groups create their own reward economies

### Cross-Group Benefits

- **Same user in multiple groups** can earn rewards from different referral chains
- **Projects can target specific communities** through group-based reward distributions
- **Flexible token economics** allow different reward structures per group/project

## Decay Functions

### Exponential Decay (Default)

Each level takes a percentage of the remaining amount:

- **70% retention**: Balanced decay rewarding deep chains
- **Sequential distribution**: Prevents overspending
- **Configurable**: Adjust retention percentage as needed

### Alternative Configurations

**More Aggressive Decay (50% retention):**

- User5: 800.00 → User4: 100.00 → User3: 50.00 → User2: 25.00 → User1: 12.50 → User0: 6.25 → ... → Oracle: ~0.01
- **Total:** ~999.99 tokens (many small levels until minReward)

**Gentler Decay (85% retention):**

- User5: 800.00 → User4: 170.00 → User3: 25.50 → User2: 3.83 → User1: 0.57 → User0: 0.086 → Oracle: 0.014
- **Total:** 1000.00 tokens

## Usage

### 1. Deploy Shared Infrastructure

As the system owner, deploy once:

```bash
# Deploy shared referral graph
forge create src/core/ReferralGraph.sol:ReferralGraph --constructor-args <owner> <root> <allowlist>

# Deploy shared reward distributor
forge create src/core/RewardDistributor.sol:RewardDistributor --constructor-args <owner> <referralGraph> <initialOracle>
```

**Note**: Reward distribution stops naturally when rewards decay below `minReward` (default: 0.01 ether). There are no artificial depth limits - the mathematical decay function handles stopping distribution when rewards become too small.

### 2. Authorize Project Oracles

Authorize oracles for different projects:

```solidity
// Authorize Project A's oracle
rewardDistributor.authorizeOracle(projectAOracle);

// Authorize Project B's oracle
rewardDistributor.authorizeOracle(projectBOracle);
```

### 3. Configure Reward Distribution

Set system-wide reward parameters:

```solidity
// Set decay parameters (70% retention per level)
rewardDistributor.setDecayConfig(IRewardDistributor.DecayType.EXPONENTIAL, 7000, 0.01 ether);

// Set original user reward percentage (80%)
rewardDistributor.setOriginalUserPercentage(8000);
```

### 4. Build Referral Networks

Groups are automatically created when the first user registers. Simply register users with their referrers:

```solidity
bytes32 groupId = keccak256("project-a-users");

// Register first user with root (group auto-created)
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

### 5. Distribute Rewards

Users build referral relationships within groups:

```solidity
bytes32 groupId = keccak256("project-a-users");

// User1 refers User2 in the group
referralGraph.register(user2, user1, groupId);

// User2 refers User3 in the same group
referralGraph.register(user3, user2, groupId);

// Batch register multiple users
address[] memory newUsers = [user4, user5, user6];
referralGraph.batchRegister(newUsers, user3, groupId);
```

### 7. Distribute Rewards

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
rewardDistributor.distributeChainRewards(reward, signature);
```

## Project Integration Examples

### DeFi Protocol Integration

```solidity
contract DeFiProtocol {
    IReferralGraph public referralGraph;
    IRewardDistributor public rewardDistributor;
    address public oracle;

    bytes32 public constant PROTOCOL_GROUP = keccak256("defi-protocol-users");

    function initialize(address _referralGraph, address _rewardDistributor) external {
        referralGraph = IReferralGraph(_referralGraph);
        rewardDistributor = IRewardDistributor(_rewardDistributor);
        // Groups are auto-created on first registration - no setup needed
    }

    function userDeposit(address user, uint256 amount) external {
        // Process deposit logic...
        // User automatically joins group when they register (or are registered)

        // Distribute referral rewards
        _distributeReferralRewards(user, amount, keccak256("deposit"));
    }

    function _distributeReferralRewards(address user, uint256 amount, bytes32 eventType) internal {
        uint256 rewardAmount = amount * 5 / 100; // 5% reward pool

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: user,
            totalAmount: rewardAmount,
            rewardToken: address(protocolToken), // Protocol's reward token
            groupId: PROTOCOL_GROUP,
            eventId: keccak256(abi.encodePacked(user, block.timestamp, eventType)),
            timestamp: block.timestamp,
            nonce: getNextNonce()
        });

        bytes memory signature = signReward(reward, oraclePrivateKey);
        rewardDistributor.distributeChainRewards(reward, signature);
    }
}
```

### Gaming Guild Integration

```solidity
contract GamingGuild {
    IReferralGraph public referralGraph;
    IRewardDistributor public rewardDistributor;

    bytes32 public guildGroup;

    function createGuild(string memory guildName) external {
        guildGroup = keccak256(abi.encodePacked(guildName, block.timestamp));
        // Group auto-created on first registration
    }

    function recruitMember(address newMember, address recruiter) external {
        // Register referral - group auto-created and member automatically added
        referralGraph.register(newMember, recruiter, guildGroup);

        // Reward recruiter for successful recruitment
        _rewardRecruitment(recruiter, newMember);
    }

    function distributeQuestRewards(address[] memory participants, uint256 totalReward) external {
        uint256 perParticipant = totalReward / participants.length;

        for (uint256 i = 0; i < participants.length; i++) {
            IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
                user: participants[i],
                totalAmount: perParticipant,
                rewardToken: address(guildToken),
                groupId: guildGroup, // Guild members share rewards
                eventId: keccak256(abi.encodePacked("quest", block.timestamp, i)),
                timestamp: block.timestamp,
                nonce: getNextNonce()
            });

            bytes memory signature = signReward(reward, guildOraclePrivateKey);
            rewardDistributor.distributeChainRewards(reward, signature);
        }
    }
}
```

### Marketplace Integration

```solidity
contract Marketplace {
    IReferralGraph public referralGraph;
    IRewardDistributor public rewardDistributor;

    // Multiple groups for different product categories
    bytes32 public electronicsGroup = keccak256("electronics-buyers");
    bytes32 public fashionGroup = keccak256("fashion-buyers");

    function initialize() external {
        // Groups auto-created on first registration - no setup needed
    }

    function processPurchase(address buyer, uint256 productId, bytes32 categoryGroup) external {
        // Process purchase...
        // Buyer automatically in group when they register or are registered

        // Distribute referral rewards in category-specific group
        uint256 referralReward = calculateReferralReward(productId);

        IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
            user: buyer,
            totalAmount: referralReward,
            rewardToken: address(marketplaceToken),
            groupId: categoryGroup, // Category-specific referral chain
            eventId: keccak256(abi.encodePacked(buyer, productId, block.timestamp)),
            timestamp: block.timestamp,
            nonce: getNextNonce()
        });

        bytes memory signature = signReward(reward, marketplaceOraclePrivateKey);
        rewardDistributor.distributeChainRewards(reward, signature);
    }
}
```

### DAO Governance Integration

```solidity
contract DAOGovernance {
    IReferralGraph public referralGraph;
    IRewardDistributor public rewardDistributor;

    bytes32 public daoGroup = keccak256("dao-members");

    function initializeGovernance() external {
        // Groups auto-created on first registration - no setup needed
    }

    function onboardMember(address newMember, address sponsor) external {
        // Register referral - group auto-created and member automatically added
        referralGraph.register(newMember, sponsor, daoGroup);

        // Reward sponsor for bringing in new member
        _rewardForOnboarding(sponsor, newMember);
    }

    function distributeProposalRewards(address[] memory voters, uint256 totalReward) external {
        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            uint256 voterReward = calculateVoterReward(voter, totalReward);

            IRewardDistributor.ChainRewardData memory reward = IRewardDistributor.ChainRewardData({
                user: voter,
                totalAmount: voterReward,
                rewardToken: address(governanceToken),
                groupId: daoGroup, // DAO member referral chain
                eventId: keccak256(abi.encodePacked("vote", block.timestamp, voter)),
                timestamp: block.timestamp,
                nonce: getNextNonce()
            });

            bytes memory signature = signReward(reward, daoOraclePrivateKey);
            rewardDistributor.distributeChainRewards(reward, signature);
        }
    }
}
```

## Security

- **Oracle Verification**: Only authorized oracles can sign reward distributions
- **Owner Control**: Only contract owner can authorize/deauthorize oracles
- **Group Isolation**: Referral networks are isolated per group
- **Cryptographic Security**: ECDSA signatures prevent manipulation
- **Dust Prevention**: Minimum thresholds prevent micro-transactions
- **Sequential Distribution**: Mathematical guarantees on spending
- **Multi-Token Support**: Each distribution specifies its reward token
- **Shared Infrastructure**: Single deployment serves multiple projects safely

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

- `setDecayConfig(DecayType type, uint256 factor, uint256 minReward)` - Configure decay
- `setOriginalUserPercentage(uint256 percentage)` - Set user reward percentage
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

### Testing Groups

```solidity
// Groups are auto-created on first registration
bytes32 testGroup = keccak256("test-group");

// Build referral chains - group auto-created when first user registers
referralGraph.register(user1, root, testGroup); // Group created here
referralGraph.register(user2, user1, testGroup);

// Distribute rewards within group
ChainRewardData memory reward = ChainRewardData({
    user: user2,
    totalAmount: 1000e18,
    rewardToken: address(token),
    groupId: testGroup,  // Important: specify group
    eventId: keccak256("test"),
    timestamp: block.timestamp,
    nonce: 1
});
```
