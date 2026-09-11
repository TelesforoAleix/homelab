# ADR-033: Vercel AI Gateway as the metered model provider, reached over plain HTTP

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** none. This is the provider decision **ADR-026 §1 deferred**, and it closes that
  section's open question.
- **Superseded by:** none

## Context

ADR-026 §1 decided that metered, per-token access becomes the target substrate and then deliberately
named no vendor:

> *"**No provider is named in this ADR.** Azure, an aggregating gateway, and direct APIs are all
> open. That choice needs evidence — model variety, cost, and EU data handling — and belongs to the
> phase that makes it, recorded as its own ADR."*

The evidence now exists. `docs/handovers/2026-09-11-model-strategy.md` is a market and
economics survey covering model variety and cost in depth, together with a week of the owner's own
measured usage. This ADR is the decision ADR-026 §1 asked for.

**Two facts from that survey shape this decision more than any leaderboard position.**

First, **the observed workload is overwhelmingly cache reads** — 485.7M of 499.3M tokens, 97.27%.
That reorders cost comparisons in ways headline pricing hides: two models with identical
input/output prices can differ twofold in total cost because their cache-read prices differ
fourfold. Cost therefore has to be modelled as a shape, not a rate.

Second, and cutting the other way: **that measurement comes from development traffic that is
deliberately staying on subscriptions** (strategy §9). Runtime Home Lab traffic — a Telegram
question, a retrieval query, an agent task — has a different and currently unmeasured cache profile.
The cache-economics ordering is a prior, not a finding about the traffic this gateway will carry.

## Decision

### 1. Vercel AI Gateway is the metered provider

Chosen for the **ecosystem and the routing surface**, not for being cheapest: one integration
reaching many models and providers, with per-model routing, provider failover and usage reporting at
the gateway.

**Model choice becomes configuration underneath it**, which is what ADR-026 §2 already requires —
adding a model is a config change, adding a *provider* is code. A gateway makes "adding a model"
genuinely trivial, which is the property that matters as the landscape moves.

### 2. It is reached over plain HTTP from Python, not through an SDK

`urllib.request` and `ssl`, the same way `services/telegram-bot/bot.py` already talks to the Telegram
Bot API. **No third-party dependency is added.**

This was decided against two alternatives and is not merely inherited:

- **The Vercel AI SDK is TypeScript.** Using it means installing Node on a node that has none, a
  second runtime beside Python, and an npm dependency tree on a machine with no encryption at rest
  (ADR-032). It buys ergonomics, not data: token counts, cache read/write and tool calls all arrive
  in the HTTP response body regardless of client.
- **`ai-python.dev` (vercel-labs) exists** and the node's Python 3.14.4 clears its 3.12 requirement.
  It is not adopted **yet** — it is a `vercel-labs` project with no version, release date or
  stability designation in its documentation, and it reads its key from `AI_GATEWAY_API_KEY`, an
  environment variable. This repository refuses environment variables for secrets on purpose; the
  bot's unit file states why: *"Anything that can read `/proc` or run `systemctl show` can read an
  environment variable… variables leak into crash dumps, `systemctl show`, and logs."*

**Plain Python is expected to be fast enough**, and where it is, simplicity wins — ADR-006.

### 3. The gateway is one backend behind an abstraction, never the whole of it

```text
InferenceProvider
├── gateway         Vercel AI Gateway        (this ADR)
├── claude_cli      subscription             (existing, ADR-025)
├── codex_cli       subscription             (existing, ADR-025)
└── self_hosted     reserved: cloud GPU, then local
```

The abstraction is not speculative tidiness. It is what lets the future inference-compute direction
(`docs/handovers/home-lab-future-inference-compute-handover.md`) arrive as configuration rather than
a rewrite, and it is the escape hatch if the gateway's economics, availability or routing stop
serving the project. **Nothing above this boundary may name a provider.**

It also means the `ai-python.dev` question stays reversible: adopting it later changes one backend
implementation and nothing else.

### 4. Development stays on subscriptions; the gateway serves the runtime

```text
building the Home Lab      -> Codex / Claude Code subscriptions
the Home Lab runtime       -> gateway
```

Strategy §9, and it follows from the measurement: development agents consume hundreds of millions of
cached tokens, and moving that to metered access for architectural tidiness would be expensive for
no gain. ADR-025 §5's accepted risk is unchanged.

