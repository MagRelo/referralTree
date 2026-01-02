# Referral System Simulation

This directory contains a Mesa-based agent simulation of a multi-level referral reward system.

## Status: ✅ Working Prototype

The simulation is successfully implemented and tested. It can model referral network growth, parameter sensitivity analysis, and Monte Carlo simulations.

## Current State & Context (For Resuming Development)

### ✅ What's Implemented
- **Mesa 2.x Agent-Based Model**: `ReferralModel` class with `UserAgent` agents
- **Network Modeling**: NetworkX integration for referral tree visualization
- **Parameter System**: Configurable referral behavior, churn, and reward parameters
- **Data Collection**: Tracks users, referrals, network metrics via Mesa's DataCollector
- **Basic Testing**: Parameter sweeps and Monte Carlo simulation framework
- **Virtual Environment**: Complete Python setup with all dependencies

### 🔧 Technical Implementation Details
- **Mesa Version**: 2.x (not 1.x) - uses AgentSet instead of scheduler
- **Agent Creation**: `UserAgent(model, referrer_id=None)` - Mesa auto-assigns unique_id
- **Model Attributes**: Custom parameters stored directly on model instance
- **Network Storage**: `model.network` as NetworkX DiGraph
- **Data Access**: Use `model.agents` instead of `model.schedule.agents`

### ⚠️ Known Issues & TODOs
1. **Visualization**: Solara web interface has API compatibility issues - needs debugging
2. **Reward Distribution**: Chain reward calculation logic not yet implemented
3. **Parameter Validation**: No bounds checking on model parameters
4. **Performance**: No optimization for large-scale simulations (>1000 agents)
5. **Data Persistence**: No saving/loading of simulation results

### 🎯 Next Priority Steps
1. **Fix Visualization**: Debug Solara integration or switch to simpler plotting
2. **Implement Reward Logic**: Add chain reward distribution matching contract logic
3. **Parameter Calibration**: Link simulation parameters to actual contract parameters
4. **Statistical Analysis**: Add proper Monte Carlo analysis with confidence intervals
5. **Validation Framework**: Compare simulation results against real referral data

### 🔗 Integration Points
- **Contract Parameters**: Simulation should use same parameter names/types as `RewardDistributor.sol`
- **Data Sources**: Need real referral program data for calibration
- **Output Format**: Results should inform contract parameter decisions
- **Economic Modeling**: Token costs, user acquisition value, viral coefficients

### 📊 Test Results (Current Baseline)
```
Basic simulation (20 steps, 5 initial users):
- Final users: 13
- Active users: 10
- Network edges: 8

Parameter sweep (50 steps):
- Low engagement (0.05 prob, 1.5 avg referrals): 46 final users
- Medium engagement (0.15 prob, 2.5 avg): 283 final users
- High engagement (0.25 prob, 3.5 avg): 1000 final users (capped)
```

### 🛠️ Quick Resume Commands
```bash
cd simulation
source venv/bin/activate
python test_simulation.py  # Verify current functionality
python -m jupyter notebook  # For analysis notebooks
```

## Overview

The simulation models users in a referral network where:
- Users can refer other users to join the platform
- Referrers earn rewards from their referral network
- Rewards decay with distance in the referral tree
- Users can become inactive (churn)

## Installation

The simulation uses a Python virtual environment. All dependencies are already installed.

To activate the environment:
```bash
cd simulation
source venv/bin/activate  # On macOS/Linux
# or
venv\Scripts\activate     # On Windows
```

## Files

- `referral_model.py` - Core simulation model and agent classes
- `visualization.py` - Web-based visualization using Mesa's Solara interface
- `test_simulation.py` - Test script to verify functionality
- `requirements.txt` - Python dependencies

## Test Results

The simulation successfully runs and shows expected behavior:

```
Testing basic simulation...
Final user count: 13
Active users: 10
Network nodes: 13
Network edges: 8

Testing parameter sweep...
Params: {'referral_probability': 0.05, 'average_referrals': 1.5} -> Final users: 46
Params: {'referral_probability': 0.15, 'average_referrals': 2.5} -> Final users: 283
Params: {'referral_probability': 0.25, 'average_referrals': 3.5} -> Final users: 1000
```

