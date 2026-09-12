# ThunderCore referral-solidity vs referralTree

**Date:** 2026-09-10  
**Purpose:** Feature and design compare for MagRelo vs `@thundercore/referral-solidity`.

| | **ThunderCore `referral-solidity`** | **referralTree v2** |
|---|---|---|
| **What it is** | Inherit-me game/dapp library (npm, Solidity ~0.5) | Shared infra (Foundry, ~0.8.26 / Cancun) |
| **Custody** | Pays **native** uplines inside `payReferral` | Graph + Calculator hold **no** funds; app transfers |
| **Who binds the edge** | Referee self-calls `addReferrer` | Oracle-only `register` / `batchRegister` per `groupId` |
| **Multi-tenancy** | One tree per inheriting contract | Many isolated trees via `groupId` |
| **Max depth** | **3** (`levelRate`) | **10** payout recipients |
| **Split** | Level % of tx amount × bonus × referee-count tier × active flag | Pure geometric 0.6 over chain length |
| **When paid** | Instantly on play/join | Whenever app settles + `ReferralSettlement` |
| **Activity gating** | Built-in inactivity window | App/oracle policy |
| **Abuse controls** | Soft-fail register events | Skiplist, tree invariants, counters |
| **Token** | Native only in the lib | Token-agnostic at settlement |

ThunderCore formula (README): \(R = A \times X \times Y_n \times Z_m \times \mathrm{isActive}\).

**Bottom line:** ThunderCore = turnkey 3-level native pay-on-play module. referralTree = multi-tenant non-custodial multilevel infrastructure.

## Sources

- https://github.com/thundercore/referral-solidity  
- https://github.com/MagRelo/referralTree  
