# Simulation Planning Document: Multi-Level Referral Reward System

## Overview

This document outlines the plan for creating a probabilistic simulation of the multi-level referral reward system. The goal is to model human behavior in referral networks and optimize system parameters before rollout. The simulation will help answer questions like:

- How does referral network structure evolve over time?
- What reward parameters maximize user acquisition while maintaining economic sustainability?
- How do different human behavioral assumptions affect system outcomes?
- What combination of settings should we use for initial rollout?

## 1. System Architecture Overview

### Core Components
- **ReferralGraph**: Manages hierarchical referral relationships within groups
- **RewardDistributor**: Handles reward calculation and distribution using configurable decay functions
- **Groups**: Isolated referral networks (each project/app can have its own group)

### Key System Properties
- Groups are implicit (created when first referral is registered)
- Oracle-based authorization system for both registration and reward distribution
- Chain rewards flow upward through referral trees using mathematical decay

## 2. System Parameters (Configurable Inputs)

### A. Reward Distribution Parameters
```typescript
interface RewardConfig {
  decayType: 'LINEAR' | 'EXPONENTIAL' | 'FIXED'
  decayFactor: number        // Basis points (0-10000, e.g., 7000 = 70%)
  minReward: number          // Minimum reward per level (in wei)
  originalUserPercentage: number  // Basis points (e.g., 8000 = 80%)
}
```

**Current Defaults:**
- Type: EXPONENTIAL
- Factor: 7000 (70% retention per level)
- Min Reward: 0.01 ether
- Original User: 8000 (80%)

**Impact on Distribution:**
- **LINEAR**: Each level takes decayFactor% of remaining amount
- **EXPONENTIAL**: Each level takes decayFactor% of the previous level's reward
- **FIXED**: Each level gets a fixed amount until minimum reached

### B. Group Configuration
```typescript
interface GroupConfig {
  groupId: string            // Unique identifier (keccak256 hash)
  allowlistEnabled: boolean  // Whether to restrict referrers
  rootAddress: string        // System root (can be address(0))
}
```

### C. Reward Event Parameters
```typescript
interface RewardEvent {
  totalAmount: number        // Base amount for percentage calculations
  rewardToken: string        // Token contract address
  triggerUser: string        // User who earned the reward
  eventId: string           // Unique event identifier
  timestamp: number
  nonce: number
}
```

## 3. Human Behavioral Factors (Simulation Inputs)

### A. Referral Network Growth
```typescript
interface ReferralBehavior {
  averageReferralsPerUser: number     // Mean referrals per user
  referralStdDev: number              // Standard deviation of referrals
  referralPeriodDays: number          // Time window for making referrals
  referralProbabilityDistribution: 'NORMAL' | 'POISSON' | 'EXPONENTIAL'
}
```

**Example Scenarios:**
- **Conservative**: μ=2.0, σ=1.0, period=30 days
- **Optimistic**: μ=3.5, σ=1.5, period=14 days
- **Aggressive**: μ=5.0, σ=2.0, period=7 days

### B. User Acquisition Timing
```typescript
interface UserAcquisition {
  dailyJoinRate: number               // New users per day
  growthAcceleration: number          // Growth rate multiplier over time
  seasonalFactors: Record<string, number>  // Monthly/weekly patterns
}
```

### C. Network Structure Preferences
```typescript
interface NetworkStructure {
  preferShallowTrees: boolean         // Favor breadth over depth
  clusterFormationProbability: number // Likelihood of friend clusters
  crossGroupReferrals: number         // Inter-group referral rate
}
```

## 4. Reward Amount Distributions

### A. Base Reward Amounts
```typescript
interface RewardDistribution {
  eventTypes: {
    name: string
    probability: number              // Frequency of this event type
    baseAmount: number              // Mean reward amount
    amountStdDev: number            // Variation in reward amounts
    distribution: 'NORMAL' | 'LOGNORMAL' | 'UNIFORM'
  }[]
}
```

**Example Event Types:**
- **Purchase**: 60% probability, μ=$50, σ=$20
- **Milestone**: 30% probability, μ=$100, σ=$50
- **Achievement**: 10% probability, μ=$200, σ=$100

### B. Token Economic Parameters
```typescript
interface TokenEconomics {
  tokenPrice: number                 // USD value per token
  rewardFrequency: number            // Events per user per day
  vestingSchedule: VestingSchedule   // Reward release timing
}
```

## 5. Simulation Output Metrics

### A. Network Structure Metrics
- **Tree Depth Distribution**: Average/maximum referral chain lengths
- **Branching Factor**: Average referrals per user
- **Network Density**: Ratio of actual to possible connections
- **Group Isolation**: Cross-group vs. within-group referrals

