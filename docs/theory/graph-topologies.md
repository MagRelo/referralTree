# Dangerous and Suspicious Graph Topologies for Referral Tree Indexing

**Date:** 2026-10-01 (payout math re-audited 2026-10-12 against `main` @ `800da1d`)  
**Purpose:** Catalog graph shapes the off-chain indexer / graph-maintenance service should detect, avoid, or highlight in ReferralGraph trees. Ties to `docs/abuse-mitigation.md` (contracts = invariants; app/oracle = quality) and the graph-maintenance-service concept.

---

## Design context

**System recap** (verified against current `main`, commit `800da1d`, which includes `1c99267`):

- `ReferralGraph` stores per-`groupId` referral trees, oracle-gated registration, skiplist management, and EIP-712-signed `rewardRoots` / `rewardLeaf` payouts.
- `RewardCalculator` splits a `rewardRoots` pool across **up to 10 recipients** with a **hard-coded basis-point weight table that approximates 0.6^k decay** (see below). It is not configurable per group or per app: there is one global `rewardCalculator` address, swappable only by the contract owner via `setRewardCalculator` (`ReferralGraph.sol:354-358`), and it applies to every group.
- `rewardLeaf` does **not** use `RewardCalculator` at all: it pays 100% of the net amount to `user`.
- Tokens are pulled from `msg.sender` in the same transaction; the graph keeps no balance.
- A global protocol fee (default 0, capped at 10%) is deducted from `totalAmount` before any split.

**Design thesis:** Incentive compatibility after *transaction costs* (Coasean friction—search, verification, enforcement, coordination—not gas). The indexer exists to **lower verification and enforcement costs** by flagging bad shapes before they extract value.

**Legal framing:** The 10-recipient cap is an **engineering and optics choice**, not a legal safe harbor. Legal weight rests on settlement-tied pay, no join fees, and no forced matrix. Shape detection is a compliance and economics tool, not a legal shield.

---

## Payout mechanics reference (current code)

### Constants

```solidity
// src/core/ReferralGraph.sol:20-26
uint256 public constant MAX_PAYOUT_LEVELS = 10;
uint256 public constant BPS_DENOMINATOR = 10_000;
uint256 public constant MAX_FEE_BPS = 1_000;          // 10% hard cap
address public constant REFERRAL_ROOT = address(0x0000000000000000000000000000000000000001);
```

### Weights (`src/core/RewardCalculator.sol:28-51`)

```solidity
if (numRecipients > 10) { numRecipients = 10; }
// Geometric weights for 0.6 decay ratio (basis points)
uint256[10] memory weights = [uint256(10000), 6000, 3600, 2160, 1296, 777, 466, 279, 167, 100];
uint256[11] memory cumSums = [uint256(0), 10000, 16000, 19600, 21760, 23056, 23833, 24299, 24578, 24745, 24845];
...
amounts[i] = totalReward * weights[i] / totalSum;   // totalSum = cumSums[numRecipients]
...
amounts[0] += remainder;                            // integer-division dust to index 0
```

So the ratio **is** 0.6, hard-coded (not a parameter, not a default, not per-group). The weights are `floor(10000 * 0.6^k)` (e.g. 0.6^5 = 0.07776 → 777, 0.6^9 = 0.01008 → 100), so the effective decay is 0.6 for the first five steps and very slightly below it afterwards. Shares are **normalized by the number of actual recipients `n`**: the pool is always fully distributed across whoever is in the chain. The "remainder" is rounding dust of at most `n-1` wei, credited to index 0.

`ReferralGraph.rewardRoots` additionally checks that the calculator returns exactly `chain.length` amounts summing to `distributedAmount`, else `InvalidSplit` (`ReferralGraph.sol:396-402`).

### `rewardRoots(user, …)` (`ReferralGraph.sol:370-413`)

```solidity
uint256 protocolFee = _protocolFee(totalAmount);                 // :388
uint256 distributedAmount = totalAmount - protocolFee;           // :389
// Start above `user`. rewardLeaf pays the trigger; this call pays ancestors only,
address[] memory chain = this.getPayoutAncestors(user, groupId, MAX_PAYOUT_LEVELS); // :393
if (chain.length == 0) revert EmptyPayoutChain();                // :394
uint256[] memory amounts = rewardCalculator.calculateRewards(distributedAmount, chain.length); // :396
```

