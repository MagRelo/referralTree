"""
Visualization server for the Referral System model using Mesa's Solara interface.
"""

import solara
from referral_model import ReferralModel, UserAgent
from mesa.visualization import SolaraViz, make_space_component, make_plot_component
import networkx as nx
import matplotlib.pyplot as plt
import numpy as np


def network_portrayal(G):
    """Create a portrayal of the referral network for visualization"""
    if G is None or len(G.nodes()) == 0:
        return {}

    # Calculate positions using spring layout
    pos = nx.spring_layout(G, seed=42)

    # Create node portrayal
    portrayal = {
        "nodes": [],
        "edges": []
    }

    # Add nodes
    for node_id in G.nodes():
        # Get agent data if available
        agent = None
        if hasattr(G, '_model') and G._model:
            try:
                agent = G._model.agents[node_id]
            except (KeyError, IndexError):
                agent = None

        node_color = "blue" if agent and agent.active else "gray"
        node_size = 10 + (agent.referral_count * 2) if agent else 10

        portrayal["nodes"].append({
            "id": node_id,
            "x": pos[node_id][0] * 100,
            "y": pos[node_id][1] * 100,
            "color": node_color,
            "size": node_size,
            "label": f"User {node_id}"
        })

    # Add edges
    for edge in G.edges():
        portrayal["edges"].append({
            "source": edge[0],
            "target": edge[1],
            "color": "gray",
            "width": 1
        })

    return portrayal


def create_model():
    """Create the referral model with default parameters"""
    model = ReferralModel(
        n_initial_users=5,
        average_referrals=2.0,
        referral_probability=0.15,
        churn_probability=0.005,
        max_users=200
    )
    return model


def make_network_component(model):
    """Create a network visualization component"""
    def get_network_data():
        return model.network

    # Create a simple plot component for the network
    return make_plot_component("Total Users")


# Model parameters for the UI
model_params = {
    "n_initial_users": solara.Slider("Initial Users", value=5, min=1, max=20, step=1),
    "average_referrals": solara.Slider("Average Referrals", value=2.0, min=0.5, max=5.0, step=0.5),
    "referral_probability": solara.Slider("Referral Probability", value=0.15, min=0.01, max=0.5, step=0.01),
    "churn_probability": solara.Slider("Churn Probability", value=0.005, min=0.0, max=0.05, step=0.001),
    "max_users": solara.Slider("Max Users", value=200, min=50, max=1000, step=50),
}

# Create the visualization page
model = create_model()
page = SolaraViz(
    model,
    [
        make_space_component(network_portrayal),
        make_plot_component("Total Users"),
        make_plot_component("Active Users"),
        make_plot_component("Total Referrals"),
    ],
    model_params=model_params,
    name="Referral Network Simulation"
)

if __name__ == "__main__":
    page