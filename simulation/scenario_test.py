#!/usr/bin/env python3
"""
Scenario Testing Script

This script runs the referral simulation using the behavioral assumptions
defined in assumptions/user_behavior_assumptions.md

Usage:
    python scenario_test.py [scenario_name]

Scenarios:
    - conservative: Low engagement, steady growth
    - moderate: Balanced growth (default)
    - aggressive: High growth, viral potential
"""

import sys
from referral_model import ReferralModel, run_simulation
import matplotlib.pyplot as plt
import pandas as pd

# Scenario definitions based on user behavior assumptions
SCENARIOS = {
    'conservative': {
        'description': 'Low engagement, steady growth (7-20% monthly churn)',
        'params': {
            'n_initial_users': 10,
            'average_referrals': 1.5,
            'referral_probability': 0.03,  # ~10% daily over 30 days
            'churn_probability': 0.007,    # ~20% monthly churn
            'max_users': 500,
            'max_referrals_per_step': 2,
            'min_referral_delay': 3,
            'min_reward': 0.01,
            'original_user_percentage': 8500,  # 85% (more generous)
        }
    },

    'moderate': {
        'description': 'Balanced growth for crypto-social apps',
        'params': {
            'n_initial_users': 10,
            'average_referrals': 2.5,
            'referral_probability': 0.15,   # 15% daily referral probability
            'churn_probability': 0.003,     # ~10% monthly churn
            'max_users': 1000,
            'max_referrals_per_step': 3,
            'min_referral_delay': 5,
            'min_reward': 0.05,
            'original_user_percentage': 8000,  # 80%
        }
    },

    'aggressive': {
        'description': 'High growth, viral potential',
        'params': {
            'n_initial_users': 10,
            'average_referrals': 3.5,
            'referral_probability': 0.25,   # 25% daily referral probability
            'churn_probability': 0.001,     # ~3% monthly churn
            'max_users': 2000,
            'max_referrals_per_step': 5,
            'min_referral_delay': 3,
            'min_reward': 0.10,
            'original_user_percentage': 7500,  # 75% (less generous to encourage referrals)
        }
    }
}