`getPayoutAncestors` (`ReferralGraph.sol:151-178`) starts at `_referrers[groupId][user]` (the trigger's referrer, **not** the trigger), walks up, **skips skiplisted addresses without consuming a slot**, and stops at `REFERRAL_ROOT` or after 10 *paid* recipients:

```solidity
address current = _referrers[groupId][user];
while (current != address(0) && current != REFERRAL_ROOT && count < maxLevels) {
    if (!_skiplisted[groupId][current]) { ancestors[count] = current; count++; }
    current = _referrers[groupId][current];
}
```

Commit `1c99267` (Oct 3, 2026) changed line 393 from `getPayoutChain` (which starts at `user`, `ReferralGraph.sol:181-205`) to `getPayoutAncestors`. Before that commit the trigger user was index 0 and took the largest share; **since that commit the trigger user receives nothing from `rewardRoots`**. `getPayoutChain` still exists as a seed-inclusive view but no payout function uses it.

Consequences:
- **Index 0 = the trigger's nearest non-skiplisted ancestor** (normally the direct referrer). Index k = the (k+1)-th non-skiplisted ancestor.
- `REFERRAL_ROOT` is never paid and ends the walk. A user registered directly under `REFERRAL_ROOT` (or whose ancestors are all skiplisted) makes `rewardRoots` revert with `EmptyPayoutChain`.
- Because skiplisted nodes do not consume a slot, skiplisting an ancestor shifts every higher ancestor one index closer (bigger share) and can pull an 11th ancestor into the paid set.
- There is **no absolute depth cap** on the tree (`_register`, `ReferralGraph.sol:269-287`, has none). The 10 cap is **relative to the trigger**: only the 10 nearest payable ancestors are paid; anyone further up gets nothing from that event.

### `rewardLeaf(user, …)` (`ReferralGraph.sol:416-438`)

```solidity
uint256 protocolFee = _protocolFee(totalAmount);
uint256 distributedAmount = totalAmount - protocolFee;
_payProtocolFee(groupId, rewardId, token, protocolFee);
ERC20(token).safeTransferFrom(msg.sender, user, distributedAmount);
```

100% of the net amount to `user`. No chain walk, no calculator, no skiplist check (a skiplisted user can still be paid by an explicitly signed `rewardLeaf`). `rewardRoots` and `rewardLeaf` share one `rewardId` namespace per group, but they are **separate calls with separate amounts** chosen by the oracle/app; nothing on-chain links a leaf reward to a roots reward or fixes their ratio.

### Protocol fee (`ReferralGraph.sol:361-367, 475-481, 577-581`)

`fee = totalAmount * feeBps / 10000` (rounded down), `feeBps ≤ 1000`, default 0, global (not per group), sent to `feeRecipient`. All percentages below are of the **net** `distributedAmount`.

### Worked examples (`rewardRoots`, share of net amount)

`n` = number of payable (non-skiplisted) ancestors above the trigger, capped at 10. Index 0 = nearest ancestor.

| n | Who is paid | Shares by index (0 → n-1) | Trigger user |
|---|-------------|---------------------------|-------------:|
| 0 | nobody — reverts `EmptyPayoutChain` | — | 0% |
| 1 | direct referrer | 100% | 0% |
| 2 | referrer, grand-referrer | 62.50%, 37.50% | 0% |
| 3 | 3 ancestors | 51.02%, 30.61%, 18.37% | 0% |
| 5 | 5 ancestors | 43.37%, 26.02%, 15.61%, 9.37%, 5.62% | 0% |
| 10 | 10 ancestors | 40.25%, 24.15%, 14.49%, 8.69%, 5.22%, 3.13%, 1.88%, 1.12%, 0.67%, 0.40% | 0% |
| >10 | nearest 10 only; 11th+ get **0** | same as n=10 | 0% |

Example with 1,000 net tokens, n=10: 402.49, 241.50, 144.90, 86.94, 52.16, 31.27, 18.76, 11.23, 6.72, 4.02 (dust to index 0).

### Worked examples (`rewardLeaf`)

| Chain depth above trigger | Who is paid |
|---|---|
| any (0, 1, 2, 3, 5, 10, >10) | trigger user: 100% of net; ancestors: 0% |

**Key attacker incentives (current code):**
1. **Own the nearest ancestors of honest users.** The direct referrer slot alone is worth 40.25%–100% of every `rewardRoots` payout, depending on `n`.
2. **Own every ancestor above an honest user ⇒ 100% of that user's `rewardRoots` payouts.** The honest trigger keeps nothing from `rewardRoots`; there is no "honest user keeps ~40%" floor.
3. **Short chains concentrate value.** Because shares renormalize to `n`, a Sybil sitting directly under `REFERRAL_ROOT` as the only ancestor gets 100%; adding more Sybil ancestors does not increase the attacker's total (already 100%), it only spreads it.
4. **Self-referral pays twice.** Attacker wallet A refers own wallet B: `rewardRoots(B)` pays A (100% if A is directly under the root) and `rewardLeaf(B)` pays B.
5. **Oracle compromise** is total: the oracle chooses trigger, amounts, and which of the two functions to call.

---

## Topology catalog

Each entry contains:
- **Definition** with ASCII or Mermaid sketch
- **Why dangerous** under the current payout rule (`rewardRoots` pays only ancestors above the trigger, hard-coded ~0.6 weights, nearest 10 payable ancestors)
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
An attacker creates a chain of Sybil wallets and gets honest users registered at the bottom of it. Every `rewardRoots` payout triggered by those honest users goes **entirely** to ancestors, i.e. to the attacker.

**Quantified example** (`getPayoutAncestors` + `RewardCalculator` weights):  
A is registered under `REFERRAL_ROOT`; the attacker controls A and 9 Sybils B–J in a single chain; legitimate user K registers under J.
- `rewardRoots(K, …)` pays `[J, I, H, G, F, E, D, C, B, A]` (n=10; A is the 10th ancestor and **is** paid; `REFERRAL_ROOT` is not).
- J (direct referrer, index 0): 40.25%; I: 24.15%; … A: 0.40%.
- Attacker total: **100%**. K receives **0%** from `rewardRoots` (K is only paid if the app separately calls `rewardLeaf(K, …)`).

The attacker does not even need 10 wallets: a single Sybil J directly under `REFERRAL_ROOT` with K under it also captures **100%** (n=1). Chain length only changes how the attacker's 100% is spread across their own wallets, and lets the chain look "organic." What matters is owning *all* payable ancestors of honest triggers. If only the top part of the chain is Sybil (honest referrers nearer K), the attacker gets the tail shares instead (e.g. honest J and I, Sybil H–A at n=10: 35.60%).

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
The spine sits above every leg/leaf, so it collects all `rewardRoots` value from them. A single attacker controlling the spine monetizes every leaf registration without contributing to recruitment quality. The caterpillar looks "bushy" superficially (many nodes) but concentrates value at the spine.

**Quantified example (broom)** (`getPayoutAncestors` + `RewardCalculator`):  
Attacker controls A, B, C, D (A registered under `REFERRAL_ROOT`); 100 honest leaves register under D.
- `rewardRoots(leaf, …)` pays `[D, C, B, A]` (n=4): D 45.96%, C 27.57%, B 16.54%, A 9.93%.
- Attacker total: **100%** of every leaf's `rewardRoots` payout; the leaf gets **0%** from it.
- If A instead hangs under an honest node R (n=5), R gets 5.62% and the attacker 94.38%.

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
When a child C_i triggers `rewardRoots`, A is index 0, the largest share. If A is directly under `REFERRAL_ROOT`, the chain is `[A]` and **A gets 100%**. If A is under an honest node R (itself under the root), the chain is `[A, R]`: A 62.5%, R 37.5%. With more ancestors above A, A's share falls toward 40.25% (n=10). The child receives nothing from `rewardRoots`.

A mega-recruiter therefore collects **40.25%–100% of every `rewardRoots` payout triggered by each direct child**, multiplied by the number of children. If A farms fake children whose events the app rewards, A extracts most of the pool (and the fake children can also be paid via `rewardLeaf`). Even if A is honest, concentration creates single points of failure for network health and regulatory optics.

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
Sybils receive rewards whenever honest users downstream of the Sybil region trigger payouts. The sparse cut makes the cluster easy to *identify*, but removal is per address: `setSkiplisted` only drops that one address from future ancestor walks (`getPayoutAncestors`, `ReferralGraph.sol:164-169`); it does not cut tree edges, and Sybils above or below it keep being paid. Skiplisting a node also shifts higher ancestors one index closer (larger shares) and can pull an extra ancestor into the 10 paid slots. To neutralize a Sybil region, skiplist **every** Sybil address in it.

**Detection signals:**
- **Conductance / normalized cut** of candidate subgraphs.
- **Random walk escape probability**: short walks from a trusted seed rarely land in the suspect region.
- **SybilRank / SybilLimit scores** below threshold.

**Action:** **Block/skiplist** every address in the Sybil region (not just the boundary node) and quarantine the cluster.

**Literature:**
- SybilGuard (Yu et al., 2006) [[8]](#ref-sybilguard)
- SybilLimit (Yu et al., 2008) [[9]](#ref-sybillimit)
- Viswanath et al. (2010) on community-detection Sybil defense [[10]](#ref-viswanath)

---

### 6. Fan-out bursts of leaf identities

**Definition:**  
A single node suddenly registers many children in a short time window.

```
... ─► P ─┬► L1
                    ├► L2
                    ├► L3 (all within minutes)
                    └► ...
```

**Why dangerous:**  
Any `rewardRoots` seeded at a burst leaf pays P as index 0 (40.25%–100%, depending on how many payable ancestors sit above P) plus up to 9 ancestors above P; absolute depth does not matter because the 10 cap is relative to the trigger. If the leaves are Sybils the app can also pay them directly via `rewardLeaf`. A burst suggests automated wallet generation for farm purposes.

**Detection signals:**
- **Registration velocity**: `registrations_per_hour(parent)` spike.
- **Wallet age**: new wallets with no prior activity.
- **No qualifying events** from burst leaves.

**Action:** **Flag for review**; delay payout eligibility for burst leaves until qualifying action.

**Literature:**
- SynchroTrap (Cao et al., 2014) on synchronized account creation [[11]](#ref-synchrotrap)

---

### 7. Distance-to-trigger positioning (formerly "depth-cap parking")

**Correction:** the earlier version assumed an absolute depth cap where Sybils "parked at depths 8–10" collect the last positions. That is not how the code works. There is no absolute tree depth limit (`_register`, `ReferralGraph.sol:269-287`). The cap is **relative**: `rewardRoots` pays the 10 nearest non-skiplisted ancestors *of the trigger* (`MAX_PAYOUT_LEVELS = 10`, `getPayoutAncestors`). A node's share depends on its distance above each trigger, not its absolute depth.

**Definition:**  
Sybils position themselves *directly above* where honest users join (e.g. as the referrer handed out in links), rather than deep in the tree.

```
R ─► ... (honest) ─► S1 ─► S2 ─► (victim leaves)
                     └ Sybil ┘
```

**Why dangerous:**  
Being 1 step above a trigger is worth 40.25%–100%; 2 steps, 24.15%–37.5%. By contrast, ancestors 9 and 10 steps above a trigger (n=10) get only 0.67% + 0.40% = **1.07%** combined, and anyone 11+ payable steps above gets **0**. So the profitable "parking spot" is immediately above honest joiners, not near some depth cap. Long Sybil chains *below* honest nodes push those honest ancestors out of the paid window entirely once there are ≥10 Sybils between them and the trigger.

**Detection signals:**
- **Referrer of many fresh honest-looking accounts** that itself has thin, young, Sybil-correlated ancestry.
- **Thin connectivity**: Sybil segment nodes have few siblings, one child each.
- **Funding graph ties** to known Sybils.
- **Per-address cumulative `RootsRewarded` share by index** (index 0 receipts dominate).

**Action:** **Down-weight** or **flag**; monitor per-address index-0 receipts.

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
Self-referral extracts rewards without creating real network growth. On-chain `SelfReferralNotAllowed` only blocks `referrer == user` for the same address (`ReferralGraph.sol:272`). With two wallets, A refers B: every reward for B's activity pays A via `rewardRoots(B)` (100% if A is directly under `REFERRAL_ROOT`) and can pay B via `rewardLeaf(B)`, so the attacker collects both sides.

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
The payer (`msg.sender`, who must equal the signed `payer`) and one or more recipients of a `rewardRoots` or `rewardLeaf` call are the same beneficial owner, or tokens immediately flow back to the payer.

```
Payer ─► [ReferralGraph.rewardRoots] ─► Ancestor1 (payer's wallet)
                                      └► Ancestor2 (payer's friend)
                                              │
                                              └───► back to Payer
```

**Why dangerous:**  
Wash settlement inflates `RootsRewarded` / `LeafRewarded` volume without real economic activity. Net cost to the washer is only the protocol fee (0 by default, ≤10%) plus gas, because the full `distributedAmount` goes to their own ancestor wallets. It can be used to farm "top referrer" leaderboards or misrepresent protocol traction.

**Detection signals:**
- **Token flow graph**: payer receives tokens from recipients within N blocks.
- **Same funding source** for payer and recipients.
- **Volume spikes** uncorrelated with product activity.

**Action:** **Flag for review**; exclude from public metrics; potential skiplist.

**Literature:**
- Liu & Zhu (2022) on airdrop Sybil behavior [[13]](#ref-liu)

---

### 11. Early tree position advantage (NOT "root remainder capture")

**Clarification on "remainder":**  
The `RewardCalculator.sol` remainder (lines 45–51) is **rounding dust** (at most n−1 wei), credited to index 0. Index 0 of a `rewardRoots` payout is the trigger's **nearest payable ancestor** (normally the direct referrer), not the trigger user (since `1c99267`, the trigger is never paid by `rewardRoots`) and not any "root". `REFERRAL_ROOT` is never paid: it ends the walk (`ReferralGraph.sol:164`).

**Definition:**  
Early registrants (close to `REFERRAL_ROOT`) are ancestors of many downstream users, so they appear in many `rewardRoots` payouts.

**Risk assessment: LOW to MODERATE**  
This is **by design**. Two properties of the current code limit it:
1. **Shallow trees favor early nodes heavily.** Shares renormalize to n, so a first registrant who is the only ancestor gets 100% of its children's payouts, and 37.5% of its grandchildren's payouts (as index 1 of a 2-ancestor chain).
2. **Deep trees cut early nodes off.** Once a trigger has 10+ payable ancestors nearer than the early node, the early node gets **0** from that trigger. Index 9 (10th ancestor) gets 0.40%.

The risk arises if the first registrants are Sybils or colluders, or if the oracle is compromised at group initialization and inserts attacker wallets near `REFERRAL_ROOT`.

**Quantified impact:**  
A node that is the 2nd payable ancestor (index 1) of 1,000 downstream users, each triggering one 1,000-token (net) `rewardRoots` payout:
- n=2: 37.5% → 375,000 tokens
- n=10: 24.15% → 241,500 tokens
The same node as index 0 (direct referrer) would get 402,490 (n=10) to 1,000,000 (n=1) tokens.

**Detection signals:**
- **Payout Gini coefficient**: top 1% capturing > 60% of total distributed.
- **First-registrant wallet analysis**: verify legitimate onboarding, not oracle self-dealing.
- **Time-to-first-reward**: early registrants with immediate high payouts are suspicious.

**Action:** **Highlight** for monitoring; **audit oracle controls** during group initialization. This is not blockable without replacing the global `RewardCalculator` (owner-only `setRewardCalculator`) or changing which ancestors `rewardRoots` pays.

**Literature:**
- Pickard et al. (2011) on recursive incentive mechanisms and early-mover advantage [[14]](#ref-pickard)
- Emek et al. (2011) on geometric mechanism properties [[2]](#ref-emek)

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
Regulators and journalists may mischaracterize a deep, narrow tree as a "pyramid scheme" regardless of actual payout mechanics. Under the current code, every `rewardRoots` payout flows *only upward* to recruiters (the trigger gets nothing from it), which strengthens the recruitment-reward optics; integrators should be able to show that rewards are tied to real product events and that users are paid for their own activity via `rewardLeaf`. The FTC's guidance focuses on recruitment-heavy structures [[15]](#ref-ftc).

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

### Per-payout share by chain length

Each `rewardRoots` call pays the trigger's payable ancestors only. n = number of payable ancestors (capped at 10):

| n | Index 0 (nearest ancestor) | Index 1 | Index 2+ | Trigger user |
|---|---------------------------|---------|----------|-------------:|
| 0 | reverts `EmptyPayoutChain` | — | — | 0% |
| 1 | 100% | — | — | 0% |
| 2 | 62.50% | 37.50% | — | 0% |
| 3 | 51.02% | 30.61% | 18.37% | 0% |
| 5 | 43.37% | 26.02% | 15.61%, 9.37%, 5.62% | 0% |
| 10 (and >10) | 40.25% | 24.15% | 14.49%, 8.69%, 5.22%, 3.13%, 1.88%, 1.12%, 0.67%, 0.40% | 0% |

`rewardLeaf` always pays 100% of net to the trigger and 0% to ancestors.

### Aggregate distribution in a healthy tree

For a balanced tree with 5 levels and branching factor 3 (121 nodes; top node T registered under `REFERRAL_ROOT`), if each of the 81 bottom-level leaves triggers one `rewardRoots`:
- Each payout goes to the leaf's 4 ancestors (n=4): parent 45.96%, grandparent 27.57%, great-grandparent 16.54%, T 9.93%.
- Per unit of payout per leaf: each of the 27 parents collects 3 × 45.96%, each of the 9 grandparents 9 × 27.57%, each of the 3 great-grandparents 27 × 16.54%, and T 81 × 9.93%.
- Per-node totals: T ≈ 8.04, level-2 ≈ 4.47, level-3 ≈ 2.48, level-4 ≈ 1.38, leaves = **0** from `rewardRoots` (leaves earn only via `rewardLeaf`).

The distribution concentrates upward: the 81 leaves get nothing from `rewardRoots` and value accrues to the few internal nodes. Gini over all 121 nodes is therefore high even in a "healthy" tree, so Gini thresholds must be computed over *ancestor receipts* (or combined with `rewardLeaf` receipts), not over all nodes.

---

## Summary table: Topology → Signal → Action

| # | Topology | Primary signal | Secondary signals | Action |
|---|----------|----------------|-------------------|--------|
| 1 | Long single chains (owning all ancestors ⇒ 100% of honest users' `rewardRoots`) | Path length with fanout ≤ 1 above honest joiners | Funding correlation, timing | Flag / auto-skiplist if ≥ 7 |
| 2 | Caterpillars / brooms (spine takes 100% of leaf `rewardRoots`) | Spine-to-leaf ratio | Depth vs. width disparity | Down-weight spine |
| 3 | Star / mega-recruiter | Out-degree > 99th percentile | Timing burst, low grandchildren | Flag; rate-limit registrations |
| 4 | Dense clumps / cliques | Funding graph density | Withdrawal clustering | Flag; investigate off-chain |
| 5 | Sparse-cut Sybil region | Conductance / SybilRank | Random-walk escape probability | Skiplist every Sybil address (skiplist is per address, not per edge) |
| 6 | Fan-out bursts at leaves | Registration velocity spike | Wallet age, no qualifying events | Flag; delay payout eligibility |
| 7 | Distance-to-trigger positioning | Index-0 receipts concentrated in Sybil-linked referrers | Thin connectivity | Down-weight / flag |
| 8 | Identity-level cycles | Funding graph cycles | Cross-group inversion | Flag; skiplist if confirmed |
| 9 | Lockstep temporal patterns | Action time clustering | Inter-event regularity | Flag; quarantine |
| 10 | Wash settlement | Token flow loops | Same funding source | Flag; exclude from metrics |
| 11 | Early position advantage | Ancestor-receipt Gini | First-registrant anomalies | Highlight; audit oracle init (LOW–MODERATE) |
| 12 | Pyramid optics | Depth/width ratio >> 1 | Low branching entropy | Highlight for compliance |

---

## Open questions

1. **Threshold calibration**: What are the right percentile cutoffs for branching factor, registration velocity, and Gini before flagging? Requires empirical calibration per group.

2. **Cross-group intelligence**: Should Sybil signals from one `groupId` automatically skiplist the same wallets in other groups? Privacy and fairness trade-offs apply.

3. **Oracle trust model**: If the oracle is compromised, all topology guarantees are void. How should the indexer detect oracle misbehavior (e.g., burst `batchRegister` from a single IP)?

4. **Sybil-proof mechanism alternatives**: Drucker & Fleischer [[3]](#ref-drucker) and Zhang & Tang (2023) [[17]](#ref-zhang) propose split-proof / Sybil-proof transforms. Should referralTree adopt a hybrid calculator that reduces chain-stuffing incentives? (The calculator is a single global contract swappable by the owner via `setRewardCalculator`; it cannot differ per group today.)

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
