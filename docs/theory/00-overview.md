# Theory & research overview

**Date:** 2026-09-12  
**Purpose:** Permanent home for Incentive Exchange / referralTree research and theory developed with MagRelo. Living index for the briefs in this folder.

## Design thesis (keep this)

People will not take referral actions that are **not incentive-compatible once transaction costs are in the denominator**.

Here **transaction costs** means the Coasean / game-theory sense: friction of search, bargaining, verification, enforcement, and coordination among agents — **not** the literal monetary cost of executing an EVM transaction. Gas fees can be one *channel* through which coordination friction falls, but they are not the thesis.

Agents that can discover and act on opportunities, cheap L2 settlement rails, and blockchain transparency (public graphs, receipts, attribution that cannot be quietly rewritten) all lower those frictions. When they do, previously uneconomic incentive-compatible designs open up — deeper trees, finer geometric splits, agent-mediated queries, graph-maintenance loops.

Short label: **IC after tx costs** (Coasean friction, not gas).

## What referralTree is

Non-custodial multilevel attribution + split math:

- `ReferralGraph` — per-`groupId` trees, oracle register/skiplist, `getPayoutChain`
- `RewardCalculator` — geometric **0.6** decay, max **10**, remainder to seed
- App owns transfers; emit `ReferralSettlement` in the same tx for **Incentive Exchange** indexing

See the main [README](../../README.md) and [docs/abuse-mitigation.md](../abuse-mitigation.md).

## Document map

| File | Contents |
|------|----------|
| [01-industry-landscape.md](./01-industry-landscape.md) | On-chain peers + growth platforms; architecture patterns |
| [02-academic-survey.md](./02-academic-survey.md) | QIN, geometric MLM, Sybil-proof transforms, marketing science |
| [03-sota-solved-vs-open.md](./03-sota-solved-vs-open.md) | Solved plumbing vs open mechanism/governance problems |
| [04-positioning-and-opportunities.md](./04-positioning-and-opportunities.md) | Where MagRelo sits; five opportunity areas |
| [05-deferral-vs-referraltree.md](./05-deferral-vs-referraltree.md) | Boner/Deferral evaluator ladder mapped onto Graph/Calculator/Exchange |
| [06-thundercore-vs-referraltree.md](./06-thundercore-vs-referraltree.md) | Feature compare vs ThunderCore `referral-solidity` |
| [07-query-incentive-networks.md](./07-query-incentive-networks.md) | Kleinberg–Raghavan lineage and takeaways for MagRelo |
| [08-market-notes.md](./08-market-notes.md) | Web2/web3 market numbers (with confidence flags) |
| [09-graph-maintenance-service.md](./09-graph-maintenance-service.md) | Network shape detection as a service (skiplist/policy layer) |
| [ie-qin-copy-suggestions.md](./ie-qin-copy-suggestions.md) | Paste-ready Incentive Exchange copy (QIN framing) |

## Framing anchors

- **Incentive Exchange** — query incentive network for agents: mechanisms + settlement receipts, not an agent runtime society (contrast: iLands).
- **Geometric path credit** — same DNA as query incentive networks; Sybil-aware designs often concentrate pay on finder + direct hop.
- **Graph maintenance** — productize shape/risk scoring → skiplist recommendations; Exchange surfaces bushy vs chainy health.

## How to extend

Add dated notes under this folder; link them from this overview. Prefer sourced claims; never invent citations or market figures.
