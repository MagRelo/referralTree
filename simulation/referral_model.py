"""
Referral System Agent-Based Model

This Mesa-based simulation models a multi-level referral reward system
where users can refer others and earn rewards from their referral network.
"""

import mesa
import networkx as nx
import numpy as np
from mesa.datacollection import DataCollector


class UserAgent(mesa.Agent):
    """
    An agent representing a user in the referral system.

    Attributes:
        unique_id: Unique identifier
        referral_count: Number of users this agent has referred
        total_rewards: Total rewards earned
        referral_level: How deep in the referral tree (0 = original user)
        referrer_id: ID of the user who referred this agent
        active: Whether this user is still active
        join_time: When this user joined
    """

    def __init__(self, model, referrer_id=None):
        super().__init__(model)
        self.referral_count = 0
        self.total_rewards = 0
        self.referral_level = 0
        self.referrer_id = referrer_id
        self.active = True
        self.join_time = model.current_step

        # Calculate referral level
        if referrer_id is not None:
            # Find referrer agent
            referrer = None
            for agent in model.agents:
                if agent.unique_id == referrer_id:
                    referrer = agent
                    break
            if referrer:
                self.referral_level = referrer.referral_level + 1

    def step(self):
        """Agent behavior each time step"""
        # Check if user becomes inactive
        if np.random.random() < self.model.churn_probability:
            self.active = False
            return

        # Potential referral behavior
        if (self.active and
            np.random.random() < self.model.referral_probability and
            self.model.current_step - self.join_time > self.model.min_referral_delay):

            # Determine how many referrals to make
            num_referrals = np.random.poisson(self.model.average_referrals)
            num_referrals = min(num_referrals, self.model.max_referrals_per_step)

            for _ in range(num_referrals):
                if len(self.model.agents) < self.model.max_users:
                    # Create new user referred by this agent
                    new_user = UserAgent(self.model, referrer_id=self.unique_id)
                    self.referral_count += 1

                    # Update network graph
                    self.model.network.add_node(new_user.unique_id)
                    self.model.network.add_edge(self.unique_id, new_user.unique_id)


class ReferralModel(mesa.Model):
    """
    The main model for the referral system simulation.

    Parameters:
        n_initial_users: Initial number of users
        average_referrals: Average referrals per user (Poisson parameter)
        referral_probability: Probability a user makes referrals each step
        churn_probability: Probability a user becomes inactive each step
        max_users: Maximum number of users in simulation
        max_referrals_per_step: Max referrals a user can make per step
        min_referral_delay: Minimum time before a user can refer others
        reward_decay_type: Type of reward decay ('exponential', 'linear', 'fixed')
        reward_decay_factor: Decay factor for rewards (basis points)
        min_reward: Minimum reward amount
        original_user_percentage: Percentage for original user (basis points)
    """

    def __init__(self,
                 n_initial_users=10,
                 average_referrals=2.0,
                 referral_probability=0.1,
                 churn_probability=0.01,
                 max_users=1000,
                 max_referrals_per_step=3,
                 min_referral_delay=5,
                 reward_decay_type='exponential',
                 reward_decay_factor=7000,  # 70%
                 min_reward=0.01,
                 original_user_percentage=8000):  # 80%

        super().__init__()

        # Model parameters
        self.n_initial_users = n_initial_users
        self.average_referrals = average_referrals
        self.referral_probability = referral_probability
        self.churn_probability = churn_probability
        self.max_users = max_users
        self.max_referrals_per_step = max_referrals_per_step
        self.min_referral_delay = min_referral_delay
        self.current_step = 0

        # Reward parameters
        self.reward_decay_type = reward_decay_type
        self.reward_decay_factor = reward_decay_factor
        self.min_reward = min_reward
        self.original_user_percentage = original_user_percentage

        # Initialize network
        self.network = nx.DiGraph()

        # Create initial users (no referrers) - Mesa 2.x auto-assigns unique_id
        for i in range(n_initial_users):
            user = UserAgent(self)
            # Add to network with the auto-assigned unique_id
            self.network.add_node(user.unique_id)

        # Data collection
        self.datacollector = DataCollector({
            "Total Users": lambda m: len(m.agents),
            "Active Users": lambda m: len([a for a in m.agents if a.active]),
            "Total Referrals": lambda m: sum(a.referral_count for a in m.agents),
            "Average Referral Count": lambda m: np.mean([a.referral_count for a in m.agents]) if len(m.agents) > 0 else 0,
            "Network Density": lambda m: nx.density(m.network) if len(m.network.nodes()) > 0 else 0,
            "Average Path Length": lambda m: (nx.average_shortest_path_length(m.network.to_undirected())
                                           if nx.is_connected(m.network.to_undirected()) and len(m.network.nodes()) > 1
                                           else 0),
        })

    def step(self):
        """Advance the model by one step"""
        self.current_step += 1
        self.datacollector.collect(self)
        # In Mesa 2.x, we iterate through agents manually
        for agent in list(self.agents):
            agent.step()


def run_simulation(model_params, max_steps=100, n_runs=1):
    """
    Run the simulation with given parameters

    Args:
        model_params: Dictionary of model parameters
        max_steps: Maximum number of steps to run
        n_runs: Number of simulation runs

    Returns:
        List of model instances with collected data
    """
    models = []

    for run in range(n_runs):
        # Create model with parameters
        model = ReferralModel(**model_params)

        # Run simulation manually
        for _ in range(max_steps):
            model.step()

        models.append(model)

    return models