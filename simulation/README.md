# Referral Reward System Economic Simulator

A Mesa-based agent simulation that models the **economic incentives** and **viral growth dynamics** of multi-level referral reward systems. Perfect for crypto-social apps, DeFi protocols, and any platform using referral incentives.

## 🎯 What This Models

**Economic Behavior**: Users earn and distribute rewards through referral chains
- **Purchase Events**: Random user activities that trigger reward distributions
- **Chain Rewards**: Rewards flow upward through referral trees using exponential/linear decay
- **Incentive Effects**: Economic motivations influence referral behavior
- **Cost Analysis**: Calculate total reward costs vs. user acquisition value

**Network Dynamics**: Viral growth patterns with realistic user behavior
- **Referral Networks**: Multi-level trees with configurable depth limits
- **Churn Modeling**: Users become inactive over time
- **Engagement Patterns**: Time-based delays and probability distributions

## 🎯 Key Features

- **Agent-Based Modeling**: Individual users with realistic behavior patterns
- **Economic Incentives**: Reward distribution through referral chains
- **Parameter Sensitivity**: Test different referral rates, churn, and reward structures
- **Monte Carlo Analysis**: Statistical validation of growth scenarios
- **Network Visualization**: Tree structures and viral coefficient analysis

## 📊 Parameters & Assumptions Assessment

Use this table to evaluate if the simulation matches your use case. All parameters are customizable.

| Category | Parameter | Current Default | Rationale | Your Use Case? | Customization |
|----------|-----------|-----------------|-----------|----------------|---------------|
| **User Acquisition** | Initial Users | 10 | Starting network size | Scale to your current user base | `n_initial_users` |
| | Daily Join Rate | Poisson(λ=2.0) | Natural referral clustering | Adjust based on your growth rate | `average_referrals` |
| | Referral Probability | 15% daily | 15% of engaged users refer daily | Match your observed referral rate | `referral_probability` |
| | Churn Rate | 1% daily | ~70% retention over 3 months | Use your actual churn data | `churn_probability` |
| **User Behavior** | Referral Delay | 5 days | Time to understand/learn product | Adjust for your onboarding time | `min_referral_delay` |
| **Economic Events** | Purchase Probability | 2% daily | 2% of users trigger rewards daily | Match your transaction rate | `event_probability` in code |
| | Purchase Amount | Log-normal μ=$7.39 | Realistic transaction distribution | Use your average order value | Distribution parameters |
| | Reward Distribution | Geometric decay (0.6 ratio) | Fixed geometric decay matching contract | Rewards decrease by 40% per level | Fixed in contract logic |
| | Original User Share | 80% | Trigger user gets 80% of rewards | Adjust based on economics | `original_user_percentage` |
| | Minimum Reward | $0.05 | Smallest reward payment | Set transaction fee minimum | `min_reward` |
| **Network Structure** | Max Users | 1,000 | Simulation capacity limit | Scale based on expected growth | `max_users` |
| | Max Depth | 50 levels | Prevent infinite chains | Set based on your reward limits | Chain traversal limit |

## 🎯 Use Case Assessment

**✅ Good Fit For:**
- Crypto/Social apps with referral incentives
- DeFi protocols with reward distributions
- Any platform with multi-level referral mechanics
- Projects optimizing reward costs vs. user growth

**❓ Questions to Ask:**
- Is your referral rate >5% monthly? (Lower rates may need conservative scenarios)
- Do users make purchases/transactions regularly? (Economic events drive rewards)
- Are rewards in fiat/crypto tokens? (Simulation assumes dollar values)
- Is network depth >3 levels economically viable? (Current decay creates shallow trees)

**🔧 Customization Path:**
1. **Behavioral Match**: Adjust referral/churn probabilities to match your data
2. **Economic Calibration**: Set reward amounts and decay to match your incentives
3. **Scale Adjustment**: Change user limits and timeframes for your scope
4. **Network Structure**: Add clustering or constraints specific to your platform

## 🚀 Quick Start

**Prerequisites**: Python virtual environment already set up with dependencies.

```bash
cd simulation
source venv/bin/activate  # macOS/Linux
# venv\Scripts\activate   # Windows

# Test the simulation
python test_simulation.py

# Run economic analysis
python economic_analysis.py moderate

# Compare scenarios
python scenario_test.py compare
```

## 📈 Key Results Summary

| Scenario | Viral Coefficient | Users | Reward Cost/User | Best For |
|----------|------------------|-------|------------------|----------|
| **Conservative** | 1.031 | ~50 | $2.50 | Established communities |
| **Moderate** | 1.096 | ~1,000 | $5.50 | New crypto-social apps |
| **Aggressive** | 1.112 | ~2,000 | $8.50 | High-incentive campaigns |

**Economic Insights**:
- Geometric decay (0.6 ratio) creates high inequality (Gini: 0.81)
- Level 0 users earn 3-4x more than Level 1 users
- 80% of rewards go to original purchasers
- Viral growth requires 10-15% daily referral probability

## 📁 Files Overview

- `referral_model.py` - Core agent-based model with reward distribution
- `scenario_test.py` - Pre-configured scenarios (conservative/moderate/aggressive)
- `economic_analysis.py` - Deep economic analysis and reward metrics
- `test_simulation.py` - Basic functionality tests
- `assumptions/user_behavior_assumptions.md` - Detailed behavioral assumptions
- `requirements.txt` - Python dependencies
- `assumptions/user_behavior_assumptions.md` - Detailed behavioral assumptions

## 🔧 Customization Guide

**To Match Your Use Case:**

1. **Update Behavioral Parameters**: Modify referral/churn rates in scenario definitions
2. **Adjust Economic Parameters**: Change reward amounts and decay in model initialization
3. **Customize Events**: Modify purchase probability and amounts in `_generate_reward_events()`
4. **Add Network Effects**: Implement clustering or geographic constraints in agent behavior

**Example Customization**:
```python
# For a high-churn mobile app
model = ReferralModel(
    referral_probability=0.08,    # Lower engagement
    churn_probability=0.015,      # Higher churn
    original_user_percentage=7500  # More rewards to purchasers (less to chain)
)
```

---

**Ready to optimize your referral economics?** Start with `python scenario_test.py moderate` and customize from there! 🎯