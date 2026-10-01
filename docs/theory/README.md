# Theory & Research

This folder contains research and design documents for the referralTree multi-level referral system.

## Documents

| File | Description |
|------|-------------|
| [graph-topologies.md](graph-topologies.md) | Dangerous/suspicious graph shapes for off-chain indexer detection |

## Design thesis

People will not take referral actions that are **not incentive-compatible once transaction costs are in the denominator**.

Here **transaction costs** means the Coasean / game-theory sense: friction of search, bargaining, verification, enforcement, and coordination among agents — **not** the literal monetary cost of executing an EVM transaction.

The indexer and graph-maintenance service exist to **lower verification and enforcement costs** by detecting bad graph shapes before they extract value.

## Related

- [abuse-mitigation.md](../abuse-mitigation.md) — Contract-level controls and integrator policy
- [README](../../README.md) — Main system overview
