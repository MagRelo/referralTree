# Deferral vs referralTree — One-Pager Mapping

**Date:** 2026-09-10  
**Purpose:** Map Tobias Boner's Deferral evaluator contracts onto MagRelo's ReferralGraph / RewardCalculator / app settlement / Incentive Exchange split, and spell out what to copy vs what to avoid.

**Sources:** Boner MSc thesis (UZH, 2023) [doi:10.5167/uzh-255750](https://doi.org/10.5167/uzh-255750); BRAINS paper [doi:10.1109/brains59668.2023.10316807](https://doi.org/10.1109/brains59668.2023.10316807); [dydent/Deferral](https://github.com/dydent/Deferral); [MagRelo/referralTree](https://github.com/MagRelo/referralTree); [exchange.mattlovan.dev](https://exchange.mattlovan.dev/).

---

## One-line contrast

| | **Deferral** | **referralTree v2** |
|---|---|---|
| **Question asked** | Are high-volume *on-chain payment + evaluate + pay* referral SCs feasible? | Can apps share a *non-custodial attribution graph + split math* and settle themselves? |
| **Custody** | Contract holds native/ERC20 until process completes, then `transfer`s rewards | Graph/Calculator hold **no** funds; app transfers + emits `ReferralSettlement` |
| **Tree** | Parent pointer inside per-referee `ReferralProcess` mapping, set on payment | `ReferralGraph` per `groupId`, oracle `register` / skiplist / `getPayoutChain` |
| **Split** | Multilevel: typically **equal split** among ancestors up to `maxRewardLevels` | `RewardCalculator`: **geometric 0.6**, max 10, remainder to seed |
| **Eligibility** | On-contract thresholds (quantity and/or value of payments) | App/oracle policy (+ docs/abuse-mitigation); not baked into calculator |
| **Measurement** | Offline gas/fiat eval + [visualizations-deferral](https://github.com/dydent/visualizations-deferral) | Live **Incentive Exchange** indexing settlements for agents |

---

## Deferral's five evaluator families → your stack

Deferral ships a **ladder of complexity**. Each step adds evaluation/storage/payout logic *into the same custodial contract*. referralTree **factorizes** those concerns.

### 1. Referral Payment Transmitter
**What it does:** Simplest path. User sends exact native `paymentAmount` with a `_referrerAddress`; contract forwards payment to company `receiver` and pays a fixed/portion **referral reward to the direct referrer** on that tx. Ownable (V1) → upgradeable (V2/V3).

**Maps to:** Thin slice of **app settlement + single-level affiliate** (LooksRare-ish), not your multilevel graph.

**Lesson:** Direct, immediate reward is cheap and clear. No tree walk. If a `groupId` only needs 1-hop fee share, don't force geometric-10.

### 2. Referral Payment Quantity Evaluator
**What it does:** Tracks how many referral payments a referee has made (`refereeProcessMapping` → `ReferralProcess`). Completes when `paymentsQuantity` exceeds `paymentsQuantityThreshold`, then distributes.

**Maps to:** **Eligibility / qualifying action** — the thing your oracle or app decides *before* or *instead of* treating every wallet connect as referable. Not part of `RewardCalculator`.

**Lesson:** Separate "did they qualify?" from "how do we split?". Deferral couples them on-chain; you can keep quantity rules off-graph and only `register` / settle when qualified.

### 3. Referral Payment Value Evaluator
**What it does:** Same process struct pattern, but completion is driven by **cumulative payment value** vs `paymentsValueThreshold` (with V1→V3 implementation cleanup).

**Maps to:** Again **eligibility** (volume-based), analogous to "only settle referral fee from real protocol volume."

**Lesson:** Value thresholds fight empty Sybil payments better than quantity alone — but gas on every payment still taxes small-ticket use cases (their $20 sub vs $50 gas vignette).

### 4. Referral Payment Multilevel Rewards (native)
**What it does:** Combines quantity **and** value thresholds. On complete, walks **parent chain** (`getAllParentReferrerAddresses`), caps depth with `maxRewardLevels`, and pays referee + ancestors. V2: total reward from payment volume × `%`; referrer pool **split equally** across eligible parents; push `transfer`s in the completion tx.

**Maps to:** Closest Deferral cousin to **ReferralGraph + payout**, but:
- Tree edges created by payment flow (not oracle batch register)
- Split ≠ geometric (equal among levels in the V2 distribute path they document)
- **Contract custodial push** on complete → this is the family where **later users / deeper chains raise completion gas** (V1 multilevel called out in conclusions)

**Lesson for you:** You already dodged their main multilevel cost trap by not doing N ancestor transfers inside the shared SC. Keep `getPayoutChain` + app loop. If you ever add an optional "helper distributor," cap depth and prefer pull/claim.

### 5. Multilevel Token Rewards (ERC20)
**What it does:** Same multilevel evaluate/distribute logic as (4), but payments and rewards in a fixed ERC20 (`token` immutable-ish; amount via `_paymentValue` because ERC20 value isn't `msg.value`).

**Maps to:** Your world already assumes **app-chosen ERC20** (or native) at settlement time; Exchange indexes `token` on `ReferralSettlement`.

**Lesson:** Token vs native is an integration detail; don't bake a single reward asset into the graph. You're ahead here.

---

## Side-by-side: who owns which layer

```
Deferral (monolith per evaluator)          referralTree + Exchange
---------------------------------          --------------------------
Payment ingest + custody          →        App (contest / protocol / agent flow)
Process thresholds (qty/value)    →        App / oracle eligibility policy
Parent pointer / tree             →        ReferralGraph (groupId, skiplist)
Ancestor walk                     →        getPayoutChain(user, groupId, max)
Split math                        →        RewardCalculator (geometric table)
Push rewards on complete          →        App transfers (same tx as event)
Gas/fiat research notebooks       →        Incentive Exchange live index
Sybil / abuse                     →        Mostly undocumented in Deferral
                                           eval; you: abuse-mitigation.md +
                                           skiplist + (optional) SP calcs
```

---

## What to copy from Deferral

1. **Publish cost curves** — Their best artifact is honest gas×volume×chain×fiat analysis. Exchange should keep doing the product version: depth, Gini, paid-out, effective ROI after gas.
2. **Laddered complexity** — Transmitter → thresholds → multilevel. Offer `groupId` presets: 1-level fee share, shallow geometric, full 0.6/10 — don't force every integrator into deep MLM.
3. **Depth caps on payout walks** — Their `maxRewardLevels` ↔ your max 10. Document that caps are gas/UX, **not** Sybil-proofness.
4. **Open blueprint ethos** — Tests, scripts, visualizations as first-class. Your Mesa sim + Foundry suite match that culture.
5. **Hybrid future** — They end by suggesting off-chain pieces for cost/perf. That's your oracle/skiplist/analytics lane — lean into it explicitly in positioning vs "fully on-chain Deferral-style."

## What not to copy

1. **Custodial evaluate-and-pay monolith** — Couples product payments to referral SC; raises reentrancy/griefing surface; completion gas scales with ancestor count.
2. **Equal split among ancestors as default multilevel** — Weaker early-builder story than geometric; different incentive geometry than Emek-style decay (and still not SP).
3. **Assuming crypto checkout** — Their real-world path requires the company already take crypto payments into the referral contract. Your Exchange/agents framing is broader (contest fees, protocol cuts, off-chain-qualified actions).
4. **Feasibility ≠ product** — Their Ethereum vignette where gas > cashback is the cautionary tale for any deep on-chain process.

---

## Suggested citation blurb (for README / Exchange)

> Multilevel on-chain referral *payment evaluators* were shown technically feasible under load by Boner et al. (Deferral, 2023), with storage and reward distribution as dominant cost drivers and completion gas sensitive to ancestor depth. referralTree takes the complementary architecture: non-custodial shared attribution (`ReferralGraph`) and pure split math (`RewardCalculator`), leaving custody, eligibility, and transfers to the integrating app, with `ReferralSettlement` powering Incentive Exchange telemetry.

---

## Sources

- Thesis PDF / ZORA — https://doi.org/10.5167/uzh-255750 · https://owncloud.csg.uzh.ch/index.php/s/77TATExxwCawcZi/download/ma-tobias-boner.pdf  
- BRAINS — https://doi.org/10.1109/brains59668.2023.10316807  
- Deferral code — https://github.com/dydent/Deferral · visualizations — https://github.com/dydent/visualizations-deferral  
- referralTree — https://github.com/MagRelo/referralTree · Exchange — https://exchange.mattlovan.dev/
