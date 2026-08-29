# Changelog

## [2.0.0] - 2026-08-29

New deploy. Live Base / Base Sepolia ReferralGraph contracts are not upgradeable and are left in place.

### Breaking

- `UserRegistered` is now `event UserRegistered(bytes32 indexed groupId, address indexed user, address indexed referrer)`. Any subgraph or listener must be updated so registrations can be attributed to a project.

### Added

- `ReferralGraph.registeredCount(groupId)` — successful registrations per group (denominator; excludes `REFERRAL_ROOT`; never decrements).
- `ReferralGraph.skiplistedCount(groupId)` — current skiplist length without copying the array.
- Canonical `ReferralSettlement` event for integrators. ReferralTree does not journal payouts; Incentive Exchange indexes this event when the payout contract emits it in the same transaction as the transfers.

### Unchanged

- Geometric split math (`0.6`, max 10, remainder to index 0).
- Graph does not hold or transfer tokens.
- No on-chain settlement journal, no `RewardDistributor` payout path, no `getAllUsers` / unbounded node enumeration, no `nodeCount` headline.
