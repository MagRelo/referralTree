# Dangerous and Suspicious Graph Topologies for Referral Tree Indexing

**Date:** 2026-10-01  
**Purpose:** Catalog graph shapes the off-chain indexer / graph-maintenance service should detect, avoid, or highlight in ReferralGraph trees. Ties to `docs/abuse-mitigation.md` (contracts = invariants; app/oracle = quality) and the graph-maintenance-service concept.

---

## Design context

**System recap** (verify against the [main README](../../README.md)):

- `ReferralGraph` stores per-`groupId` referral trees, oracle-gated registration, skiplist management, and EIP-712-signed `rewardRoots` / `rewardLeaf` payouts.
- `RewardCalculator` splits rewards using **geometric 0.6 decay**, capped at **10 recipients**, with the **remainder going to the seed/root** (index 0).
- The integrating app owns transfers; settlement happens in the same transaction; tokens are pulled from `msg.sender`.
- A protocol fee (default 0) is deducted from `totalAmount` before the split.

**Design thesis:** Incentive compatibility after *transaction costs* (Coasean friction—search, verification, enforcement, coordination—not gas). The indexer exists to **lower verification and enforcement costs** by flagging bad shapes before they extract value.

**Legal framing:** The depth cap of 10 is an **engineering and optics choice**, not a legal safe harbor. Legal weight rests on settlement-tied pay, no join fees, and no forced matrix. Shape detection is a compliance and economics tool, not a legal shield.

---

## Payout mechanics reference

For a chain of length `n` (1 ≤ n ≤ 10), each level `k` (0-indexed, 0 = seed) receives:

```
share(k, n) = 0.6^k / Σ_{j=0}^{n-1} 0.6^j
```

At the 10-recipient cap:

| Level | Share |
|-------|------:|
| 0 (seed) | 40.25% |
| 1 | 24.15% |
| 2 | 14.49% |
| 3 | 8.69% |
| 4 | 5.22% |
| 5 | 3.13% |
| 6 | 1.88% |
| 7 | 1.12% |
| 8 | 0.67% |
| 9 | 0.40% |

Key attacker incentives:
1. **Control the seed** (level 0) to capture ~40% of every payout.
2. **Control the first few levels** to capture ~65–80% cumulatively.
3. **Stuff chains to exactly 10** to maximize the number of colluding levels paid.
4. **Place Sybils near the depth cap** so legitimate users push payouts to colluders.

---

## Topology catalog

Each entry contains:
- **Definition** with ASCII or Mermaid sketch
- **Why dangerous** for the 0.6^k / 10-cap payout
- **Detection signals** the indexer can compute
- **Recommended action**: block, down-weight, flag for review, or highlight
- **Academic grounding** (verified citations)

---

### 1. Long single chains / path graphs (Sybil chain stuffing)

**Definition:**  
A linear chain with minimal branching—each node has at most one child.

```
R ─► A ─► B ─► C ─► D ─► E ─► F ─► G ─► H ─► I ─► J
```

**Why dangerous:**  
An attacker creates a chain of Sybil wallets to capture all 10 payout slots. If the attacker controls A–J, every payout triggered by any downstream user pays 100% to the attacker's wallets. Under 0.6^k decay, the attacker captures the entire budget because there are no honest ancestors to compete.

**Quantified example:**  
If the attacker creates 9 Sybils (B–J) under their primary wallet A, and a legitimate user K registers under J:
- Any `rewardRoots(K, …)` pays: A (40.25%), B (24.15%), …, J (0.40%).
- Total to attacker: 100%.

**Detection signals:**
- **Path length / depth** without branching: `max_depth(node)` where `fanout(ancestor) == 1`.
- **Branching factor distribution**: median/mean < 1.1 over many levels.
- **Chain age concentration**: many sequential registrations in a short window.
- **Funding graph correlation**: same funding source for consecutive chain members.

**Action:** **Flag for review**; auto-skiplist mid-chain nodes if chain length ≥ 7 with fanout ≤ 1.2 per node and no qualifying events from leaves.

