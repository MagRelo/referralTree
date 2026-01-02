#!/usr/bin/env python3
"""
Economic Analysis Script

This script analyzes the economic aspects of the referral simulation,
including reward distribution, costs, and incentives.
"""

import sys
from referral_model import ReferralModel, DecayType
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

def analyze_reward_distribution(scenario_name='moderate', steps=50):
    """Analyze reward distribution and economic metrics"""

    # Get scenario parameters
    scenarios = {
        'conservative': {
            'n_initial_users': 10,
            'average_referrals': 1.5,
            'referral_probability': 0.03,
            'churn_probability': 0.007,
            'max_users': 500,
            'max_referrals_per_step': 2,
            'min_referral_delay': 3,
            'reward_decay_type': 'exponential',
            'reward_decay_factor': 8000,
            'min_reward': 0.01,
            'original_user_percentage': 8500,
        },
        'moderate': {
            'n_initial_users': 10,
            'average_referrals': 2.5,
            'referral_probability': 0.15,
            'churn_probability': 0.003,
            'max_users': 1000,
            'max_referrals_per_step': 3,
            'min_referral_delay': 5,
            'reward_decay_type': 'exponential',
            'reward_decay_factor': 7000,
            'min_reward': 0.05,
            'original_user_percentage': 8000,
        },
        'aggressive': {
            'n_initial_users': 10,
            'average_referrals': 3.5,
            'referral_probability': 0.25,
            'churn_probability': 0.001,
            'max_users': 2000,
            'max_referrals_per_step': 5,
            'min_referral_delay': 3,
            'reward_decay_type': 'exponential',
            'reward_decay_factor': 6000,
            'min_reward': 0.10,
            'original_user_percentage': 7500,
        }
    }

    params = scenarios[scenario_name]
    model = ReferralModel(**params)

    print(f"🧮 Analyzing {scenario_name.upper()} scenario economics")
    print(f"📋 Parameters: decay_factor={params['reward_decay_factor']/100}%, min_reward=${params['min_reward']:.2f}")

    # Run simulation
    reward_events_over_time = []
    total_rewards_over_time = []

    for step in range(steps):
        model.step()
        reward_events_over_time.append(len(model.reward_events))
        total_rewards_over_time.append(model.total_rewards_distributed)

    # Analyze final reward distribution
    all_rewards = [agent.total_rewards for agent in model.agents]
    user_levels = [agent.referral_level for agent in model.agents]

    # Calculate economic metrics
    total_reward_cost = model.total_rewards_distributed
    total_users = len(model.agents)
    avg_reward_per_user = total_reward_cost / total_users if total_users > 0 else 0

    # Reward distribution by level
    level_rewards = {}
    level_counts = {}
    for agent in model.agents:
        level = agent.referral_level
        if level not in level_rewards:
            level_rewards[level] = 0
            level_counts[level] = 0
        level_rewards[level] += agent.total_rewards
        level_counts[level] += 1

    print(f"\n💰 Economic Summary:")
    print(f"   Total Reward Events: {len(model.reward_events)}")
    print(f"   Total Rewards Distributed: ${total_reward_cost:.2f}")
    print(f"   Average Reward per User: ${avg_reward_per_user:.2f}")
    print(f"   Reward Cost per Acquisition: ${total_reward_cost/total_users:.2f}")

    print(f"\n🏆 Reward Distribution by Level:")
    for level in sorted(level_rewards.keys()):
        avg_level_reward = level_rewards[level] / level_counts[level] if level_counts[level] > 0 else 0
        print(f"   Level {level}: {level_counts[level]} users, avg ${avg_level_reward:.2f} each")

    # Calculate Gini coefficient (inequality measure)
    if all_rewards:
        sorted_rewards = sorted(all_rewards)
        n = len(sorted_rewards)
        cumsum = np.cumsum(sorted_rewards)
        gini = (n + 1 - 2 * np.sum(cumsum) / cumsum[-1]) / n
        print(f"\n📊 Inequality Metrics:")
        print(f"   Gini Coefficient: {gini:.3f} (0=perfect equality, 1=perfect inequality)")
        print(f"   Reward Range: ${min(all_rewards):.2f} - ${max(all_rewards):.2f}")

    # Create detailed visualization
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))

    # Plot 1: Reward events over time
    ax1.plot(reward_events_over_time, linewidth=2, color='blue')
    ax1.set_xlabel('Time Steps')
    ax1.set_ylabel('Cumulative Reward Events')
    ax1.set_title('Reward Events Over Time')
    ax1.grid(True, alpha=0.3)

    # Plot 2: Total rewards distributed over time
    ax2.plot(total_rewards_over_time, linewidth=2, color='green')
    ax2.set_xlabel('Time Steps')
    ax2.set_ylabel('Total Rewards Distributed ($)')
    ax2.set_title('Reward Distribution Over Time')
    ax2.grid(True, alpha=0.3)

    # Plot 3: Reward distribution by user level
    levels = sorted(level_rewards.keys())
    avg_rewards_by_level = [level_rewards[l] / level_counts[l] for l in levels]
    ax3.bar(levels, avg_rewards_by_level, color='orange', alpha=0.7)
    ax3.set_xlabel('Referral Level')
    ax3.set_ylabel('Average Reward per User ($)')
    ax3.set_title('Rewards by Referral Level')
    ax3.grid(True, alpha=0.3)

    # Plot 4: Individual user rewards (top 50)
    top_rewards = sorted(all_rewards, reverse=True)[:50]
    ax4.bar(range(len(top_rewards)), top_rewards, color='red', alpha=0.7)
    ax4.set_xlabel('User Rank (by rewards)')
    ax4.set_ylabel('Total Rewards ($)')
    ax4.set_title('Top 50 Users by Total Rewards')
    ax4.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(f'economic_analysis_{scenario_name}.png', dpi=150, bbox_inches='tight')
    print(f"\n📈 Economic analysis saved to: economic_analysis_{scenario_name}.png")

    return {
        'total_reward_cost': total_reward_cost,
        'avg_reward_per_user': avg_reward_per_user,
        'reward_events': len(model.reward_events),
        'gini_coefficient': gini if 'gini' in locals() else 0,
        'level_rewards': level_rewards,
        'level_counts': level_counts
    }

def compare_decay_types():
    """Compare different reward decay types"""
    print("🔬 Comparing Reward Decay Types")

    decay_types = ['exponential', 'linear', 'fixed']
    results = {}

    base_params = {
        'n_initial_users': 10,
        'average_referrals': 2.0,
        'referral_probability': 0.1,
        'churn_probability': 0.005,
        'max_users': 200,
        'max_referrals_per_step': 3,
        'min_referral_delay': 5,
        'reward_decay_factor': 7000,
        'min_reward': 0.05,
        'original_user_percentage': 8000,
    }

    for decay_type in decay_types:
        params = base_params.copy()
        params['reward_decay_type'] = decay_type

        model = ReferralModel(**params)
        for _ in range(30):
            model.step()

        total_rewards = model.total_rewards_distributed
        user_count = len(model.agents)

        results[decay_type] = {
            'total_rewards': total_rewards,
            'user_count': user_count,
            'cost_per_user': total_rewards / user_count if user_count > 0 else 0
        }

        print(f"   {decay_type.title()}: ${total_rewards:.2f} total, ${total_rewards/user_count:.2f}/user")

    return results

if __name__ == "__main__":
    scenario = sys.argv[1] if len(sys.argv) > 1 else 'moderate'

    if scenario == 'compare_decay':
        compare_decay_types()
    else:
        analyze_reward_distribution(scenario)