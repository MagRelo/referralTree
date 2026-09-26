# Changelog

## [2.0.0] - 2026-08-29

New deploy. Live Base / Base Sepolia ReferralGraph contracts are not upgradeable and are left in place.

### Breaking

- `UserRegistered` is now `event UserRegistered(bytes32 indexed groupId, address indexed user, address indexed referrer)`. Any subgraph or listener must be updated so registrations can be attributed to a project.

### Added

- `ReferralGraph.registeredCount(groupId)` — successful registrations per group (denominator; excludes `REFERRAL_ROOT`; never decrements).
- `ReferralGraph.skiplistedCount(groupId)` — current skiplist length without copying the array.
- `ReferralGraph.settle` pulls an ERC20 fee from `msg.sender`, pays `getPayoutChain`, and emits `ReferralSettlement`. `msg.sender` or `tx.origin` must be an authorized oracle for the group. The graph does not keep a balance. `settlementId` is unique per group.
- Optional global protocol fee on `settle` (`setProtocolFee`). Defaults to 0. When set, the caller also pays `totalAmount * feeBps / 10000` to `feeRecipient` on top of the referral split. `ReferralSettlement.totalAmount` is still the referral-network fee.

### Unchanged

- Geometric split math (`0.6`, max 10, remainder to index 0).
- Graph does not retain a token balance between transactions.
- No on-chain settlement journal, no `RewardDistributor` payout path, no `getAllUsers` / unbounded node enumeration, no `nodeCount` headline.
