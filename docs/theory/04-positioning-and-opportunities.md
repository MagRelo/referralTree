# Positioning and Opportunities for referralTree / MagRelo

**Date:** 2026-09-10  
**Purpose:** Position referralTree against Deferral, on-chain MLM clones, and growth platforms—then expand five actionable opportunity areas and suggested next experiments for Matt Lovan.

---

## Positioning snapshot

**referralTree** ([github.com/MagRelo/referralTree](https://github.com/MagRelo/referralTree)) is a non-custodial multilevel referral **graph + calculator** with app-owned settlement and indexed events. Live surface: Incentive Exchange ([exchange.mattlovan.dev](https://exchange.mattlovan.dev/))—weekly signal index for agents. v2 (CHANGELOG **2026-08-29**): ReferralGraph (per-`groupId`, oracle `register`/`batchRegister`, skiplist, `getPayoutChain`) + RewardCalculator (**0.6** geometric, max **10**, remainder to index **0**); Foundry / Solidity ~**0.8.26** / Cancun; Mesa under `simulation/`.

| Comparator | Their center of gravity | referralTree relative stance |
|------------|-------------------------|------------------------------|
| **Deferral** ([dydent/Deferral](https://github.com/dydent/Deferral); viz [visualizations-deferral](https://github.com/dydent/visualizations-deferral); Boner thesis [doi:10.5167/uzh-255750](https://doi.org/10.5167/uzh-255750), BRAINS [doi:10.1109/brains59668.2023.10316807](https://doi.org/10.1109/brains59668.2023.10316807)) | Published deferred-reward mechanism + analysis | Prefer production graph/API + Exchange instrumentation; cite Deferral as academic peer, not clone |
| **ThunderCore / Clicks / Safwa / mdantis** ([referral-solidity](https://github.com/thundercore/referral-solidity), [clicks-protocol](https://github.com/clicks-protocol/clicks-protocol), [Safwa](https://github.com/SafwaNetwork/contract.safwa.network), [mdantis](https://github.com/mdantis-dev/SOLIDITY-referral-system)) | Self-register trees or matrix/MLM payout coupling | Avoid custody and matrix fill; oracle-gated edges; app transfers |
| **Attrace / Fuul** ([attrace.com/about](https://attrace.com/about/), [fuul.xyz](https://www.fuul.xyz/)) | Affiliate/attribution networks & protocol reward infra | Compete on open graph math + research instrument, not on full CRM/ops suite |
| **LooksRare AffiliateManager** ([docs](https://docs.looksrare.org/developers/protocol-contracts/AffiliateManager)) | Fee-path shallow affiliate | Multilevel geometric is different product; borrow fee-funded *economics*, not topology |
| **Galxe / Layer3 / ShareMint / XOffer** | Campaign / quest / offer growth | Partner/integrate for distribution; do not reinvent quest UX |

**One-line position:** MagRelo ships the auditable multilevel *split substrate* and an agent-facing signal market; platforms own campaigns; Deferral owns the thesis citation; matrix coins own the legal heat.

## Opportunity 1 — Sybil-aware split variants on-chain

Emek et al. ([doi:10.1145/1993574.1993606](https://doi.org/10.1145/1993574.1993606)) show geometric mechanisms invite Sybil strategies; Drucker & Fleischer ([doi:10.1145/2229012.2229046](https://doi.org/10.1145/2229012.2229046)) and Zhang & Tang TDGM/SP+CP ([doi:10.1609/aaai.v37i5.25730](https://doi.org/10.1609/aaai.v37i5.25730), [arXiv:2302.06061](http://arxiv.org/abs/2302.06061)) sketch proof-oriented alternatives. **Action:** add a `RewardCalculator` strategy interface—keep `Geometric06` as default; implement 1–2 Sybil-aware variants (e.g., transforms inspired by Drucker/Fleischer or SP+CP-style constraints) as pure view math over the same `getPayoutChain`. Compare under Mesa: attack profit vs. honest recruitment surplus. Ship as opt-in `groupId` policy, not a breaking default. Document explicitly that depth caps ≠ Sybil-proofness.

## Opportunity 2 — Eligibility proofs without custody

Oracle registration is honest hybrid trust; the open ask is *verifiable* eligibility without pulling funds into the graph contracts. **Action:** define an attestation hook—oracle submits edge + claim commitment (passport / credential / action receipt hash) rather than naked `(referrer, referee)`. Keep transfers app-side. Align threat model with airdrop Sybil literature (Liu & Zhu [arXiv:2209.04603](http://arxiv.org/abs/2209.04603); Liu et al. 2025 [arXiv:2505.09313](http://arxiv.org/abs/2505.09313)): measure false-accept under farmed wallets. Goal is not "decentralize KYC tomorrow"; it is **make eligibility audits reproducible** for Exchange consumers and partners (Fuul/Attrace-class) who need proof-friendly hooks.

## Opportunity 3 — Graph analytics → skiplist automation

Skiplist + per-`groupId` trees already encode structure that growth teams usually only see in BI tools. **Action:** offline (or keeper) job that scores nodes—depth distribution, fanout, recirculation, suspected Sybil clusters—and proposes `batchRegister` / quarantine policies. Feed metrics into Incentive Exchange as first-class signals (not only settlement amounts). Close the loop with Mesa: regenerate synthetic graphs matching live degree distributions, then stress RewardCalculator variants. This is a differentiation ThunderCore clones lack and platforms rarely open-source.

## Opportunity 4 — Incentive Exchange as research instrument

Most referral repos die as static Solidity. The Exchange's weekly signal index for agents makes MagRelo a **measurement platform**: publish anonymized chain-length histograms, decay residual to root, settlement latency, and (later) Sybil-score proxies. **Action:** version a public research schema tied to `ReferralSettlement` events; run A/B `groupId`s with different calculators; invite replication against Deferral-style deferred schemes. Positioning win: Attrace/Fuul sell attribution ops; MagRelo sells **open incentive telemetry** engineers and agents can query.

## Opportunity 5 — Legal–econ design checklist / fee-funded templates

Vander Nat & Keep ([doi:10.1509/jppm.21.1.139.17603](https://doi.org/10.1509/jppm.21.1.139.17603), [doi:10.1108/jhrm-01-2014-0002](https://doi.org/10.1108/jhrm-01-2014-0002)) separate product-anchored MLM from recruitment pyramids; Reingewertz ([doi:10.1371/journal.pone.0253700](https://doi.org/10.1371/journal.pone.0253700)) and marketing referral papers (Biyalogorsky [doi:10.1287/mksc.20.1.82.10195](https://doi.org/10.1287/mksc.20.1.82.10195); Schmitt [doi:10.1509/jm.75.1.46](https://doi.org/10.1509/jm.75.1.46); Kumar [doi:10.1509/jmkg.74.5.001](https://doi.org/10.1509/jmkg.74.5.001)) inform reward sidedness. **Action:** publish a short MagRelo checklist—product/fee nexus required, depth cap, no forced matrix, app settlement of real economic activity, disclose oracle role—and ship a **fee-funded template** (LooksRare-like shallow cut *plus* optional geometric drip from protocol fees) that stays far from Safwa-class matrix optics. Counsel review is out of band; the engineering artifact is opinionated defaults that fail closed toward affiliate-like economics.

## Suggested next experiments for Matt

1. **Fork calculator strategies** — Geometric06 vs. one SP-inspired variant; Mesa Sybil insert attacks; report attack ROI curves.  
2. **Attested register prototype** — `batchRegister` with claim hash field; reject path without breaking non-custodial payouts.  
3. **Exchange research schema v0** — weekly publish depth/Gini/residual-to-root from live settlements.  
4. **Fee-funded group template** — single reference `groupId` config + docs checklist for partners.  
5. **Deferral comparative note** — one page: deferred vs. immediate app settlement under identical trees (cite Boner; link both repos).

Ship experiments as Foundry tests + Mesa notebooks first; promote winners to Exchange-visible `groupId`s second. That sequence keeps referralTree in its lane: sharp incentive substrate, not another quest board.

## Sources

- MagRelo/referralTree — https://github.com/MagRelo/referralTree · Exchange — https://exchange.mattlovan.dev/  
- Deferral — https://github.com/dydent/Deferral · visualizations — https://github.com/dydent/visualizations-deferral · Boner — https://doi.org/10.5167/uzh-255750 · https://doi.org/10.1109/brains59668.2023.10316807  
- ThunderCore / Clicks / Safwa / mdantis / LooksRare / Attrace / Fuul — URLs as in Doc 1  
- Emek — https://doi.org/10.1145/1993574.1993606 · Drucker & Fleischer — https://doi.org/10.1145/2229012.2229046 · Zhang & Tang — https://doi.org/10.1609/aaai.v37i5.25730 · http://arxiv.org/abs/2302.06061  
- Liu & Zhu — http://arxiv.org/abs/2209.04603 · Liu et al. 2025 — http://arxiv.org/abs/2505.09313  
- Vander Nat & Keep — https://doi.org/10.1509/jppm.21.1.139.17603 · https://doi.org/10.1108/jhrm-01-2014-0002 · Reingewertz — https://doi.org/10.1371/journal.pone.0253700 · Biyalogorsky — https://doi.org/10.1287/mksc.20.1.82.10195 · Schmitt — https://doi.org/10.1509/jm.75.1.46 · Kumar — https://doi.org/10.1509/jmkg.74.5.001
