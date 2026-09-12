# Academic Survey: Multilevel Referral, Sybil Proofness, and Marketing Science

**Date:** 2026-09-10  
**Purpose:** Annotated map of the theory that should constrain how referralTree (and peers) split rewards—especially geometric decay, Sybil attacks, and the thin peer-reviewed Solidity multilevel referral literature.

---

## Why this survey exists

Engineers shipping geometric multilevel payouts often rediscover results that mechanism-design papers already named: **geometric shares are elegant and fragile**. This brief walks the core citations as a narrative for builders—not a bibliography dump.

**Flag up front:** peer-reviewed literature on *Solidity multilevel referral contracts* is thin. Most "on-chain referral" writing is blog posts, GitHub READMEs, or adjacent work (airdrop Sybil, query incentive networks, Deferral's BRAINS paper). Treat production trees as engineering artifacts informed by theory, not as theory validated on-chain.

## On-chain / crypto-native mechanism work

**Boner / Deferral (2023)** is the primary bridge from academia to multilevel deferred rewards on chain. The UZH thesis ([doi:10.5167/uzh-255750](https://doi.org/10.5167/uzh-255750); PDF: [owncloud.csg.uzh.ch … ma-tobias-boner.pdf](https://owncloud.csg.uzh.ch/index.php/s/77TATExxwCawcZi/download/ma-tobias-boner.pdf)) and IEEE BRAINS paper ([doi:10.1109/brains59668.2023.10316807](https://doi.org/10.1109/brains59668.2023.10316807)) analyze deferred reward distribution over referral structures, with implementations and visualizations ([Deferral](https://github.com/dydent/Deferral), [visualizations-deferral](https://github.com/dydent/visualizations-deferral)). For MagRelo: Deferral is the citation to beat on *published* deferred-referral design; referralTree's v2 graph + calculator is a parallel engineering answer (oracle register, geometric 0.6, app settlement).

## Classic MLM mechanism design

**Emek et al. (2011)** — "Mechanisms for Multi-Level Marketing" ([doi:10.1145/1993574.1993606](https://doi.org/10.1145/1993574.1993606)) — is the foundational CS result. They study reward schemes along recruitment trees and show that **geometric (exponentially decaying) mechanisms** are powerful: they can incentivize recruitment while keeping accounting local and tractable. They also show the dark twin: **geometric schemes are Sybil-vulnerable**—an agent can profit by inserting fake identities along the path (or otherwise gaming the tree) under natural conditions. This is the theoretical sentence behind referralTree's `RewardCalculator`: decay **0.6**, max depth **10**, remainder to index 0 is *exactly* in Emek's attractive-but-fragile family.

**Drucker & Fleischer (2012)** — "Simpler Sybil-Proof Mechanisms for Multi-Level Marketing" ([doi:10.1145/2229012.2229046](https://doi.org/10.1145/2229012.2229046)) — give transforms / constructions that restore Sybil-proofness (under stated models) with simpler structure than prior work. Takeaway for implementers: Sybil-proofness usually means **changing the split rule or constraints**, not "adding KYC later." Pure geometric decay alone does not inherit these proofs.

**Zhang & Tang (2023)** — TDGM / SP+CP ([doi:10.1609/aaai.v37i5.25730](https://doi.org/10.1609/aaai.v37i5.25730); [arXiv:2302.06061](http://arxiv.org/abs/2302.06061)) — advance Sybil-proof and related properties for tree-based diffusion / multi-level marketing mechanisms (including geometric-flavored designs). Useful when evaluating whether a variant of geometric decay can be patched toward SP/CP-style guarantees without abandoning on-chain computability.

## Query incentive networks (sibling literature)

**Kleinberg & Raghavan (2005)** ([doi:10.1109/sfcs.2005.63](https://doi.org/10.1109/sfcs.2005.63)) model incentives for propagating queries through networks with branching payments—intellectually adjacent to referral trees (pay ancestors for successful discovery). **Chen et al.** on Sybil-proof query incentive networks ([doi:10.1145/2482540.2482588](https://doi.org/10.1145/2482540.2482588)) tighten the Sybil angle in that setting. Related allocation/diffusion work: Rahwan et al. fair allocation ([arXiv:1404.0542](http://arxiv.org/abs/1404.0542)); Kandhway & Kotnis ([arXiv:1601.07505](http://arxiv.org/abs/1601.07505)). Builders should steal *threat models* from this line even when product UX is "invite friends," not "answer queries."

## Marketing science (empirical / managerial)

These papers justify *why* referral programs work and how rewards should be structured—not how to code trees:

- **Biyalogorsky et al.** — customer referral rewards ([doi:10.1287/mksc.20.1.82.10195](https://doi.org/10.1287/mksc.20.1.82.10195)): when to reward referrer vs. referee.
- **Schmitt et al.** — referral programs and customer value ([doi:10.1509/jm.75.1.46](https://doi.org/10.1509/jm.75.1.46)).
- **Kumar et al.** — referral program design and CRM ([doi:10.1509/jmkg.74.5.001](https://doi.org/10.1509/jmkg.74.5.001)).
- **Leduc, Jackson, Johari** — pricing and referral in networks ([doi:10.1016/j.geb.2017.05.011](https://doi.org/10.1016/j.geb.2017.05.011)).
- **Zhang & Chaintreau (2021)** — strategic referral / network effects ([arXiv:2112.00269](http://arxiv.org/abs/2112.00269)).
- **Reingewertz (2021)** — multilevel marketing economics / empirics ([doi:10.1371/journal.pone.0253700](https://doi.org/10.1371/journal.pone.0253700)).

For Incentive Exchange ([exchange.mattlovan.dev](https://exchange.mattlovan.dev/)): marketing science informs **eligibility, dual-sided rewards, and measuring incremental lift**; it does not replace Sybil-proof mechanism design.

## Pyramid vs MLM (legal–econ boundary)

**Vander Nat & Keep (2002)** ([doi:10.1509/jppm.21.1.139.17603](https://doi.org/10.1509/jppm.21.1.139.17603)) and follow-on (2014) ([doi:10.1108/jhrm-01-2014-0002](https://doi.org/10.1108/jhrm-01-2014-0002)) analyze when multilevel compensation crosses into pyramid characteristics (recruitment-heavy vs. product/sales-heavy). Matrix-style on-chain MLMs (Doc 1) sit nearest this line; referralTree's app-owned product settlement and capped geometric depth are structurally closer to "affiliate attribution with multilevel share" than forced matrix fill—but **legal classification is not a Solidity property**. Design checklists belong in Doc 4.

## Airdrop Sybil (crypto practice)

**Liu & Zhu (2022)** ([arXiv:2209.04603](http://arxiv.org/abs/2209.04603)) and **Liu et al. (2025)** ([arXiv:2505.09313](http://arxiv.org/abs/2505.09313)) document Sybil behavior in airdrop / distribution settings—the empirical attack surface closest to referral farming. referralTree correctly pushes most abuse to **app/oracle policy**; theory says that if the *on-chain split* remains pure geometric, sophisticated Sybils still have a mechanism-level opening even when farm accounts are filtered imperfectly.

## Geometric decay 0.6: powerful and Sybil-weak

| Property | Why it helps | Why it hurts |
|----------|--------------|--------------|
| Local, depth-capped shares | Cheap `getPayoutChain`; predictable UX | Caps do not equal Sybil-proofness |
| Remainder to index 0 | Conserves budget; roots funded | Concentrates value early in tree |
| Factor 0.6 | Smooth incentives along chain (Emek-style) | Fake nodes can still capture mass under Emek/Drucker threat models |

**Bottom line:** Keep geometric decay for engineering clarity; do not advertise it as Sybil-proof. Pair with oracle policy, eligibility proofs, or SP-style split variants (Docs 3–4).

## Sources

- Boner thesis — https://doi.org/10.5167/uzh-255750 · BRAINS — https://doi.org/10.1109/brains59668.2023.10316807 · PDF — https://owncloud.csg.uzh.ch/index.php/s/77TATExxwCawcZi/download/ma-tobias-boner.pdf  
- Emek et al. — https://doi.org/10.1145/1993574.1993606  
- Drucker & Fleischer — https://doi.org/10.1145/2229012.2229046  
- Zhang & Tang — https://doi.org/10.1609/aaai.v37i5.25730 · http://arxiv.org/abs/2302.06061  
- Kleinberg & Raghavan — https://doi.org/10.1109/sfcs.2005.63 · Chen et al. — https://doi.org/10.1145/2482540.2482588  
- Rahwan et al. — http://arxiv.org/abs/1404.0542 · Kandhway & Kotnis — http://arxiv.org/abs/1601.07505  
- Biyalogorsky — https://doi.org/10.1287/mksc.20.1.82.10195 · Schmitt — https://doi.org/10.1509/jm.75.1.46 · Kumar — https://doi.org/10.1509/jmkg.74.5.001 · Leduc/Jackson/Johari — https://doi.org/10.1016/j.geb.2017.05.011 · Zhang & Chaintreau — http://arxiv.org/abs/2112.00269 · Reingewertz — https://doi.org/10.1371/journal.pone.0253700  
- Vander Nat & Keep — https://doi.org/10.1509/jppm.21.1.139.17603 · https://doi.org/10.1108/jhrm-01-2014-0002  
- Liu & Zhu — http://arxiv.org/abs/2209.04603 · Liu et al. 2025 — http://arxiv.org/abs/2505.09313
