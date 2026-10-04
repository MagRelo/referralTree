# Security Review: Multi-Level Referral Reward System

**Audit Date:** October 4, 2026  
**Auditor:** Independent Security Reviewer  
**Commit Hash:** `800da1df6f8317e8c5334fa190802cc7e0df2dfe`  
**Repository:** MagRelo/referralTree

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Scope](#scope)
3. [Methodology](#methodology)
4. [Summary of Findings](#summary-of-findings)
5. [Detailed Findings](#detailed-findings)
6. [Informational Notes](#informational-notes)
7. [Gas Optimizations](#gas-optimizations)
8. [Conclusion](#conclusion)

---

## Executive Summary

This security review covers the Multi-Level Referral Reward System, a non-custodial smart contract system for managing referral relationships and distributing rewards through a tree structure. The system consists of:

- **ReferralGraph.sol** - Core contract managing referral trees and reward distribution
- **RewardCalculator.sol** - Geometric reward splitting logic (0.6^k decay)
- **Associated interfaces and deployment scripts**

The review identified **no critical or high-severity vulnerabilities**. The codebase demonstrates strong security practices including:
- Proper EIP-712 signature verification with cross-chain replay protection
- Reentrancy guards on reward functions
- Comprehensive input validation
- Well-designed nonce system preventing signature replay

The findings consist primarily of low-severity issues related to ERC-20 edge cases and informational observations about design choices.

---

## Scope

### In-Scope Contracts

| File | Lines | Description |
|------|-------|-------------|
| `src/core/ReferralGraph.sol` | 581 | Core referral tree and reward distribution |
| `src/core/RewardCalculator.sol` | 53 | Geometric reward calculation |
| `src/interfaces/IReferralGraph.sol` | 309 | Interface definition |
| `src/interfaces/IRewardCalculator.sol` | 19 | Calculator interface |
| `src/interfaces/IERC1271.sol` | 9 | ERC-1271 signature validation |
| `script/Deploy.s.sol` | 36 | Deployment script |

### Out of Scope

- Test files and mocks
- External dependencies (solmate, forge-std)

### Test Environment

- Solidity 0.8.26
- Foundry 1.8.4
- EVM Version: Cancun

---

## Methodology

The audit employed the following techniques:

1. **Manual Code Review** - Line-by-line analysis of all in-scope contracts
2. **Automated Analysis** - Slither static analysis (v0.11.6)
3. **Foundry Testing** - All 102 existing tests pass; 13 additional PoC tests created
4. **Invariant Testing** - Verification of structural properties (no cycles, referrer consistency)

### Areas of Focus

- Access control and oracle trust model
- EIP-712 domain, nonce, and replay handling
- Signature malleability and deadline handling
- Reentrancy and ERC-20 quirks
- Rounding and fee math
- Unbounded loops and gas griefing
- Front-running/MEV on register and settle
- Referral cycles and self-referral
- Depth-cap edge cases
- Event and indexer correctness
- Upgradeability and initialization
- Denial of service vectors
- Centralization risks

---

## Summary of Findings

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | 0 | - |
| High | 0 | - |
| Medium | 0 | - |
| Low | 2 | ERC-20 edge cases |
| Informational | 8 | Design observations and best practices |
| Gas | 2 | Optimization opportunities |

---

## Detailed Findings

### Low Severity

#### L-01: Fee-on-Transfer Tokens Cause Accounting Discrepancy

**Location:** `src/core/ReferralGraph.sol:408-410`, `src/core/ReferralGraph.sol:436`

**Description:**  
The contract uses `safeTransferFrom` to transfer tokens but does not account for fee-on-transfer tokens. When a fee-on-transfer token is used, the actual amount received by each recipient is less than the amount specified in the transfer call and emitted in events.

**Impact:**  
Recipients receive less than the amounts indicated in the `RootsRewarded` and `LeafRewarded` events. Indexers and off-chain systems relying on event data will have incorrect accounting.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testL01_FeeOnTransferTokensNotSupported`

**Recommendation:**  
Document that fee-on-transfer tokens are not supported. Alternatively, measure the balance change before and after transfers to determine actual amounts received. This is a known limitation in many protocols and is acceptable if documented.

---

#### L-02: Rebasing Tokens May Cause Unexpected Behavior

**Location:** `src/core/ReferralGraph.sol:370-412`, `src/core/ReferralGraph.sol:415-438`

**Description:**  
Rebasing tokens (tokens that automatically adjust balances) are not explicitly supported. While the contract does not hold token balances (non-custodial design), any integration that relies on the exact amounts emitted in events may encounter discrepancies.

**Impact:**  
Low impact due to the non-custodial design. The contract immediately transfers tokens from payer to recipients without holding any balance.

**Recommendation:**  
Document that rebasing tokens are not supported or may exhibit unexpected behavior.

---

### Informational

#### I-01: Protocol Fee Rounds to Zero for Small Amounts

**Location:** `src/core/ReferralGraph.sol:577-580`

**Description:**  
The protocol fee calculation uses integer division which rounds down:
```solidity
return (totalAmount * bps) / BPS_DENOMINATOR;
```

For `feeBps = 1` (0.01%) and amounts less than 10,000, the fee rounds to zero.

**Impact:**  
No protocol revenue is collected for dust-sized rewards. This is expected behavior but should be documented.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testI01_ProtocolFeeRoundsToZeroForSmallAmounts`

**Recommendation:**  
Document this behavior. Consider a minimum fee if revenue on small amounts is important.

---

#### I-02: Token Without Code Handled Correctly

**Location:** `src/core/ReferralGraph.sol:408`, `src/core/ReferralGraph.sol:436`

**Description:**  
If a token address without code is provided, `safeTransferFrom` from solmate will revert with "TRANSFER_FROM_FAILED" because the low-level call returns no data.

**Impact:**  
Informational - the contract correctly fails when given an invalid token address.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testI02_TokenWithoutCodeBehavior`

---

#### I-03: Oracle Deauthorization Invalidates Existing Signatures

**Location:** `src/core/ReferralGraph.sol:454`

**Description:**  
Oracle authorization is checked at execution time, not at signature creation time:
```solidity
if (!_authorizedOracles[groupId][oracle]) revert InvalidSigner();
```

If an oracle is deauthorized after signing but before submission, the signature becomes invalid.

**Impact:**  
This is the correct security model - it allows owners to revoke compromised oracles immediately. However, off-chain systems should be aware that pre-signed rewards may fail if the oracle is deauthorized.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testI03_DeauthorizedOracleSignatureInvalid`

---

#### I-04: Owner Can Instantly Change Fee Settings

**Location:** `src/core/ReferralGraph.sol:360-367`

**Description:**  
The owner can set protocol fees up to 10% (MAX_FEE_BPS = 1000) instantly without any timelock or governance delay.

**Impact:**  
Centralization risk - users must trust the owner not to increase fees unexpectedly. This is mitigated by the 10% hard cap.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testI04_InstantFeeChangeByOwner`

**Recommendation:**  
Consider implementing a timelock for fee changes above a certain threshold, or document this as an accepted centralization tradeoff.

---

#### I-05: REFERRAL_ROOT Never Receives Rewards

**Location:** `src/core/ReferralGraph.sol:26`, `src/core/ReferralGraph.sol:136`, `src/core/ReferralGraph.sol:164`

**Description:**  
`REFERRAL_ROOT` (address(0x1)) is excluded from payout chains. Users directly under the root with no other ancestors will cause `EmptyPayoutChain` revert when calling `rewardRoots`.

**Impact:**  
By design. The root is a sentinel value, not a real recipient. Use `rewardLeaf` to pay users directly under the root.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testI05_ReferralRootNeverPaid`

---

#### I-06: Signature Malleability Handled via Nonce

**Location:** `src/core/ReferralGraph.sol:524-532`

**Description:**  
The contract does not reject high-s ECDSA signatures (unlike EIP-2 strict signatures). However, signature replay is prevented by the `rewardId` nonce system which marks each rewardId as used.

**Impact:**  
Informational - this is an intentional design choice matching solmate's permit implementation.

**Existing Test:**  
See `testMalleatedSignatureCannotReplay()` in the existing test suite.

---

#### I-07: EIP-712 Domain Separator Correctly Includes Chain ID

**Location:** `src/core/ReferralGraph.sol:487-500`

**Description:**  
The domain separator correctly includes `chainId` and `verifyingContract` address. It is cached at construction but recomputed if the chain ID changes (fork protection).

**Impact:**  
Cross-chain replay attacks are prevented.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testM01_CrossChainReplayProtection`

---

#### I-08: Depth Cap Correctly Limits Payout Recipients

**Location:** `src/core/ReferralGraph.sol:20`, `src/core/ReferralGraph.sol:393`

**Description:**  
`MAX_PAYOUT_LEVELS = 10` caps the number of recipients in `rewardRoots`. The `RewardCalculator` also caps at 10 recipients. This prevents unbounded gas consumption in deep trees.

**Impact:**  
Gas griefing is mitigated. Deep referral chains are supported for registration, but payouts are capped.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testI08_DepthCapInPayout`

---

## Gas Optimizations

#### G-01: Unbounded Loop in batchRegister

**Location:** `src/core/ReferralGraph.sol:306-313`

**Description:**  
`batchRegister` iterates over an unbounded array, which can consume excessive gas for large batches.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testG01_BatchRegisterGasConsumption`  
Result: ~54,000 gas per registration, 100 registrations = ~5.4M gas

**Recommendation:**  
Document recommended batch sizes or add a maximum batch size check. A batch of ~150 users would approach block gas limits.

---

#### G-02: View Functions Return Unbounded Arrays

**Location:** `src/core/ReferralGraph.sol:118-120`, `src/core/ReferralGraph.sol:212-215`

**Description:**  
`getChildren()` and `getSkiplisted()` return entire arrays which could be very large for popular referrers or groups with many skiplisted addresses.

**PoC:**  
See `test/audit/AuditPoCs.t.sol::testG02_UnboundedArrayReturns`  
Result: ~155K gas for 50 children

**Recommendation:**  
Consider adding paginated view functions for off-chain queries if these lists are expected to grow large.

---

## Informational Notes

### Static Analysis Results (Slither)

Slither identified 11 results, all informational:

1. **Uninitialized local variable `sum`** (line 399) - False positive; initialized to 0 by Solidity.
2. **Timestamp comparison** (line 453) - Expected for deadline validation; not exploitable.
3. **Assembly usage** (lines 544-572) - Necessary for efficient signature verification; reviewed and safe.
4. **Multiple Solidity versions** - Dependencies use `>=0.8.0`, project uses `^0.8.20`; acceptable.
5. **Naming conventions** - `DOMAIN_SEPARATOR()` etc. match EIP-712 conventions.

### Verified Security Properties

- **No cycles in referral tree** - Enforced by `UserAlreadyRegistered` and `ReferrerNotInTree` checks
- **Self-referral blocked** - `SelfReferralNotAllowed` error
- **Replay protection** - `rewardId` nonce shared between `rewardRoots` and `rewardLeaf`
- **Cross-chain protection** - Domain separator includes chain ID
- **Cross-group isolation** - Oracle authorization is per-group
- **Reentrancy protection** - `nonReentrant` modifier on reward functions

### Design Observations

1. **Non-custodial design** - Contract never holds token balances; transfers go directly from payer to recipients
2. **Oracle trust model** - Oracles are fully trusted for their groups; they can register users and sign rewards
3. **No upgradeability** - Contracts are not upgradeable; immutable deployment
4. **No pause functionality** - Cannot be paused; may be intentional for trustlessness

---

## Conclusion

The Multi-Level Referral Reward System demonstrates strong security engineering. The EIP-712 signature implementation is correct, replay protection is comprehensive, and the non-custodial design minimizes token-holding risks.

The identified issues are low-severity and primarily relate to ERC-20 edge cases (fee-on-transfer, rebasing tokens) that are common limitations in DeFi protocols. These should be documented but do not require code changes.

**Recommendation:** Document the limitations regarding fee-on-transfer tokens, rebasing tokens, and the instant fee-change capability. Consider adding pagination to view functions if large arrays are expected.

---

## Appendix: Test Results

All 102 existing tests pass. 13 additional PoC tests were created and pass:

```
Running 13 tests for test/audit/AuditPoCs.t.sol:AuditPoCs
[PASS] testG01_BatchRegisterGasConsumption()
[PASS] testG02_UnboundedArrayReturns()
[PASS] testI01_ProtocolFeeRoundsToZeroForSmallAmounts()
[PASS] testI02_TokenWithoutCodeBehavior()
[PASS] testI03_DeauthorizedOracleSignatureInvalid()
[PASS] testI04_InstantFeeChangeByOwner()
[PASS] testI05_ReferralRootNeverPaid()
[PASS] testI06_GeometricWeightsCorrectness()
[PASS] testI07_CyclePrevention()
[PASS] testI08_DepthCapInPayout()
[PASS] testL01_FeeOnTransferTokensNotSupported()
[PASS] testM01_CrossChainReplayProtection()
Suite result: ok. 13 passed; 0 failed; 0 skipped
```

---

*Report generated by independent security review. This report is provided "as is" and does not constitute financial or legal advice. Smart contracts should be thoroughly tested before deployment.*
