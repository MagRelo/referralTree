# Referral Abuse and Mitigation Plan

## Purpose

This document explains the payout incentives in the current multi-level referral system and recommends ways to reduce abuse from Sybil accounts, fake referrers, collusive referral chains, and low-quality registrations.

The main design principle is that the contracts should enforce simple invariants, while the oracle and registration process should enforce user quality, event eligibility, and fraud controls before rewards are signed.

## Current Mechanics

The system has two trust boundaries:

- `ReferralGraph` stores the referral tree for each `groupId`.
- `RewardDistributor` verifies an authorized oracle signature and pays a reward pool up a referral chain.

Registration is oracle-gated. Only an authorized oracle can call `register` or `batchRegister`. The graph prevents zero-address users, zero-address referrers, direct self-referrals, duplicate registrations in the same group, and registration under a referrer that is not already in the group's tree. The first user in a group can be registered under `REFERRAL_ROOT`.

Referral edges are append-only. Once a user is registered in a group, their referrer cannot be changed by the current contract.

Reward distribution is also oracle-gated, but through signatures. An authorized oracle signs `ChainRewardData`, including:

- `user`: the first address in the payout chain and the largest recipient.
- `totalAmount`: the reward pool to distribute.
- `rewardToken`: the token paid from the distributor.
- `groupId`: the referral tree used for upstream lookups.
- `eventId`, `timestamp`, and `nonce`: off-chain event metadata used in the signed hash.

When `distributeChainRewards` is called, the contract starts with `reward.user`, walks upward through that user's referrers, stops at `REFERRAL_ROOT` or an empty referrer, caps payouts at 10 recipients, and distributes the full `totalAmount` using geometric weights with a 0.6 decay ratio.

## Payout Incentives

For a short chain, the first recipient receives the largest share, and upstream referrers receive progressively smaller shares.

| Paid recipients | First recipient | Second | Third | Fourth | Fifth |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 100.00% | - | - | - | - |
| 2 | 62.50% | 37.50% | - | - | - |
| 3 | 51.02% | 30.61% | 18.37% | - | - |
| 4 | 45.96% | 27.57% | 16.54% | 9.93% | - |
| 5 | 43.40% | 26.00% | 15.60% | 9.36% | 5.62% |

At the 10-recipient cap, the approximate split is:

| Level | Share |
| --- | ---: |
| 0 | 40.25% |
| 1 | 24.15% |
| 2 | 14.49% |
| 3 | 8.69% |
| 4 | 5.22% |
| 5 | 3.13% |
| 6 | 1.88% |
| 7 | 1.12% |
| 8 | 0.67% |
| 9 | 0.40% |

These incentives are good for motivating direct referrals because the first recipient captures the largest share. They also create predictable gaming incentives:

- An attacker wants to control the first paid recipient whenever possible.
- If the attacker can control a contiguous referral chain, they can capture most or all of the reward.
- If rewards are paid for weak events, attackers can profit by manufacturing accounts and events until expected rewards exceed abuse costs.
- Early tree position matters because upstream accounts continue to receive smaller but recurring rewards from downstream activity.

## Abuse Scenarios

### Sybil Referral Farms

An attacker creates many wallets and registers them under one or more attacker-controlled referrers. If the oracle later signs rewards for activity from those wallets, the attacker captures the direct reward and the upstream rewards.

Impact is highest when:

- Account creation is free or cheap.
- Reward-triggering actions have little economic cost.
- Rewards are immediate and liquid.
- There are no per-user, per-device, per-payment-method, or per-identity limits.

### Fake Referrer Attribution

A user may be registered under a referrer that did not actually refer them. This can happen through spoofed referral codes, last-click manipulation, oracle bugs, compromised backends, or collusion with an integration partner.

Impact is high because referral edges are immutable. A bad attribution can permanently route future rewards to the wrong upstream chain.

### Self-Referral Through Multiple Accounts

Direct self-referral is blocked at the address level, but a user can still create multiple wallets and refer themselves indirectly. For example, an attacker can create `A -> B -> C`, then trigger reward events where all paid recipients are controlled by the same actor.