### 5. No paid call is made before the spend governor exists

**This is a precondition, not a later improvement.** Metered access plus system-initiated work is the
combination that can spend money while nobody is watching.

The governor must:

- enforce configurable ceilings over **four windows — hour, day, week, month**;
- hold **separate budgets for attended and unattended work**, per ADR-026 §6, so autonomous activity
  cannot consume the owner's own headroom;
- check **before** the call, so a refusal costs nothing — the Phase 09 caps precedent;
- persist across restart;
- **fail closed.** If a counter cannot be read, the call is refused rather than estimated.

The numeric ceilings are not set here; they are configuration and belong to the phase that builds it.

### 6. What this ADR does not decide

- **The route vocabulary.** `utility`, `general_tools`, `reasoning_cached` and the rest are a task
  vocabulary, and ADR-026 §4 puts the declaration form in ADR-027's hands. It is settled once
  Phase 19 is settled, and the strategy document's names are a proposal, not a decision.
- **Which models fill which route.** Configuration, decided by evaluation.
- **What may leave the machine.** ADR-025 §8 currently permits only the question and the `/status`
  figures. A gateway carrying assembled context is a substantial widening, and §8 requires its own
  ADR for that. It is the immediate next decision and this one does not pre-empt it.

## Alternatives considered

**Direct provider APIs, one integration each.** No intermediary, no margin, and the provider sees
exactly what you send with nobody in between. Rejected: it makes "add a model" a code change in
every case, which is precisely what ADR-026 §2 decided against, and it multiplies credentials — one
secret per vendor, each with its own rotation and blast radius.

**Azure**, named in ADR-026 §1. A serious option on data handling and EU residency, and the right
answer if the project ever holds data belonging to someone other than the owner. Rejected here
because the model catalogue is narrower and the operational overhead is larger than a home lab
justifies today. **This is the alternative to revisit first** if the data position changes.

**Another aggregating gateway.** Comparable in shape. Vercel is chosen for the surrounding ecosystem;
the abstraction in §3 means a different aggregator is a backend swap rather than a redesign.

**The TypeScript AI SDK**, and **`ai-python.dev`** — both addressed in §2.

## Consequences

**Easier:** one credential instead of one per vendor. Adding or swapping a model is a configuration
edit. Provider failover exists without being built. Usage reporting arrives at the gateway for free.

**Accepted, and named rather than glossed:**

- **A third party sees every prompt the runtime sends.** The owner's position, recorded 2026-09-11:
  the content is public information, the owner's own material, or already generated by an AI, and
  this is not a service offered to anyone else. EU data handling was one of ADR-026 §1's three
  criteria and is answered by that scope, not by a residency guarantee. **If the project ever
  processes a third party's data, this ADR must be revisited before it does.**
- **One key unlocks every model.** Smaller credential surface than N vendor keys, and a larger blast
  radius if it leaks. It is handled exactly like the bot token — file at 0600, delivered by
  `LoadCredential=`, never an environment variable.
- **Vendor concentration.** Pricing, routing and availability now depend on one intermediary. §3 is
  the mitigation and it only works if it is respected in code.

**Newly required:** the spend governor (§5), and cost telemetry to make it meaningful — tokens by
class including cache read and write, cost, latency, model, provider, success. Without the telemetry
the governor is guessing, and the cache-ratio question in Context stays unanswered.

**Unblocked:** system-initiated messages. Telegram becomes bidirectional rather than strictly
request/response, which means model calls that nobody just asked for — the exact case ADR-026 §3's
`unattended` field exists to gate. Push and the governor ship together or not at all.

## Validation / revisit trigger

Revisit when:

1. **The project processes data belonging to anyone but the owner.** The §Consequences scope is doing
   the work that a residency guarantee would otherwise do. Azure is the first alternative to re-examine.
2. The gateway's margin becomes material against measured spend, or a needed model is not routed.
3. **Measured runtime cache ratio differs materially from the 97% development figure** — that would
   reorder the cost comparison this decision was informed by.
4. `ai-python.dev` reaches a stable release, or the plain-HTTP client proves insufficient.
5. Self-hosted inference becomes real, at which point `self_hosted` stops being a reserved slot.

**The check that this decision is holding:** no module above `InferenceProvider` names a provider or a
model; adding a model is a configuration diff with no code change; and no paid call can be made with
the spend governor absent or unreadable.
