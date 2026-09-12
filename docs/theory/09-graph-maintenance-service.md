# Graph maintenance as a service

**Date:** 2026-09-11  
**Purpose:** Product sketch — detect ReferralGraph shapes/patterns; score risk; recommend skiplist/policy. Aligns with `docs/abuse-mitigation.md` (contracts = invariants; app/oracle = quality).

## One-liner

Watch graphs + settlements, score shape/risk, recommend or apply skiplist and policy so projects don't hand-farm their trees.

## Patterns

| Pattern | Signal | Action |
|---------|--------|--------|
| Chain farms | Low fanout, high depth, funding clusters | Skiplist mid-chain / farm root |
| Star / hub Sybil | Huge children, tiny grandchildren | Cap registers; raise eligibility |
| Bush healthy | Mean eligible children ≳ 2 | Green signal for Exchange |
| Wallet clusters | Same deployer/timing bursts | Quarantine before payout |
| Gini capture | Few addresses dominate `totalPaid` | Alert; DR calculator / caps |
| Settlement/register skew | Many edges, few settlements | Cheap-signal flag |
| Oracle anomaly | Burst `batchRegister` | Dual-control / pause |
| Cross-group clones | Same topology on many `groupId`s | Shared denylist (opt-in) |

## Product shapes

1. Read-only **Graph Health** on Exchange listings  
2. **Skiplist Copilot** — propose + human confirm  
3. **Policy-as-a-service** — managed eligibility rules  
4. **Attack sim pack** — Mesa Sybil shapes vs calculator strategies  
5. Opt-in shared denylist / reputation subgraph  

Ties to **IC after tx costs**: detectors should price abuse ROI against gas and reward size.