**Literature:**
- Douceur (2002) on Sybil attacks [[1]](#ref-douceur)
- Emek et al. (2011) on geometric mechanism Sybil vulnerability [[2]](#ref-emek)

---

### 2. Caterpillars and brooms

**Definition:**  
A long spine with short "legs" (caterpillar) or a single long chain ending in a dense burst of leaves (broom/comet).

```
Caterpillar:                     Broom:
R ─► A ─► B ─► C ─► D ─► E       R ─► A ─► B ─► C ─► D ─┬► L1
    │     │     │     │                                 ├► L2
    └►a1  └►b1  └►c1  └►d1                              ├► L3
                                                        ├► L4
                                                        └► ...
```

**Why dangerous:**  
The spine captures geometric decay rewards from all legs/leaves. A single attacker controlling the spine monetizes every leaf registration without contributing to recruitment quality. The caterpillar looks "bushy" superficially (many nodes) but concentrates value at the root/spine.

**Quantified example (broom):**  
If attacker controls R–D (5 nodes, depth 4) and 100 leaves register under D:
- Each leaf reward pays D (43.4%), C (26%), B (15.6%), A (9.4%), R (5.6%).
- Attacker captures 100% of 100 leaf payouts.

**Detection signals:**
- **Spine-to-leaf ratio**: `|spine| / |leaves|` where spine nodes have exactly 1 child except terminal.
- **Depth vs. width disparity**: `depth >> log₂(size)`.
- **Terminal burst**: large `|children(node)|` concentrated at one depth level.

**Action:** **Down-weight** payout eligibility for spine nodes; require qualifying actions from spine members.

**Literature:**
- Drucker & Fleischer (2012) on split-proof mechanisms [[3]](#ref-drucker)

---

### 3. Star / hub capture and mega-recruiter concentration

**Definition:**  
One node has an extremely high number of direct children (star topology). Mega-recruiters may be legitimate early adopters or attackers farming referral bonuses.

```
        ┌► C1
        ├► C2
R ─► A ─┼► C3
        ├► C4
        ├► ...
        └► Cn  (n >> 100)
```

**Why dangerous:**  
Under 0.6^k, node A captures 62.5% of every payout triggered by its children (2-level chain), R captures 37.5%. If A is a Sybil farmer, a small set of wallets extracts most referral value. Even if A is honest, concentration creates single points of failure for network health and regulatory optics.

**Detection signals:**
- **Out-degree (children count)** exceeding percentile threshold (e.g., > 99th percentile for group).
- **Children-to-grandchildren ratio**: few grandchildren suggests A's children are inactive.
- **Timing burst**: large batch of children registered in a short window.
- **Payout Gini coefficient** for top-N ancestors.

**Action:** **Flag for review**; cap per-referrer registration rate; require KYC/proof-of-personhood for mega-recruiters.

**Literature:**
- SybilRank (2012) on degree bias correction [[4]](#ref-sybilrank)
- Kumar et al. (2010) on referral program design [[5]](#ref-kumar)

---

### 4. Dense clumps, cliques, and near-cliques (collusion rings)

**Definition:**  
A subgraph where many nodes refer each other densely, approaching a clique in the underlying *identity* graph (even if the referral tree is directed and acyclic). In the tree, this appears as multiple short chains converging on a small ancestor set.

```
Identity-level view (not tree):
    A ──── B
    │ \  / │
    │  \/  │
    │  /\  │
    │ /  \ │
    C ──── D

Tree manifestation:
R ─► A ─► B
    └► C ─► D
        └► B (would be rejected; but B and D share funding, timing)
```

**Why dangerous:**  
Collusion rings coordinate to trigger payouts and share proceeds off-chain. Even if the on-chain tree is valid, the same beneficial owner controls multiple nodes across different subtrees, capturing rewards from multiple paths.

**Detection signals:**
- **Funding graph density**: bipartite subgraph `(payers, payees)` has high edge density.
- **Shared withdrawal destinations**.
- **Temporal correlation**: registration and payout events cluster within minutes.
- **IP / device fingerprint overlap** (off-chain).

**Action:** **Flag for review**; investigate off-chain; skiplist if confirmed.

**Literature:**
- FRAUDAR (Hooi et al., 2016) on dense-subgraph fraud [[6]](#ref-fraudar)
- CopyCatch (Beutel et al., 2013) on lockstep detection [[7]](#ref-copycatch)

---

### 5. Sybil regions joined by a sparse cut

**Definition:**  
A cluster of nodes with dense internal connections that attaches to the honest graph via a small number of edges (attack edges). Classic Sybil partition.

```
Honest region          Attack edges      Sybil region
    ●───●───●              │              ○───○───○
    │   │   │           ───┼───           │   │   │
    ●───●───●              │              ○───○───○
          \                │                 │
           ●──────────── attack ──────────── ○
```

**Why dangerous:**  
Sybils receive rewards whenever honest users downstream of the Sybil region trigger payouts. The sparse cut makes removal cheap: skiplisting the attack edge severs the entire Sybil cluster.

**Detection signals:**
- **Conductance / normalized cut** of candidate subgraphs.
- **Random walk escape probability**: short walks from a trusted seed rarely land in the suspect region.
- **SybilRank / SybilLimit scores** below threshold.

**Action:** **Block/skiplist** the attack edge(s) and quarantine the cluster.

**Literature:**
- SybilGuard (Yu et al., 2006) [[8]](#ref-sybilguard)
- SybilLimit (Yu et al., 2008) [[9]](#ref-sybillimit)
- Viswanath et al. (2010) on community-detection Sybil defense [[10]](#ref-viswanath)

---

### 6. Fan-out bursts of leaf identities

**Definition:**  
A single node suddenly registers many children in a short time window, often at or near the depth cap.

```
... ─► P (depth 9) ─┬► L1
                    ├► L2
                    ├► L3 (all within minutes)
                    └► ...
```

**Why dangerous:**  
If P is at depth 9, the children (depth 10) are at the payout cap. Any reward seeded at a child pays P and the 9 ancestors. A burst suggests automated wallet generation for farm purposes.

**Detection signals:**
- **Registration velocity**: `registrations_per_hour(parent)` spike.
- **Depth proximity**: children at depths 9–10.
- **Wallet age**: new wallets with no prior activity.
- **No qualifying events** from burst leaves.

**Action:** **Flag for review**; delay payout eligibility for burst leaves until qualifying action.

**Literature:**
- SynchroTrap (Cao et al., 2014) on synchronized account creation [[11]](#ref-synchrotrap)

---

### 7. Chains or clumps parked near the depth cap

**Definition:**  
Sybils deliberately position themselves at depths 8–10 so that legitimate downstream registrations push payouts into their controlled chain segment.

```
R ─► ... (honest, depth 7) ─► S8 ─► S9 ─► S10 ─► (victim leaves)
                              └───── Sybil ─────┘
```

**Why dangerous:**  
Under 0.6^k with 10-cap, levels 8–9 still receive ~1.8% combined. An attacker parked at these depths collects a small but reliable fraction of all downstream payouts. At scale (millions of events), this becomes significant.

**Detection signals:**
- **Depth concentration**: disproportionate node count at depths 8–10.
- **Thin connectivity**: these nodes have few siblings, one child each.
- **Funding graph ties** to known Sybils.

**Action:** **Down-weight** or **flag**; monitor payout concentration at deep levels.

**Literature:**
- Babaioff et al. (2012) on depth-capped reward schemes [[12]](#ref-babaioff)

---

### 8. Cycles and reciprocal / self-referral via multiple identities

**Definition:**  
The on-chain tree forbids literal cycles (edges are append-only, no re-registration). However, **identity-level cycles** occur when the same entity controls nodes A and B, and A refers B in group G1 while B refers A in group G2, or A→B→C→A-controlled paths funnel payouts back.

```
Identity-level cycle:
    [Alice] ──(wallet A)──► [Alice] (wallet B)
        ▲                        │
        └────────────────────────┘
        (same person, different wallets)
```

**Why dangerous:**  
Self-referral extracts rewards from the protocol without creating real network growth. The attacker triggers rewards for "referring themselves."

**Detection signals:**
- **Funding graph cycles**: wallet W1 funded W2, which funded W3, which funded W1.
- **Cross-group referral inversion**: A refers B in G1, B refers A in G2.
- **KYC / identity linkage** (off-chain).
- **IP / device correlation**.

**Action:** **Flag for review**; skiplist both nodes if confirmed.

**Literature:**
- Emek et al. (2011) on false-name manipulation [[2]](#ref-emek)
- Drucker & Fleischer (2012) on collusion-proof mechanisms [[3]](#ref-drucker)

---

### 9. Synchronized / lockstep temporal patterns

**Definition:**  
Groups of nodes perform registrations and/or trigger reward events at the same time, suggesting bot coordination.

**Why dangerous:**  
Lockstep behavior is a strong indicator of automated Sybil farms. Even if individual topology looks normal, temporal correlation reveals a common controller.

**Detection signals:**
- **Action time clustering**: Kolmogorov–Smirnov test vs. uniform distribution.
- **Inter-event time regularity**: low variance in registration intervals.
- **Shared transaction nonces / gas prices** (on-chain forensics).

**Action:** **Flag for review**; quarantine pending investigation.

**Literature:**
- CopyCatch (Beutel et al., 2013) [[7]](#ref-copycatch)
- SynchroTrap (Cao et al., 2014) [[11]](#ref-synchrotrap)

---

### 10. Wash settlement and circular value flow

**Definition:**  
The payer and one or more recipients in a `rewardRoots` call are the same beneficial owner, or tokens immediately flow back to the payer.

```
Payer ─► [ReferralGraph.rewardRoots] ─► Recipient1 (payer's wallet)
                                      └► Recipient2 (payer's friend)
                                              │
                                              └───► back to Payer
```

**Why dangerous:**  
Wash trading inflates payout volume metrics without real economic activity. It can be used to farm "top referrer" leaderboards or misrepresent protocol traction.

**Detection signals:**
- **Token flow graph**: payer receives tokens from recipients within N blocks.
- **Same funding source** for payer and recipients.
- **Volume spikes** uncorrelated with product activity.

**Action:** **Flag for review**; exclude from public metrics; potential skiplist.

**Literature:**
- Liu & Zhu (2022) on airdrop Sybil behavior [[13]](#ref-liu)

---

### 11. Seed / root remainder capture

**Definition:**  
Since the geometric split sends the **remainder to index 0** (seed), an attacker controlling the seed extracts rounding benefits and the largest share on every payout.

**Why dangerous:**  
Early tree position is immutable in ReferralGraph. If an attacker becomes the root or near-root through registration manipulation or oracle compromise, they perpetually capture ~40% of all downstream rewards.

**Detection signals:**
- **Payout Gini coefficient**: top 1% of nodes capture > 50% of total paid.
- **Root wallet age / activity**: suspicious if new wallet with no prior history.
- **Oracle audit trail**: verify legitimate first registration.

**Action:** **Audit oracle controls**; consider re-registration or group migration if root compromised.

**Literature:**
- Pickard et al. (2011) on recursive incentive mechanisms and early-mover advantage [[14]](#ref-pickard)

---

### 12. Pyramid optics shapes (deep and narrow vs. healthy branching)

**Definition:**  
A tree that is very deep relative to its width, resembling an inverted pyramid or needle. Even if not technically fraudulent, such shapes raise regulatory and reputational concerns.

```
"Pyramid" optics:          Healthy branching:
        ●                        ●
        │                      / | \
        ●                     ●  ●  ●
        │                    /|  |  |\
        ●                   ● ● ● ● ● ●
        │                   ...
        ● (depth >> width)
```

**Why dangerous:**  
Regulators and journalists may mischaracterize a deep, narrow tree as a "pyramid scheme" regardless of actual payout mechanics. The FTC's guidance focuses on recruitment-heavy structures [[15]](#ref-ftc).

**Detection signals:**
- **Depth/width ratio**: `max_depth / sqrt(size)` >> 1.
- **Branching entropy**: low Shannon entropy of child counts.
- **Few leaves relative to internal nodes**.

**Action:** **Highlight** in dashboards; provide context for compliance review.

**Literature:**
- Vander Nat & Keep (2002) on pyramid vs. MLM classification [[16]](#ref-vandernat)

---

## Healthy reference shapes and baseline metrics

### What "healthy" looks like

A well-functioning referral tree has:
1. **Balanced branching**: mean branching factor ~2–5 across levels.
2. **Shallow depth**: most users within 3–5 hops of the root.
3. **Active leaves**: high ratio of leaves triggering qualifying events.
4. **Distributed payouts**: Gini < 0.6 for cumulative rewards.
5. **Organic growth**: registration velocity correlates with external marketing, not Sybil bursts.

```
Healthy example:
            R
         /  |  \
        A   B   C
       /|   |   |\
      D E   F   G H
     /|  \     / | \
    ...  ...  ...
```

### Baseline metrics for the indexer

| Metric | Healthy range | Suspicious range |
|--------|---------------|------------------|
| Mean branching factor | 2–5 | < 1.2 or > 50 |
| Median depth | 3–5 | > 8 |
| Depth / √(size) ratio | < 0.5 | > 1.5 |
| Payout Gini coefficient | 0.3–0.5 | > 0.7 |
| Leaf activation rate | > 30% | < 5% |
| Registration velocity spike | < 5x weekly mean | > 20x |
| Cross-funding density | < 0.1 | > 0.5 |
| Top-10% payout share | < 50% | > 80% |

### Generation payout histogram (healthy)

For a balanced tree with depth 5 and branching factor 3:

| Level | Nodes | Expected payout share (each) |
|-------|-------|------------------------------|
| 0 | 1 | 43.4% × (1/1) = 43.4% |
| 1 | 3 | 26.0% × (1/3) = 8.7% each |
| 2 | 9 | 15.6% × (1/9) = 1.7% each |
| 3 | 27 | 9.4% × (1/27) = 0.35% each |
| 4 | 81 | 5.6% × (1/81) = 0.07% each |

The distribution fans out: many nodes receive small amounts, few receive large amounts. A *healthy* Gini for such a tree is ~0.4–0.5.

---

## Summary table: Topology → Signal → Action

| # | Topology | Primary signal | Secondary signals | Action |
|---|----------|----------------|-------------------|--------|
| 1 | Long single chains | Path length with fanout ≤ 1 | Funding correlation, timing | Flag / auto-skiplist if ≥ 7 |
| 2 | Caterpillars / brooms | Spine-to-leaf ratio | Depth vs. width disparity | Down-weight spine |
| 3 | Star / mega-recruiter | Out-degree > 99th percentile | Timing burst, low grandchildren | Flag; rate-limit registrations |
| 4 | Dense clumps / cliques | Funding graph density | Withdrawal clustering | Flag; investigate off-chain |
| 5 | Sparse-cut Sybil region | Conductance / SybilRank | Random-walk escape probability | Block/skiplist attack edges |
| 6 | Fan-out bursts at leaves | Registration velocity spike | Depth proximity, wallet age | Flag; delay payout eligibility |
| 7 | Depth-cap parking | Node concentration at 8–10 | Thin connectivity | Down-weight / flag |
| 8 | Identity-level cycles | Funding graph cycles | Cross-group inversion | Flag; skiplist if confirmed |
| 9 | Lockstep temporal patterns | Action time clustering | Inter-event regularity | Flag; quarantine |
| 10 | Wash settlement | Token flow loops | Same funding source | Flag; exclude from metrics |
| 11 | Root remainder capture | Payout Gini > 0.7 | Root wallet anomalies | Audit oracle; consider migration |
| 12 | Pyramid optics | Depth/width ratio >> 1 | Low branching entropy | Highlight for compliance |

---

## Open questions

1. **Threshold calibration**: What are the right percentile cutoffs for branching factor, registration velocity, and Gini before flagging? Requires empirical calibration per group.

2. **Cross-group intelligence**: Should Sybil signals from one `groupId` automatically skiplist the same wallets in other groups? Privacy and fairness trade-offs apply.

3. **Oracle trust model**: If the oracle is compromised, all topology guarantees are void. How should the indexer detect oracle misbehavior (e.g., burst `batchRegister` from a single IP)?

4. **Sybil-proof mechanism alternatives**: Drucker & Fleischer [[3]](#ref-drucker) and Zhang & Tang (2023) [[17]](#ref-zhang) propose split-proof / Sybil-proof transforms. Should referralTree adopt a hybrid calculator that reduces chain-stuffing incentives?

5. **Off-chain data access**: Many signals (IP, device, funding source) require off-chain data. What is the minimal on-chain indexer, and what should remain in the oracle's private pipeline?

6. **Legal classification**: Does flagging "pyramid optics" create liability, or reduce it by demonstrating diligence? Consult counsel.

7. **Adversarial adaptation**: Once attackers know the detection heuristics, they will add noise (fake branching, staggered timing). What second-order defenses exist?

8. **Incentive for reporters**: Should the protocol reward users who report suspicious topologies? Risk of false positives and gaming the reporter mechanism.

---

## References

<a id="ref-douceur"></a>
[1] Douceur, J.R. (2002). "The Sybil Attack." *IPTPS 2002*, LNCS 2429, pp. 251–260.  
https://doi.org/10.1007/3-540-45748-8_24

<a id="ref-emek"></a>
[2] Emek, Y., Karidi, R., Tennenholtz, M., & Zohar, A. (2011). "Mechanisms for Multi-Level Marketing." *EC '11*, pp. 209–218.  
https://doi.org/10.1145/1993574.1993606

<a id="ref-drucker"></a>
[3] Drucker, F. & Fleischer, L. (2012). "Simpler Sybil-Proof Mechanisms for Multi-Level Marketing." *EC '12*, pp. 441–458.  
https://doi.org/10.1145/2229012.2229046

<a id="ref-sybilrank"></a>
[4] Cao, Q., Sirivianos, M., Yang, X., & Pregueiro, T. (2012). "Aiding the Detection of Fake Accounts in Large Scale Social Online Services." *NSDI '12*.  
https://www.usenix.org/conference/nsdi12/technical-sessions/presentation/cao

<a id="ref-kumar"></a>
[5] Kumar, V., Petersen, J.A., & Leone, R.P. (2010). "Driving Profitability by Encouraging Customer Referrals." *Journal of Marketing*, 74(5), pp. 1–17.  
https://doi.org/10.1509/jmkg.74.5.001

<a id="ref-fraudar"></a>
[6] Hooi, B., Song, H.A., Beutel, A., Shah, N., Shin, K., & Faloutsos, C. (2016). "FRAUDAR: Bounding Graph Fraud in the Face of Camouflage." *KDD '16*, pp. 895–904.  
https://doi.org/10.1145/2939672.2939747

<a id="ref-copycatch"></a>
[7] Beutel, A., Xu, W., Guruswami, V., Palow, C., & Faloutsos, C. (2013). "CopyCatch: Stopping Group Attacks by Spotting Lockstep Behavior in Social Networks." *WWW '13*, pp. 119–130.  
https://doi.org/10.1145/2488388.2488400

<a id="ref-sybilguard"></a>
[8] Yu, H., Kaminsky, M., Gibbons, P.B., & Flaxman, A. (2006). "SybilGuard: Defending Against Sybil Attacks via Social Networks." *SIGCOMM '06*, pp. 267–278.  
https://doi.org/10.1145/1159913.1159945

<a id="ref-sybillimit"></a>
[9] Yu, H., Gibbons, P.B., Kaminsky, M., & Xiao, F. (2008). "SybilLimit: A Near-Optimal Social Network Defense against Sybil Attacks." *IEEE S&P '08*, pp. 3–17.  
https://doi.org/10.1109/SP.2008.13

<a id="ref-viswanath"></a>
[10] Viswanath, B., Post, A., Gummadi, K.P., & Mislove, A. (2010). "An Analysis of Social Network-Based Sybil Defenses." *SIGCOMM '10*, pp. 363–374.  
https://doi.org/10.1145/1851182.1851226

<a id="ref-synchrotrap"></a>
[11] Cao, Q., Yang, X., Yu, J., & Palow, C. (2014). "Uncovering Large Groups of Active Malicious Accounts in Online Social Networks." *CCS '14*, pp. 477–488.  
https://doi.org/10.1145/2660267.2660269

<a id="ref-babaioff"></a>
[12] Babaioff, M., Dobzinski, S., Oren, S., & Zohar, A. (2012). "On Bitcoin and Red Balloons." *EC '12*, pp. 56–73.  
https://doi.org/10.1145/2229012.2229022

<a id="ref-liu"></a>
[13] Liu, M. & Zhu, Z. (2022). "Sybil Attacks on Airdrops." *arXiv:2209.04603*.  
https://arxiv.org/abs/2209.04603

<a id="ref-pickard"></a>
[14] Pickard, G., Pan, W., Rahwan, I., Cebrian, M., Crane, R., Madan, A., & Pentland, A. (2011). "Time-Critical Social Mobilization." *Science*, 334(6055), pp. 509–512.  
https://doi.org/10.1126/science.1205869

<a id="ref-ftc"></a>
[15] FTC Bureau of Consumer Protection. "Multilevel Marketing." *Business Guidance*.  
https://www.ftc.gov/business-guidance/resources/multilevel-marketing

<a id="ref-vandernat"></a>
[16] Vander Nat, P.J. & Keep, W.W. (2002). "Marketing Fraud: An Approach for Differentiating Multilevel Marketing from Pyramid Schemes." *Journal of Public Policy & Marketing*, 21(1), pp. 139–151.  
https://doi.org/10.1509/jppm.21.1.139.17603

<a id="ref-zhang"></a>
[17] Zhang, K. & Tang, P. (2023). "Sybil-Proof Diffusion Mechanism." *AAAI '23*.  
https://doi.org/10.1609/aaai.v37i5.25730

<a id="ref-kleinberg"></a>
[18] Kleinberg, J. & Raghavan, P. (2005). "Query Incentive Networks." *FOCS '05*, pp. 132–141.  
https://doi.org/10.1109/SFCS.2005.63

<a id="ref-sybilinfer"></a>
[19] Danezis, G. & Mittal, P. (2009). "SybilInfer: Detecting Sybil Nodes using Social Networks." *NDSS '09*.  
https://www.ndss-symposium.org/ndss2009/sybillnfer-detecting-sybil-nodes-using-social-networks/

<a id="ref-milo"></a>
[20] Milo, R., Shen-Orr, S., Itzkovitz, S., Kashtan, N., Chklovskii, D., & Alon, U. (2002). "Network Motifs: Simple Building Blocks of Complex Networks." *Science*, 298(5594), pp. 824–827.  
https://doi.org/10.1126/science.298.5594.824

<a id="ref-lv"></a>
[21] Lv, Y. & Moscibroda, T. (2013). "Fair and Resilient Incentive Tree Mechanisms." *EC '13*, pp. 230–239.  
https://doi.org/10.1145/2484239.2484252

---

## Related documents

- [abuse-mitigation.md](../abuse-mitigation.md) — Contract-level controls and integrator policy
- [README](../../README.md) — System overview and payout mechanics

---

*This document is a living reference. Update as detection heuristics mature and new attack patterns emerge.*
