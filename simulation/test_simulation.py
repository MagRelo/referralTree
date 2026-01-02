"""
Test script for the Referral System simulation
"""

from referral_model import ReferralModel, run_simulation
import matplotlib.pyplot as plt
import pandas as pd

def test_basic_simulation():
    """Test basic simulation functionality"""
    print("Testing basic simulation...")

    # Create model with default parameters
    model = ReferralModel(
        n_initial_users=5,
        average_referrals=2.0,
        referral_probability=0.1,
        max_users=50
    )

    # Run for 20 steps
    for _ in range(20):
        model.step()

    print(f"Final user count: {len(model.agents)}")
    print(f"Active users: {len([a for a in model.agents if a.active])}")
    print(f"Network nodes: {len(model.network.nodes())}")
    print(f"Network edges: {len(model.network.edges())}")

    return model

def test_parameter_sweep():
    """Test parameter sweep functionality"""
    print("\nTesting parameter sweep...")

    # Test different referral probabilities
    params_list = [
        {"referral_probability": 0.05, "average_referrals": 1.5},
        {"referral_probability": 0.15, "average_referrals": 2.5},
        {"referral_probability": 0.25, "average_referrals": 3.5},
    ]

    results = []
    for params in params_list:
        models = run_simulation(params, max_steps=30, n_runs=1)
        model = models[0]

        result = {
            "referral_probability": params["referral_probability"],
            "average_referrals": params["average_referrals"],
            "final_users": len(model.agents),
            "active_users": len([a for a in model.agents if a.active]),
            "total_referrals": sum(a.referral_count for a in model.agents)
        }
        results.append(result)
        print(f"Params: {params} -> Final users: {result['final_users']}")

    return results

if __name__ == "__main__":
    # Run basic test
    model = test_basic_simulation()

    # Run parameter sweep
    results = test_parameter_sweep()

    # Plot results if matplotlib is available
    try:
        df = pd.DataFrame(results)
        plt.figure(figsize=(10, 6))
        plt.scatter(df['referral_probability'], df['final_users'])
        plt.xlabel('Referral Probability')
        plt.ylabel('Final User Count')
        plt.title('Referral Probability vs Final User Count')
        plt.savefig('simulation_results.png')
        print("\nResults saved to simulation_results.png")
    except ImportError:
        print("Matplotlib not available for plotting")

    print("\nSimulation tests completed!")