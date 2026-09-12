# Industry Landscape: On-Chain & Platform Referral Systems

**Date:** 2026-09-10  
**Purpose:** Map the competitive and architectural landscape around multilevel referral incentives so engineers building systems like referralTree know where peers sit, what patterns dominate, and which gaps remain open.

---

## Scope

Referral and affiliate systems in crypto span two layers: (1) on-chain Solidity contracts that store graphs and sometimes settle payouts, and (2) growth platforms that handle tracking, campaigns, and often custody or off-chain accounting. This brief surveys both, then places [referralTree](https://github.com/MagRelo/referralTree) relative to them.

## On-chain peers

**Deferral** ([github.com/dydent/Deferral](https://github.com/dydent/Deferral); visualizations: [dydent/visualizations-deferral](https://github.com/dydent/visualizations-deferral)) is the closest research-adjacent peer. Tobias Boner's 2023 work formalizes deferred reward distribution over referral trees with on-chain mechanisms and analysis of incentive properties. It is academic-first: mechanism design and evaluation matter as much as deployability. referralTree's geometric decay and non-custodial split echo the same problem class—who gets paid along a chain—but Deferral is the reference for published mechanism thinking; referralTree is the production-shaped graph + app-settlement stack.

**ThunderCore referral-solidity** ([thundercore/referral-solidity](https://github.com/thundercore/referral-solidity)) is a classic self-register tree: users attach to a referrer on-chain; rewards follow parent links. Simple, battle-tested pattern for L1/L2 dapps that want "invite code as address" without an oracle. Abuse (Sybil, self-refer loops) is mostly out of scope of the contract.

**Clicks Protocol** ([clicks-protocol/clicks-protocol](https://github.com/clicks-protocol/clicks-protocol)) pushes further into protocolized click/referral attribution. Architecture leans toward on-chain registration of referral relationships with protocol-level accounting—useful as a contrast to oracle-gated designs where eligibility lives off-chain.

**Safwa** ([SafwaNetwork/contract.safwa.network](https://github.com/SafwaNetwork/contract.safwa.network)) exemplifies matrix / MLM-style topologies: forced tree or matrix fill rules, often with strong on-chain payout coupling. These systems maximize "structure pays" mechanics and sit closest to regulatory MLM/pyramid scrutiny (see Doc 2 / Doc 4). Architecturally opposite of referralTree's non-custodial graph + app-owned transfers.

**mdantis SOLIDITY-referral-system** ([mdantis-dev/SOLIDITY-referral-system](https://github.com/mdantis-dev/SOLIDITY-referral-system)) is a compact multilevel referral contract sample: register referrer, walk up N levels, split rewards. Representative of many GitHub "referral.sol" clones—useful for pattern recognition, not as a research baseline.

**LooksRare AffiliateManager** ([docs](https://docs.looksrare.org/developers/protocol-contracts/AffiliateManager)) is fee-affiliate, not multilevel tree: affiliates earn a cut of trading fees tied to referred volume. Single-hop or shallow attribution, custody/settlement inside the marketplace's fee path. Important industry pattern: most successful NFT/DeFi "referral" products are fee affiliates, not geometric MLM trees.

## Growth platforms (off-chain / hybrid)

| Platform | Role | Link |
|----------|------|------|
| **Fuul** | On-chain affiliate / reward infra for protocols | [fuul.xyz](https://www.fuul.xyz/) |
| **ShareMint** | Creator/affiliate campaign tooling | [sharemint.xyz](https://sharemint.xyz/) |
| **XOffer** | Offer / affiliate marketplace style growth | [xoffer.io](https://www.xoffer.io/) |
| **Attrace** | Decentralized affiliate & referral attribution network | [attrace.com/about](https://attrace.com/about/) |
| **Galxe** | Credential / quest / campaign distribution | [galxe.com](https://www.galxe.com/) |
| **Layer3** | Quest and business campaign layer | [app.layer3.xyz/business](https://app.layer3.xyz/business) |

These products win on UX, campaign ops, analytics, and anti-fraud as product features. On-chain pieces (if any) are often attestation, claim tokens, or fee hooks—not full multilevel payout graphs. Attrace and Fuul are the closest to "protocolized affiliate"; Galxe/Layer3 are quest engines where referral is one growth lever among many.

## Architecture pattern table

| Pattern | Who registers edges? | Who holds funds? | Payout logic | Typical risk |
|---------|----------------------|------------------|--------------|--------------|
| **On-chain self-register** | User tx sets parent | Often contract or claim | Walk parents, fixed % | Sybil, griefing, unbounded gas |
| **Oracle-gated** | Trusted/relayer registers | App or escrow | Off-chain eligibility → on-chain settle | Oracle trust, censorship |
| **Fee affiliate** | Marketplace attribution | Protocol fee path | Single/shallow cut | Gaming volume, wash |
| **Matrix / MLM** | Forced placement rules | Contract often custodial | Matrix spillover / levels | Legal classification, collapse |
| **Non-custodial graph + app payout** | Oracle/app registers graph; app transfers | Users / app wallets | On-chain chain readout; app emits settlement | App honesty; graph integrity |

## Where referralTree sits

referralTree ([MagRelo/referralTree](https://github.com/MagRelo/referralTree)) is the **non-custodial graph + app payout** pattern:

- **ReferralGraph** — per-`groupId` trees; oracle `register` / `batchRegister`; skiplist structure; `getPayoutChain` for depth-capped ancestor walks.
- **RewardCalculator** — geometric decay **0.6**, max depth **10**, remainder to index 0 (root/origin).
- **App owns transfers**; same transaction emits `ReferralSettlement` for indexing (Incentive Exchange live at [exchange.mattlovan.dev](https://exchange.mattlovan.dev/)).
- Abuse controls live mostly in **app/oracle policy**; Mesa simulation under `simulation/`. Stack: Foundry, Solidity ~0.8.26, Cancun; CHANGELOG 2026-08-29 marks v2.

Versus peers: more mechanism-aware than ThunderCore/mdantis clones; less custodial/matrix than Safwa; more multilevel-graph than LooksRare AffiliateManager; more production/engineering oriented than Deferral's thesis artifacts; more on-chain structure than Fuul/ShareMint/Galxe which optimize campaign ops. The live Incentive Exchange positions MagRelo to treat referral events as a **signal index for agents**, not only a growth CRM.

## Practical takeaway

If you need multilevel splits with auditable chain math and no on-chain custody of rewards, referralTree's lane is thin but clear. If you need growth ops and anti-fraud as a service, platforms win. If you need published Sybil-proof mechanism guarantees, academia (Doc 2–3) still outruns every production Solidity tree—including this one.

## Sources

- MagRelo/referralTree — https://github.com/MagRelo/referralTree  
- Deferral — https://github.com/dydent/Deferral · visualizations — https://github.com/dydent/visualizations-deferral  
- ThunderCore referral-solidity — https://github.com/thundercore/referral-solidity  
- Clicks Protocol — https://github.com/clicks-protocol/clicks-protocol  
- SafwaNetwork — https://github.com/SafwaNetwork/contract.safwa.network  
- mdantis SOLIDITY-referral-system — https://github.com/mdantis-dev/SOLIDITY-referral-system  
- LooksRare AffiliateManager — https://docs.looksrare.org/developers/protocol-contracts/AffiliateManager  
- Fuul — https://www.fuul.xyz/ · ShareMint — https://sharemint.xyz/ · XOffer — https://www.xoffer.io/ · Attrace — https://attrace.com/about/ · Galxe — https://www.galxe.com/ · Layer3 — https://app.layer3.xyz/business  
- Incentive Exchange — https://exchange.mattlovan.dev/