The contract cannot distinguish legitimate household, team, or community referrals from one person controlling many wallets. This has to be handled by registration and oracle policy.

### Reward Event Replay by Variant Payload

The distributor prevents replay of the exact same signed reward hash. However, the same real-world event can be paid again if the oracle signs a second payload with a different `timestamp`, `nonce`, `totalAmount`, or `eventId`.

This is primarily an oracle correctness issue. The contract does not enforce one payout per real-world event.

### Unregistered First Recipient

`distributeChainRewards` starts the payout chain with `reward.user` before looking up its referrer. If the oracle signs a reward for an address that is not registered in the selected group, that address can still receive 100% of the reward because the chain has one recipient.

This may be intentional for direct campaign rewards, but if referral payouts should only go to registered referrers, the oracle must enforce that policy or the contract should require registration.

### Oracle or Backend Compromise

Authorized oracles can register referral edges and sign reward distributions. A compromised oracle key can create fake registrations, sign excessive rewards, choose arbitrary reward tokens held by the distributor, and route rewards to attacker addresses until the oracle is removed or funds are drained.

### Group and Token Confusion

Because `groupId` and `rewardToken` are included in the signed payload but not constrained by an app registry, the oracle is responsible for ensuring the event belongs to the group and token being paid. A signing bug could pay the wrong campaign, group, or token.

## Recommended Controls

### Registration Controls

Require registration to be backed by an attribution record that the oracle can verify. At minimum, store and validate:

- The referral code or invite link used.
- The user address being registered.
- The intended referrer address.
- The `groupId`.
- The timestamp and source of attribution.
- The product account, session, or installation associated with the registration.

Use a clear attribution policy. Recommended defaults:

- First valid referral wins, not last click.
- Referral attribution expires after a fixed window, such as 7-30 days.
- Referrer cannot be changed after the user completes a qualifying action.
- The referrer must have an account in good standing before they can receive new referrals.
- Do not let users enter or change referral codes after they know a reward-triggering event is likely.

Add friction proportional to reward value:

- Low-value campaigns can use wallet ownership, email/phone verification, device fingerprinting, and rate limits.
- Medium-value campaigns should require proof of account age, minimum product engagement, or a small economic action.
- High-value campaigns should use stronger identity, payment uniqueness, allowlists, or manual review.

### Reward Eligibility Controls

Only sign rewards for events that have real value to the product. A reward-triggering event should satisfy all of these:

- The referred user completed a qualifying action, not just registration.
- The action is final enough that it is unlikely to be reversed, refunded, or charged back.
- The expected gross value of the action is greater than the expected referral payout plus fraud risk.
- The user and referrer are not already flagged, banned, or over limit.
- The event has not already been paid in the oracle's off-chain ledger.

Avoid paying meaningful rewards for cheap actions like account creation, connecting a wallet, joining a Discord, or making a trivially reversible transaction.

### Payout Design Controls

Consider splitting rewards into pending, vested, and claimable states off-chain or in a future contract version. Immediate liquid rewards are easiest to abuse. Better patterns include:

- Delay payouts until the referred user remains active for a minimum period.
- Vest larger rewards over time.
- Claw back or net future rewards when downstream activity is reversed.
- Cap rewards per referred user, referrer, group, and time window.
- Use lower payout rates for shallow or low-confidence registrations.
- Increase payout rates only after the referrer builds a clean history.

The current geometric curve strongly rewards the first recipient. That is useful when `reward.user` is a legitimate referrer, but risky when the oracle can be tricked into setting `reward.user` to an attacker-controlled account. If abuse pressure is high, consider a smaller direct share, a fixed direct-referrer bonus plus capped upstream pool, or reward multipliers based on trust tier.

### Sybil Resistance

No single Sybil defense is enough. Use layered signals and make abuse economics unattractive:

- Per-wallet limits: cap rewards per address and per downstream address.
- Per-identity limits: link accounts through phone, email, OAuth, payment method, KYC, or proof-of-personhood where appropriate.
- Per-device and network limits: detect repeated registrations from the same device, IP range, emulator, VPN, or automation pattern.
- Funding graph checks: flag wallets funded by the same source, recently created wallets, circular transfers, and common withdrawal destinations.
- Behavior checks: require normal product usage before reward eligibility.
- Graph checks: flag unusually deep chains, dense attacker-controlled clusters, high sibling counts from one referrer, and accounts that only exist to refer.