### B. Reward Distribution Metrics
- **Reward Velocity**: How quickly rewards propagate through network
- **Inequality Metrics**: Gini coefficient of reward distribution
- **Dust Accumulation**: Percentage of rewards going to oracle
- **Reward Decay Analysis**: How rewards diminish with distance

### C. User Behavior Metrics
- **Engagement Rates**: Percentage of users actively referring
- **Conversion Rates**: Referral acceptance probability
- **Retention Metrics**: User activity over time
- **Viral Coefficient**: Average secondary referrals per user

## 6. Simulation Implementation Plan

### Phase 1: Core Simulation Engine
1. **Agent-Based Model**: Individual user agents with behavioral profiles
2. **Network Generation**: Referral graph construction algorithms
3. **Reward Propagation**: Chain reward calculation and distribution
4. **Temporal Dynamics**: Time-based event simulation

### Phase 2: Parameter Sensitivity Analysis
1. **Single Variable Tests**: Impact of changing one parameter at a time
2. **Multi-Variable Optimization**: Finding optimal parameter combinations
3. **Scenario Comparison**: Compare different behavioral assumptions
4. **Robustness Testing**: System behavior under extreme conditions

### Phase 3: Validation Framework
1. **Historical Data Integration**: Compare against existing referral programs
2. **A/B Testing Simulation**: Model different reward structures
3. **Economic Analysis**: ROI calculations for different configurations
4. **Risk Assessment**: Failure mode analysis

## 7. Data Collection and Validation

### A. Real-World Comparison Points
- **Existing Programs**: Study successful referral programs (Uber, Airbnb, etc.)
- **Industry Benchmarks**: Standard metrics for referral program performance
- **User Surveys**: Willingness to refer, expected reward preferences

### B. Model Calibration
- **Parameter Fitting**: Adjust simulation parameters to match real data
- **Cross-Validation**: Test model predictions against held-out data
- **Sensitivity Analysis**: Identify which parameters matter most

## 8. Implementation Roadmap

### Week 1-2: Foundation
- [ ] Create simulation framework skeleton
- [ ] Implement basic referral network generation
- [ ] Build reward distribution calculator

### Week 3-4: Core Features
- [ ] Add temporal dynamics (time-based simulation)
- [ ] Implement user behavior models
- [ ] Create parameter configuration system

### Week 5-6: Analysis Tools
- [ ] Build visualization dashboard
- [ ] Add statistical analysis functions
- [ ] Create parameter sweep utilities

### Week 7-8: Validation
- [ ] Integrate real-world data for calibration
- [ ] Perform sensitivity analysis
- [ ] Generate rollout recommendations

## 9. Key Research Questions

### Primary Optimization Goals
1. **Viral Growth**: Maximize sustainable user acquisition rate
2. **Economic Sustainability**: Minimize reward costs while maintaining incentives
3. **User Experience**: Ensure fair and motivating reward distribution
4. **System Robustness**: Handle various behavioral scenarios gracefully

### Critical Parameters to Test
1. **Decay Function Selection**: Linear vs. Exponential vs. Fixed decay
2. **Reward Pool Sizing**: What percentage of value should go to referrals?
3. **Timing Dynamics**: How referral timing affects network structure
4. **Behavioral Assumptions**: Sensitivity to referral willingness assumptions

## 10. Success Criteria

### Simulation Validation
- [ ] Model predictions match historical referral program data within 20%
- [ ] Parameter sensitivity analysis identifies key leverage points
- [ ] Monte Carlo simulations show robust performance across scenarios

### Business Impact
- [ ] Clear recommendations for initial parameter settings
- [ ] Confidence intervals for expected user growth rates
- [ ] Risk assessment for different rollout strategies

## 11. Next Steps

1. **Immediate**: Choose simulation framework (Python with NetworkX, JavaScript, etc.)
2. **Week 1**: Implement basic referral network generation
3. **Week 2**: Add reward distribution mechanics
4. **Week 3**: Create parameter sweep functionality
5. **Week 4**: Build visualization and analysis tools

## 12. Open Questions

1. **Primary Goal**: Are you optimizing for maximum viral growth, sustainable user acquisition, or reward program profitability?

2. **Time Horizon**: What timeframe are you modeling (weeks, months, years)?

3. **Scale**: What's your expected user base size (1K, 10K, 100K+ users)?

4. **Data Sources**: Do you have existing referral program data to calibrate against?

5. **Key Metrics**: Which simulation outputs matter most (user growth, reward costs, network structure)?

6. **Constraints**: Are there budget limits, token supply constraints, or other boundaries?

---

*This document will be updated as the simulation develops and we gather more insights about the system's behavior.*