This demonstrates:
- ✅ Agent-based modeling with user behavior
- ✅ Network growth simulation
- ✅ Parameter sensitivity analysis
- ✅ Data collection and visualization

## Running the Simulation

### Basic Test
```bash
cd simulation
source venv/bin/activate
python test_simulation.py
```

This will run a basic simulation and parameter sweep, printing results to the console.

### Web Visualization
```bash
cd simulation
source venv/bin/activate
python visualization.py
```

This launches a web interface where you can adjust parameters and watch the simulation in real-time (requires Solara).

### Jupyter Notebook Analysis
```bash
cd simulation
source venv/bin/activate
jupyter notebook
```

Create a new notebook and import the simulation:
```python
from referral_model import ReferralModel, run_simulation
import matplotlib.pyplot as plt
import pandas as pd

# Run parameter sweep
params = {"referral_probability": 0.1, "average_referrals": 2.0}
models = run_simulation(params, max_steps=50, n_runs=3)

# Analyze results
for i, model in enumerate(models):
    df = model.datacollector.get_model_vars_dataframe()
    plt.plot(df['Total Users'], label=f'Run {i+1}')

plt.legend()
plt.show()
```

## Model Parameters

### User Behavior
- `n_initial_users`: Starting number of users (default: 10)
- `average_referrals`: Mean referrals per user (Poisson distribution, default: 2.0)
- `referral_probability`: Probability a user makes referrals each step (default: 0.1)
- `churn_probability`: Probability a user becomes inactive each step (default: 0.01)
- `max_users`: Maximum users in simulation (default: 1000)
- `max_referrals_per_step`: Max referrals per time step (default: 3)
- `min_referral_delay`: Steps before a user can refer others (default: 5)

### Reward System
- `reward_decay_type`: 'exponential', 'linear', or 'fixed' (default: 'exponential')
- `reward_decay_factor`: Decay rate in basis points (default: 7000 = 70%)
- `min_reward`: Minimum reward per level (default: 0.01)
- `original_user_percentage`: Percentage for triggering user (default: 8000 = 80%)

## Output Metrics

The simulation tracks:
- **Total Users**: All users ever created
- **Active Users**: Currently active users
- **Total Referrals**: Cumulative referral count
- **Average Referral Count**: Mean referrals per user
- **Network Density**: Ratio of actual to possible connections
- **Average Path Length**: Average shortest path between users

## Example Usage

```python
from referral_model import ReferralModel

# Create model with custom parameters
model = ReferralModel(
    n_initial_users=20,
    average_referrals=3.0,
    referral_probability=0.2,
    churn_probability=0.005,
    reward_decay_type='exponential',
    reward_decay_factor=8000  # 80% retention
)

# Run simulation
for step in range(100):
    model.step()

# Get results
df = model.datacollector.get_model_vars_dataframe()
print(df.tail())
```

## Parameter Sensitivity Analysis

Use the `run_simulation` function for batch analysis:

```python
from referral_model import run_simulation

# Test different referral rates
params_list = [
    {"referral_probability": 0.05, "average_referrals": 1.5},
    {"referral_probability": 0.15, "average_referrals": 2.5},
    {"referral_probability": 0.25, "average_referrals": 3.5},
]

results = []
for params in params_list:
    models = run_simulation(params, max_steps=50, n_runs=5)
    # Analyze average outcomes across runs
    avg_final_users = sum(len(m.schedule.agents) for m in models) / len(models)
    results.append({"params": params, "avg_final_users": avg_final_users})
```

## Next Steps

1. **Validate the Model**: Compare simulation outputs against real referral program data
2. **Sensitivity Analysis**: Test how changes in parameters affect outcomes
3. **Behavioral Calibration**: Adjust user behavior parameters to match observed patterns
4. **Reward Optimization**: Find optimal reward distribution parameters
5. **Monte Carlo Analysis**: Run thousands of simulations to understand uncertainty

## Integration with Main Project

The simulation parameters should eventually be linked to the actual smart contract parameters defined in the main project's contracts. Key mappings:

- Simulation `reward_decay_type/factor` → Contract `decayType/decayFactor`
- Simulation `min_reward` → Contract `minReward`
- Simulation `original_user_percentage` → Contract `originalUserPercentage`

This allows you to test contract parameter changes in simulation before deployment.