Treat these as risk signals, not automatic proof. Some legitimate communities share devices, networks, exchanges, and funding sources.

### Oracle Safety

The oracle is the highest-leverage control point. Recommended practices:

- Maintain an off-chain idempotency table keyed by canonical real-world event ID, not by signed nonce alone.
- Refuse to sign if `reward.user` is not an eligible registered account for `groupId`, unless the campaign explicitly allows direct non-referral rewards.
- Enforce per-campaign budgets before signing.
- Enforce per-user, per-referrer, and per-group velocity limits.
- Validate `rewardToken` against an allowlist for the campaign.
- Validate `groupId` against the app or campaign that generated the event.
- Sign with short-lived keys where possible and keep hot wallet limits low.
- Use separate oracle keys for registration and reward signing.
- Monitor oracle output for unusual amounts, tokens, groups, recipients, and signing velocity.
- Keep an emergency runbook to unauthorize an oracle and pause funding when abuse is detected.

For higher-value deployments, use multi-signer approval or threshold signing for large distributions, new tokens, new groups, or unusually high-risk accounts.

### Contract-Level Improvements To Consider

The current contracts are intentionally simple. If abuse risk increases, consider adding some guardrails on-chain:

- Require `reward.user` to be registered in `groupId` before paying referral rewards.
- Add EIP-712 typed data with `chainId` and verifying contract to prevent cross-chain or cross-contract signature reuse.
- Include an on-chain consumed mapping by `eventId` or `(groupId, eventId)` if each event should pay once regardless of nonce.
- Add per-token or per-group reward caps controlled by the owner or campaign admin.
- Add an app or campaign registry that binds allowed oracles, groups, and reward tokens.
- Add pause controls for distribution and registration separately.
- Emit `groupId` in registration events to simplify monitoring and indexing.
- Consider a referrer dispute or correction process if immutable attribution creates unacceptable operational risk.

## Monitoring and Detection

Track abuse through product data, oracle decisions, and on-chain graph activity. Useful metrics include:

- Registrations per referrer per hour/day.
- Reward amount per referrer, per group, and per token.
- Ratio of referred accounts that complete qualifying actions.
- Ratio of referred accounts later banned, refunded, or inactive.
- Chain depth distribution by group.
- Percentage of rewards captured by top referrers.
- Clusters of accounts sharing device, IP, funding source, withdrawal address, or behavioral fingerprints.
- Duplicate or near-duplicate event records before signing.

Set alerts for sudden spikes, new referrers earning outsized rewards, and campaigns where reward cost exceeds expected user value.

## Suggested Rollout Policy

Start conservative and loosen controls only after real data supports it:

1. Pay no reward on registration alone.
2. Require a qualifying action with clear economic or product value.
3. Hold rewards in a pending state during an initial fraud window.
4. Cap daily and lifetime rewards per user, referrer, and group.
5. Manually review the highest-earning referrers before increasing limits.
6. Gradually increase limits for accounts with clean history.

## Open Questions

- Should referral rewards only be paid when `reward.user` is registered in the target group?
- Should every real-world event be payable once, or can one event intentionally produce multiple reward distributions?
- What is the minimum qualifying action for each campaign?
- What maximum payout is acceptable before stronger identity or manual review is required?
- Should referrer attribution be permanently immutable, or should there be a controlled correction path?
- Who owns oracle risk: the protocol owner, each campaign, or a shared fraud operations process?

## Bottom Line

The system is only as abuse-resistant as the oracle's registration and signing policy. The contracts prevent malformed tree edges and exact signed-payload replay, but they do not prove that users are unique, that referrers are genuine, or that reward events are economically valid.

The best near-term mitigation is to make the oracle conservative: register only attributable referrals, sign only valuable and deduplicated events, cap exposure aggressively, and delay or review payouts when Sybil signals appear. Contract changes can add useful backstops, but the main defense against fake accounts and fake referrers will be product-level verification plus oracle discipline.
