# Changelog

## [2.0.0] - 2026-08-29

New deploy. Live Base / Base Sepolia ReferralGraph contracts are not upgradeable and are left in place.

### Breaking

- `UserRegistered` is now `event UserRegistered(bytes32 indexed groupId, address indexed user, address indexed referrer)`. Any subgraph or listener must be updated so registrations can be attributed to a project.

### Added

- `ReferralGraph.registeredCount(groupId)` — successful registrations per group (denominator; excludes `REFERRAL_ROOT`; never decrements).
- `ReferralGraph.skiplistedCount(groupId)` — current skiplist length without copying the array.
- `ReferralGraph.rewardRoots` pulls `totalAmount` of an ERC20 from `msg.sender`, pays `getPayoutChain`, and emits `RootsRewarded`. `ReferralGraph.rewardLeaf` pays a single registered `user` directly and emits `LeafRewarded`. Both are authorized by an EIP-712 signature (`RewardRoots` / `RewardLeaf`, distinct type names) from an oracle for the group: ECDSA (65-byte or EIP-2098) recovering to `oracle` is tried first (so EIP-7702-delegated EOAs work without a 1271 delegate), then ERC-1271 if `oracle` has code; no ERC-6492 (solmate-permit-style domain separator; payload binds `groupId`, `rewardId`, `user`, `token`, `totalAmount`, `payer = msg.sender`, `deadline`). Anyone may submit; no `tx.origin` or caller whitelist. The graph does not keep a balance. `rewardId` is unique per group across both functions and acts as the signature nonce (`RewardIdUsed`). `user` must be registered in the group for both.
- Optional global protocol fee on `rewardRoots` and `rewardLeaf` (`setProtocolFee`). Defaults to 0; capped at `MAX_FEE_BPS` (1000 bps = 10%). When set, `totalAmount * feeBps / 10000` is deducted from `totalAmount` and sent to `feeRecipient`; the remainder is paid out. Caller pays exactly `totalAmount`. `RootsRewarded.distributedAmount` / `LeafRewarded.distributedAmount` is the net amount; `distributedAmount + ProtocolFeeCharged.amount == totalAmount`.
- Naming (breaking vs the pre-release `settle` branches): `settle` → `rewardRoots`, `ReferralSettlement` → `RootsRewarded` (topic0 `0x512f243e…4235`; the old `0xc1d7413a…e3b3` is gone), `Settle` → `RewardRoots` typehash, `settlementId` → `rewardId`, `SettlementAlreadyUsed` → `RewardIdUsed`. New: `LeafRewarded` (topic0 `0xbcd78b20…a7aa`). `ProtocolFeeCharged` keeps its name and signature (its second field is now named `rewardId`).

### Unchanged

- Geometric split math (`0.6`, max 10, remainder to index 0).
- Graph does not retain a token balance between transactions.
- No on-chain payout journal, no `RewardDistributor` payout path, no `getAllUsers` / unbounded node enumeration, no `nodeCount` headline.
