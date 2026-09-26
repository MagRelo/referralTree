# Changelog

## [2.0.0] - 2026-08-29

New deploy. Live Base / Base Sepolia ReferralGraph contracts are not upgradeable and are left in place.

### Breaking

- `UserRegistered` is now `event UserRegistered(bytes32 indexed groupId, address indexed user, address indexed referrer)`. Any subgraph or listener must be updated so registrations can be attributed to a project.

### Added

- `ReferralGraph.registeredCount(groupId)` — successful registrations per group (denominator; excludes `REFERRAL_ROOT`; never decrements).
- `ReferralGraph.skiplistedCount(groupId)` — current skiplist length without copying the array.
- `ReferralGraph.settle` pulls an ERC20 fee from `msg.sender`, pays `getPayoutChain`, and emits `ReferralSettlement`. Authorized by an EIP-712 `Settle` signature from an oracle for the group: ECDSA (65-byte or EIP-2098) recovering to `oracle` is tried first (so EIP-7702-delegated EOAs work without a 1271 delegate), then ERC-1271 if `oracle` has code; no ERC-6492 (solmate-permit-style domain separator; payload binds `groupId`, `settlementId`, `user`, `token`, `totalAmount`, `payer = msg.sender`, `deadline`). Anyone may submit; no `tx.origin` or caller whitelist. The graph does not keep a balance. `settlementId` is unique per group and acts as the signature nonce.
- Optional global protocol fee on `settle` (`setProtocolFee`). Defaults to 0; capped at `MAX_FEE_BPS` (1000 bps = 10%). When set, `totalAmount * feeBps / 10000` is deducted from the settle total and sent to `feeRecipient`; the remainder is the referral split. Caller pays exactly `totalAmount`. `ReferralSettlement.totalAmount` is the referral distributable.

### Unchanged

- Geometric split math (`0.6`, max 10, remainder to index 0).
- Graph does not retain a token balance between transactions.
- No on-chain settlement journal, no `RewardDistributor` payout path, no `getAllUsers` / unbounded node enumeration, no `nodeCount` headline.
