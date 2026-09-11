# ADR-040: Autonomous operation is normal; budget replaces attribution

- **Status:** Proposed
- **Date:** 2026-09-11
- **Supersedes:** ADR-025 §9, fully. ADR-026 §5 lifted it per provider; this retires it.
- **Superseded by:** none

## Context

ADR-025 §9 required every model call to trace to a message the owner had just sent: *"No scheduled
calls, no background calls, no autonomous calls."* ADR-026 §5 then permitted subscription providers to
serve unattended calls as an accepted risk, per provider.

That left the rule half-alive — superseded in one direction, still written as a prohibition — which
invites a future reader to enforce it.

The target architecture makes autonomous work ordinary rather than exceptional. The system is always
running and listening; a request may come from a schedule, from a client such as Factory, or from the
system itself noticing something. None of those trace to a message the owner just sent, and requiring
that they do would remove most of what the system is for.

## Decision

### 1. Autonomous model calls are normal

A call may originate from a scheduled trigger, from any client, or from the system's own activity.
**Attribution to a human message is not required and is not a control.**

### 2. The control is budget, not attribution

What §9 was really protecting against — a system spending without anyone watching — is handled by the
spend governor (ADR-033 §5): ceilings over four windows, attended and unattended budgets held
separately, checked before the call, persisted, failing closed.

Attribution never actually controlled spend; it controlled *shape*. Budget controls spend directly,
which is the better instrument.

### 3. The licensing question is recorded as an accepted judgement

§9's real purpose was to stand in for an unanswered question: subscription plans are sold for a human
using them interactively, and autonomous calls on a subscription are a grey area.

**The owner's position, recorded as a judgement rather than a resolution:** all work in this system is
ultimately owner-instructed, at one remove or several, and the usage stays within the spirit of what
the subscription is for. The owner accepts this.

It is written down this way deliberately. In a year a reader needs to know this was **decided**, with
reasoning, rather than never noticed — the same standard ADR-026 applied when it first lifted the rule.

### 4. Metered versus subscription becomes a cost question

With licensing accepted, the choice between a metered provider and a subscription is about cost,
capacity, latency and eligibility — not about permission. That simplifies layer 7: the router weighs
providers on their properties, without a licensing rule cutting across them.

ADR-026 §5's per-provider `unattended` eligibility field stays. It remains useful for providers whose
terms genuinely differ, and for turning a provider off for autonomous work without turning it off.

## Alternatives considered

**Route all autonomous work to metered inference.** Recommended by the assistant and **not adopted**.
It would retire the grey area entirely, and it costs money the subscriptions already cover. The owner
judged the licensing position acceptable, which makes the spend unnecessary. Recorded because it
remains the clean fallback if the judgement in §3 ever needs reversing.

**Keep §9 and carve out exceptions.** Rejected: a prohibition with more exceptions than cases is worse
than no rule, and it reads as a constraint to anyone who finds it later.

**Require a human to confirm each scheduled run.** Rejected — that is attribution again, and it defeats
scheduling.

## Consequences

**Easier.** Scheduled work, system-initiated work and client-initiated work are all ordinary. No
component needs to manufacture an attribution to be allowed to run.

**Harder.** The budget is now the only thing between the system and unbounded spend, so the governor
stops being a safety net and becomes a load-bearing control. It must exist before any metered call
(ADR-033 §5) and it must fail closed.

**Accepted risk:** the licensing judgement in §3. It is the owner's to make and it is reversible — the
mechanism for reversing it is §4's eligibility field plus the rejected alternative above.

## Validation / revisit trigger

1. A scheduled trigger produces a model call with **no human message anywhere in its lineage**, and
   the call is recorded with its true origin rather than an invented one.
2. The same call with the budget exhausted is **refused before the call**, not after.
3. Unattended spend does not consume attended headroom — proved by exhausting one and using the other.

**Revisit if:** a provider's terms change materially; autonomous volume becomes large enough that the
usage stops resembling interactive use; or the system begins acting for someone other than the owner,
which changes whose instruction is at the root of the chain.