def run_scenario(scenario_name='moderate', steps=50, save_plot=True):
    """Run a specific scenario and return results"""

    if scenario_name not in SCENARIOS:
        print(f"Unknown scenario: {scenario_name}")
        print(f"Available scenarios: {list(SCENARIOS.keys())}")
        return None

    scenario = SCENARIOS[scenario_name]
    print(f"\n🚀 Running {scenario_name.upper()} scenario")
    print(f"📋 {scenario['description']}")
    print(f"⚙️  Parameters: {scenario['params']}")

    # Run simulation
    models = run_simulation(scenario['params'], max_steps=steps, n_runs=3)

    # Analyze results
    results = []
    for i, model in enumerate(models):
        df = model.datacollector.get_model_vars_dataframe()

        result = {
            'run': i + 1,
            'final_users': len(model.agents),
            'active_users': len([a for a in model.agents if a.active]),
            'total_referrals': sum(a.referral_count for a in model.agents),
            'avg_referrals_per_user': sum(a.referral_count for a in model.agents) / len(model.agents),
            'user_growth': df['Total Users'].tolist(),
            'active_users_over_time': df['Active Users'].tolist(),
        }
        results.append(result)

    # Calculate averages across runs
    avg_results = {
        'scenario': scenario_name,
        'description': scenario['description'],
        'parameters': scenario['params'],
        'avg_final_users': sum(r['final_users'] for r in results) / len(results),
        'avg_active_users': sum(r['active_users'] for r in results) / len(results),
        'avg_total_referrals': sum(r['total_referrals'] for r in results) / len(results),
        'avg_referrals_per_user': sum(r['avg_referrals_per_user'] for r in results) / len(results),
        'user_growth_curve': [sum(r['user_growth'][i] for r in results) / len(results) for i in range(steps)],
        'active_users_curve': [sum(r['active_users_over_time'][i] for r in results) / len(results) for i in range(steps)],
    }

    # Print summary
    print(f"\n📊 Results (averaged over {len(results)} runs):")
    print(f"   👥 Final Users: {avg_results['avg_final_users']:.1f}")
    print(f"   ✅ Active Users: {avg_results['avg_active_users']:.1f}")
    print(f"   🔗 Total Referrals: {avg_results['avg_total_referrals']:.1f}")
    print(f"   📈 Avg Referrals/User: {avg_results['avg_referrals_per_user']:.2f}")
    print(f"   📊 Viral Coefficient: {(avg_results['avg_final_users'] / scenario['params']['n_initial_users']) ** (1/steps):.3f}")

    # Create plot if requested
    if save_plot:
        plt.figure(figsize=(12, 8))

        plt.subplot(2, 2, 1)
        plt.plot(avg_results['user_growth_curve'], label='Total Users', linewidth=2)
        plt.plot(avg_results['active_users_curve'], label='Active Users', linewidth=2, linestyle='--')
        plt.xlabel('Time Steps')
        plt.ylabel('Number of Users')
        plt.title(f'{scenario_name.title()} Scenario - User Growth')
        plt.legend()
        plt.grid(True, alpha=0.3)

        plt.subplot(2, 2, 2)
        user_growth_rate = [(avg_results['user_growth_curve'][i+1] - avg_results['user_growth_curve'][i])
                           / avg_results['user_growth_curve'][i] * 100
                           for i in range(len(avg_results['user_growth_curve'])-1)]
        plt.plot(user_growth_rate, linewidth=2, color='orange')
        plt.xlabel('Time Steps')
        plt.ylabel('Growth Rate (%)')
        plt.title('User Growth Rate Over Time')
        plt.grid(True, alpha=0.3)

        plt.subplot(2, 2, 3)
        plt.bar(['Conservative', 'Moderate', 'Aggressive'],
                [SCENARIOS['conservative']['params']['referral_probability'] * 100,
                 SCENARIOS['moderate']['params']['referral_probability'] * 100,
                 SCENARIOS['aggressive']['params']['referral_probability'] * 100],
                color=['lightblue', 'orange', 'red'])
        plt.ylabel('Referral Probability (%)')
        plt.title('Scenario Comparison - Referral Rates')
        plt.ylim(0, 30)

        plt.subplot(2, 2, 4)
        final_users = [SCENARIOS[s]['params']['n_initial_users'] for s in ['conservative', 'moderate', 'aggressive']]
        # This would need actual results - for now just show structure
        plt.text(0.5, 0.5, 'Final user counts\nvary by scenario\n(see console output)',
                ha='center', va='center', transform=plt.gca().transAxes)
        plt.title('Scenario Outcomes')

        plt.tight_layout()
        plt.savefig(f'scenario_{scenario_name}_results.png', dpi=150, bbox_inches='tight')
        print(f"\n📈 Results saved to: scenario_{scenario_name}_results.png")

    return avg_results

def compare_scenarios(steps=50):
    """Run all scenarios and compare results"""
    print("🔬 Comparing All Scenarios")

    results = {}
    for scenario_name in SCENARIOS.keys():
        results[scenario_name] = run_scenario(scenario_name, steps=steps, save_plot=False)

    # Summary comparison
    print(f"\n{'='*60}")
    print("📊 SCENARIO COMPARISON SUMMARY")
    print(f"{'='*60}")

    print("<8")
    print(f"{'─'*60}")

    for scenario_name, result in results.items():
        viral_coeff = (result['avg_final_users'] / SCENARIOS[scenario_name]['params']['n_initial_users']) ** (1/steps)
        print("<8")

    print(f"\n💡 Key Insights:")
    print("   • Conservative: Steady, sustainable growth")
    print("   • Moderate: Balanced approach for crypto-social apps")
    print("   • Aggressive: High-risk, high-reward viral potential")

if __name__ == "__main__":
    scenario = sys.argv[1] if len(sys.argv) > 1 else 'moderate'

    if scenario == 'compare':
        compare_scenarios()
    elif scenario in SCENARIOS:
        run_scenario(scenario)
    else:
        print(f"Usage: python {sys.argv[0]} [scenario_name]")
        print(f"Available scenarios: {list(SCENARIOS.keys()) + ['compare']}")
        print("\nExample: python scenario_test.py moderate")