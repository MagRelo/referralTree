# SOTA: Solved Problems vs Open Problems in Referral Incentive Systems

**Date:** 2026-09-10  
**Purpose:** Separate what the industry and literature already handle well from what still breaks geometric multilevel systems—and map those gaps onto referralTree's v2 design choices.

---

## Framing

"State of the art" here means *practically deployable knowledge*, not a single leaderboard. On-chain multilevel referral is a stack of solved plumbing plus open mechanism and governance problems. referralTree ([MagRelo/referralTree](https://github.com/MagRelo/referralTree)) intentionally owns the plumbing and hybrid trust path; it does not claim to close Sybil-proof geometric theory.

## Relatively solved

**Tree storage and ancestor walks.** Parent pointers, adjacency, and depth-capped walks are commodity. Skiplists / indexed chains (as in ReferralGraph) make `getPayoutChain` gas-bounded. ThunderCore-style self-register trees and mdantis samples show the same core data structure repeatedly ([thundercore/referral-solidity](https://github.com/thundercore/referral-solidity), [mdantis-dev/SOLIDITY-referral-system](https://github.com/mdantis-dev/SOLIDITY-referral-system)).

**Depth caps and budget conservation.** Caps (referralTree: max **10**) and remainder routing (remainder to index **0**) prevent unbounded recursion and make RewardCalculator deterministic. Engineering-solved; *incentive*-incomplete (early positions still advantaged).

**Hybrid trust (oracle-gated registration).** Letting an oracle/app `register` / `batchRegister` edges while keeping the graph on-chain is a standard compromise: apps get eligibility control; chains get auditability. Abuse becomes policy (rate limits, KYC, graph rules)—explicitly referralTree's stance—rather than unsolvable on-chain Sybil detection.

**L2 volume and cheap settlement.** Cancun-era L2s make frequent settlement events and indexing (`ReferralSettlement` in the same tx as app transfers) economically fine. The live Incentive Exchange ([exchange.mattlovan.dev](https://exchange.mattlovan.dev/)) depends on this: weekly signal index for agents needs event density, not mainnet-era gas anxiety.

**Web2 referral science.** Marketing literature (Biyalogorsky; Schmitt; Kumar; Leduc/Jackson/Johari — see Doc 2 DOIs) gives usable guidance on dual-sided rewards, customer lifetime value, and program ROI. Quest platforms (Galxe, Layer3) productize campaign ops. None of that solves multilevel Sybil-proof splits on-chain—but "should we run a referral program?" is answered.

**Fee-affiliate (shallow) attribution.** LooksRare-style AffiliateManager patterns ([docs](https://docs.looksrare.org/developers/protocol-contracts/AffiliateManager)) show production success for *single-hop / fee-path* affiliates. Solved product category—different from geometric MLM trees.

## Still open

**Sybil-proof geometric mechanisms on-chain.** Emek et al. (2011) show geometric MLM mechanisms are attractive and Sybil-vulnerable ([doi:10.1145/1993574.1993606](https://doi.org/10.1145/1993574.1993606)). Drucker & Fleischer (2012) and Zhang & Tang (2023) TDGM/SP+CP ([doi:10.1145/2229012.2229046](https://doi.org/10.1145/2229012.2229046), [doi:10.1609/aaai.v37i5.25730](https://doi.org/10.1609/aaai.v37i5.25730), [arXiv:2302.06061](http://arxiv.org/abs/2302.06061)) offer directions, but production Solidity trees almost never implement those transforms. Pure **0.6** decay remains theoretically powerful and theoretically Sybil-weak.

**Trust-minimized eligibility.** Oracle/app policy works until the oracle is wrong, captured, or opaque. ZK / attestation proofs for "real user / unique human / qualified action" without custody are open product + crypto infrastructure problems. Airdrop Sybil studies (Liu & Zhu 2022 [arXiv:2209.04603](http://arxiv.org/abs/2209.04603); Liu et al. 2025 [arXiv:2505.09313](http://arxiv.org/abs/2505.09313)) show detection is arms-race, not finished science.

**Gini / early-position inequality.** Remainder-to-root and first-mover trees concentrate rewards. Mechanism papers discuss fairness (e.g., Rahwan et al. [arXiv:1404.0542](http://arxiv.org/abs/1404.0542)); few deployable contracts expose tunable fairness constraints without breaking recruitment incentives.

**Portable reputation across apps.** Referral edges today are siloed per `groupId` / per protocol. No widely adopted portable "referrer quality" primitive that other apps can consume without re-trusting the same oracle.

**Legal classification (pyramid vs MLM vs affiliate).** Vander Nat & Keep ([doi:10.1509/jppm.21.1.139.17603](https://doi.org/10.1509/jppm.21.1.139.17603), [doi:10.1108/jhrm-01-2014-0002](https://doi.org/10.1108/jhrm-01-2014-0002)) frame the policy line; on-chain matrix systems (Safwa-class) sit nearest risk. Open problem for product counsel + fee/product design—not solvable by skiplist math.

**Peer-reviewed Solidity multilevel referral lit** remains thin (Boner/Deferral BRAINS [doi:10.1109/brains59668.2023.10316807](https://doi.org/10.1109/brains59668.2023.10316807) is the standout). Most "SOTA" is code and blogs.

## Architecture tradeoff table

| Choice | Pros | Cons | referralTree |
|--------|------|------|--------------|
| Self-register parents | Trustless edges | Sybil free-for-all | Avoided; oracle register |
| Oracle-gated edges | Eligibility + batch UX | Trust / censorship | **Chosen** |
| Custodial escrow payout | Atomic on-chain pay | Custody, hack surface | **Avoided**; app transfers |
| Non-custodial graph readout | Auditable chain math | App must honor settlement | **Chosen** + `ReferralSettlement` |
| Geometric decay | Simple, Emek-aligned | Sybil-weak | **0.6 / max 10 / rem→0** |
| Matrix / forced fill | Aggressive growth loops | Legal + collapse risk | Avoided |
| Fee affiliate only | Production-proven | Not multilevel | Not the product |

## Known pitfalls

1. **Advertising "decentralized referrals" while oracle owns edges** — honest hybrid labeling beats marketing that invites security review fail.
2. **Unbounded or deep walks** — gas griefing; always cap (referralTree: 10).
3. **Assuming depth caps = Sybil-proof** — false per Emek/Drucker.
4. **Custodial reward pools without formal audits** — matrix MLMs fail operationally and legally.
5. **Ignoring early-position Gini** — community backlash even if math is "correct."
6. **Simulation gap** — Mesa under `simulation/` is the right habit; uncalibrated sims still mislead.
7. **Index/event omission** — without `ReferralSettlement`-style emission, Incentive Exchange / agents cannot observe the economy.

## Tie-back to referralTree design

V2 (CHANGELOG **2026-08-29**): Foundry, Solidity ~**0.8.26**, Cancun; ReferralGraph per-`groupId` + skiplist + oracle batching; RewardCalculator geometric; app-owned transfers; Mesa for abuse exploration. That stack **closes plumbing and hybrid ops**; it **leaves open** Sybil-aware splits, trust-minimized eligibility, fairness knobs, portable reputation, and legal–econ packaging—exactly Doc 4's opportunity set. Deferral remains the academic comparator ([github.com/dydent/Deferral](https://github.com/dydent/Deferral)); platforms (Fuul, Attrace, Galxe) remain the ops comparators.

## Sources

- referralTree — https://github.com/MagRelo/referralTree · Exchange — https://exchange.mattlovan.dev/  
- Emek — https://doi.org/10.1145/1993574.1993606 · Drucker & Fleischer — https://doi.org/10.1145/2229012.2229046 · Zhang & Tang — https://doi.org/10.1609/aaai.v37i5.25730 · http://arxiv.org/abs/2302.06061  
- Boner/Deferral BRAINS — https://doi.org/10.1109/brains59668.2023.10316807 · Deferral repo — https://github.com/dydent/Deferral  
- Liu & Zhu — http://arxiv.org/abs/2209.04603 · Liu et al. 2025 — http://arxiv.org/abs/2505.09313 · Rahwan et al. — http://arxiv.org/abs/1404.0542  
- Vander Nat & Keep — https://doi.org/10.1509/jppm.21.1.139.17603 · https://doi.org/10.1108/jhrm-01-2014-0002  
- ThunderCore / mdantis / LooksRare / Safwa / Fuul / Attrace / Galxe — as linked in Doc 1
