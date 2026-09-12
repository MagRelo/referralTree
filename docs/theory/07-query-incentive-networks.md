# Query incentive networks — takeaways for MagRelo

**Date:** 2026-09-10  
**Purpose:** Distill the QIN literature that inspired referralTree / Incentive Exchange framing.

## Core model (Kleinberg & Raghavan, FOCS 2005)

Root wants an **answer**; offers a reward; each hop that lacks it forwards a **smaller** offer and hopes to keep the difference. Propagation stops when residual hits zero. Nash exists in how aggressively nodes skim.

Shared DNA with geometric referral: **path-shared residual reward**. Timing differs: QIN builds the path during the hunt; referralTree **reuses a standing attribution tree** when value appears.

## Results that matter

1. **Depth must eat the pool** — intermediaries need a cut or they won't forward.
2. **Critical branching ≈ 2** (not 1) once incentives are strategic: below ~2 effective offspring, required root stake blows up; above 2, O(log n) can suffice for rare answers (n = rarity).
3. **Sybil push toward Direct Referral** (Chen et al., EC 2013) — concentrate reward on answer holder + direct parent; deep geometric is Sybil-honeypot without eligibility.
4. **Red-balloon / DARPA line** — recursive splits work when the answer is verifiable and the pot is real.

## MagRelo implications

- Instrument Exchange for **fanout / bush vs chain** (eligible branching).
- Offer optional **finder-heavy / DR** calculator beside Geometric06.
- Qualifying action = "held the answer"; don't pay geometric on wallet-connect.
- Stake size should track rarity/hardness of the signal (IC after Coasean tx costs: reward must clear coordination friction for intermediaries to forward).
- Skiplist as extinction control on bad lineages.

## Sources

- Kleinberg & Raghavan — https://doi.org/10.1109/sfcs.2005.63 · https://www.cs.cornell.edu/home/kleinber/focs05-qin.pdf  
- Chen et al. Sybil-proof QIN — https://doi.org/10.1145/2482540.2482588  
