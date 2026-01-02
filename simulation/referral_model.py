"""
Referral System Agent-Based Model

This Mesa-based simulation models a multi-level referral reward system
where users can refer others and earn rewards from their referral network.
"""

import mesa
import networkx as nx
import numpy as np
from mesa.datacollection import DataCollector
from dataclasses import dataclass
from typing import List, Tuple, Dict
import hashlib
from enum import Enum


class DecayType(Enum):
    """Reward decay types matching the smart contract"""
    LINEAR = "linear"
    EXPONENTIAL = "exponential"
    FIXED = "fixed"


@dataclass
class RewardEvent:
    """Represents a reward-triggering event in the simulation"""
    user_id: int
    total_amount: float  # Base amount for reward calculations
    event_type: str     # "purchase", "milestone", "achievement"
    timestamp: int

    def __post_init__(self):
        # Create unique event ID
        event_string = f"{self.user_id}_{self.total_amount}_{self.event_type}_{self.timestamp}"
        self.event_id = hashlib.md5(event_string.encode()).hexdigest()


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
        self.total_rewards = 0.0
        self.pending_rewards = 0.0  # Rewards earned but not yet distributed
        self.referral_level = 0
        self.referrer_id = referrer_id
        self.active = True
        self.join_time = model.current_step
        self.last_reward_time = model.current_step

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
        self.reward_decay_type = DecayType(reward_decay_type) if isinstance(reward_decay_type, str) else reward_decay_type
        self.reward_decay_factor = reward_decay_factor
        self.min_reward = min_reward
        self.original_user_percentage = original_user_percentage

        # Reward event tracking
        self.reward_events = []
        self.total_rewards_distributed = 0.0
        self.reward_distribution_count = 0

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
            "Total Rewards Distributed": lambda m: m.total_rewards_distributed,
            "Average Rewards per User": lambda m: (sum(a.total_rewards for a in m.agents) / len(m.agents)) if len(m.agents) > 0 else 0,
            "Reward Events": lambda m: len(m.reward_events),
        })

    def step(self):
        """Advance the model by one step"""
        self.current_step += 1
        self.datacollector.collect(self)

        # In Mesa 2.x, we iterate through agents manually
        for agent in list(self.agents):
            agent.step()

        # Generate reward events (simulate user activities)
        self._generate_reward_events()

    def _generate_reward_events(self):
        """Generate reward events based on active user behavior"""
        active_users = [a for a in self.agents if a.active]

        if not active_users:
            return

        # Probability of an event per active user per step
        event_probability = 0.02  # 2% chance per user per step

        for user in active_users:
            if np.random.random() < event_probability:
                # Generate reward amount (log-normal distribution for realistic rewards)
                reward_amount = np.random.lognormal(mean=2.0, sigma=1.0)  # Mean ~$7.39

                # Create reward event
                event = RewardEvent(
                    user_id=user.unique_id,
                    total_amount=reward_amount,
                    event_type="purchase",  # Could be randomized later
                    timestamp=self.current_step
                )

                # Distribute rewards
                self._distribute_chain_rewards(event)

    def _distribute_chain_rewards(self, event: RewardEvent):
        """Distribute rewards across the referral chain (matches contract logic)"""
        # Get referral chain for the user
        chain = self._get_referral_chain(event.user_id)

        if not chain:
            return

        # Calculate reward distribution
        recipients, amounts = self._calculate_chain_rewards(event.total_amount, chain)

        # Distribute rewards to recipients
        total_distributed = 0.0
        for recipient_id, amount in zip(recipients, amounts):
            if amount > 0:
                # Find the agent and add rewards
                for agent in self.agents:
                    if agent.unique_id == recipient_id:
                        agent.total_rewards += amount
                        agent.last_reward_time = self.current_step
                        total_distributed += amount
                        break

        # Track event
        self.reward_events.append(event)
        self.total_rewards_distributed += total_distributed
        self.reward_distribution_count += 1

    def _get_referral_chain(self, user_id: int) -> List[int]:
        """Get the referral chain from user up to root (matches contract logic)"""
        chain = []
        current_id = user_id
        visited = set()

        # Traverse up the referral chain (avoid cycles)
        while current_id is not None and current_id not in visited:
            visited.add(current_id)
            chain.append(current_id)

            # Find referrer
            current_id = None
            for agent in self.agents:
                if agent.unique_id == chain[-1]:
                    current_id = agent.referrer_id
                    break

            # Limit chain depth to prevent infinite loops
            if len(chain) > 50:
                break

        return chain

    def _calculate_chain_rewards(self, total_amount: float, chain: List[int]) -> Tuple[List[int], List[float]]:
        """Calculate reward distribution across chain (matches contract _calculateChainRewards)"""
        if not chain:
            return [], []

        # Original user gets their percentage
        original_user_reward = (total_amount * self.original_user_percentage) / 10000
        remaining_for_chain = total_amount - original_user_reward

        recipients = [chain[0]]  # Original user
        amounts = [original_user_reward]

        # Calculate rewards for referral chain (excluding original user)
        num_referrers = len(chain) - 1  # chain[0] is original user
        remaining_to_distribute = remaining_for_chain

        for i in range(num_referrers):
            if remaining_to_distribute < self.min_reward:
                break  # Not enough left to distribute

            # Calculate level reward based on decay type
            level_reward = self._calculate_level_reward(remaining_to_distribute, i + 1)

            # Ensure minimum reward and don't exceed remaining
            if level_reward < self.min_reward:
                level_reward = min(remaining_to_distribute, self.min_reward) if remaining_to_distribute >= self.min_reward else 0

            if level_reward > 0 and level_reward <= remaining_to_distribute:
                recipients.append(chain[i + 1])
                amounts.append(level_reward)
                remaining_to_distribute -= level_reward
            else:
                break

        # Any remaining goes to "dust" (could be oracle/platform in real system)
        if remaining_to_distribute > 0:
            # For simulation, we could add a platform fee recipient
            # For now, we'll just track it as distributed
            pass

        return recipients, amounts

    def _calculate_level_reward(self, base_amount: float, level: int) -> float:
        """Calculate reward for a specific level using the configured decay function"""
        if self.reward_decay_type == DecayType.LINEAR:
            # Linear decay: reward = max(minReward, baseAmount * (1 - decayRate * level))
            decay_amount = (base_amount * self.reward_decay_factor * level) / 10000
            if decay_amount >= base_amount:
                return self.min_reward
            reward = base_amount - decay_amount
            return max(reward, self.min_reward)

        elif self.reward_decay_type == DecayType.EXPONENTIAL:
            # Exponential decay: each level gets decayFactor% of the previous level's reward
            reward = base_amount
            for i in range(level):
                reward = (reward * self.reward_decay_factor) / 10000
                if reward < self.min_reward:
                    return self.min_reward
            return reward

        elif self.reward_decay_type == DecayType.FIXED:
            # Fixed amount per level
            return max(self.reward_decay_factor, self.min_reward)

        return self.min_reward  # Fallback


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