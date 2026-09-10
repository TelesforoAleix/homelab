# ADR-026: Multi-provider model access and routing

- **Status:** Accepted
- **Date:** 2026-09-10
- **Supersedes:** ADR-025 §9 (owner-initiated calls only)
- **Superseded by:** none

## Context

Phase 09 connected the model executor using the owner's two personal subscriptions, and did so
under a constraint rather than an answer. ADR-025 §9 required that **every model call be
owner-initiated** — traceable to a message the owner had just sent — because whether automating a
personal Claude Pro or ChatGPT subscription falls within either provider's terms had not been
established, and could not be established by reading a CLI's `--help`.

That constraint has become load-bearing in a way Phase 09 anticipated. The owner has now described
the system this project is actually building:

- **many models, not two.** Ten to twenty, reached through a metered provider or gateway, so their
  behaviour can be compared;
- **routing by task**, where the system chooses the model rather than the caller naming one;
- **request decomposition**, where a single message becomes several sub-calls — draft, review,
  check — which need not run on the same model;
- **agents that operate**, which by definition make calls no human triggered individually.

Every one of those requires calls that ADR-025 §9 forbids. The constraint was written to defer a
question; the architecture now needs it answered.

Two further facts shape the decision.

**ADR-008 already anticipated this.** Its text reads: *"Introduce direct API billing intentionally
in later experiments."* It is a sequencing decision — start with subscriptions — not a prohibition
on metered access. The Phase 09 handover compressed it to "no API keys, no paid overage", which is
stricter than what ADR-008 says. This ADR is ADR-008's later experiment arriving, not a reversal
of it.

**Phase 15 has already started by accident.** `services/model-helper/providers.py` is a
two-provider router with independent per-provider limits and fallback proved against a genuinely
exhausted provider. The structure exists. What does not exist is models as *configuration* rather
than two entries hardcoded in Python.

## Decision

### 1. Metered providers become the target substrate; the vendor is not chosen here

The project moves toward metered, per-token model access as the primary path, because that is what
supports many models and unattended execution without a terms question.

**No provider is named in this ADR.** Azure, an aggregating gateway, and direct APIs are all open.
That choice needs evidence — model variety, cost, and EU data handling — and belongs to the phase
that makes it, recorded as its own ADR.

### 2. Models are configuration, not code

The router reads a registry. Adding a model is a configuration change; adding a *provider* is code.
Callers never name a model.

### 3. Every provider entry carries an `unattended` eligibility field

```text
provider: claude-cli    unattended: true    # subscription — see §5
provider: codex-cli     unattended: true    # subscription — see §5
provider: <metered>     unattended: true    # metered — no terms question
```

**The router enforces this structurally.** A call that declares itself unattended, routed to a
provider marked `false`, is refused before the call is made — the same shape as the Phase 09 caps,
which are checked before the call so a refusal costs nothing.

The field exists even though every current entry is `true`. That is deliberate: it keeps the
decision **visible and reversible one provider at a time**, which a global rule does not.

### 4. Agents declare a need, not a model

An agent declares what it requires — "cheap classification", "fresh-context review" — and the
router selects. This is what makes models pluggable, and it is why the same agent definition can run
on a different model tomorrow without being edited. The declaration form is ADR-027's business.

### 5. Subscription providers may serve unattended calls, as an accepted risk

**Decided by the owner on 2026-09-10, against the assistant's recommendation, and recorded as a
disagreement rather than a consensus.**

The owner's reasoning: exposure is bounded by rate limiting, the system is reachable only by the
owner over Tailscale, and the move to a metered provider is coming regardless — so the interim risk
is small and time-limited.

The assistant's reasoning, recorded because ADR-025 §9 existed for it: **rate limiting bounds
capacity, not terms.** How many calls are made is a different question from what the subscription
may be used for, and access control does not answer it either — the providers observe a usage
pattern, not a network topology. The residual risk is account action or throttling rather than
anything legal.

Both are written down. The owner's decision stands, and §3's mechanism is what makes it reversible
without redesign.

### 6. Unattended work must not consume the owner's allowance

Independent of terms, and not a matter of opinion: the bot and the owner draw from the same bucket.
Phase 09 recorded **both** subscriptions hitting their limits during implementation, partly consumed
by that phase's own verification.

An unattended loop that exhausts a provider overnight blocks the owner's own work the next morning.
Therefore, on subscription providers:

- unattended work carries a **lower cap** than interactive work, or
- a **floor is reserved** for owner-initiated calls that unattended work cannot spend.

Whichever is implemented, the caps stay per-provider and enforced before the call, as Phase 09
established.

## Alternatives considered

**Keep ADR-025 §9 as a global rule until a metered provider is live.** Safest, and it was the
assistant's recommendation. Rejected by the owner: it blocks the decomposition and agent work that
motivates the whole architecture, in exchange for a risk the owner judges small and temporary.

**Establish the subscription terms position directly.** Attractive because it would close a question
open since Phase 07. Rejected as impractical — Phase 09 already tried and recorded that it cannot be
resolved from product documentation — and because the answer stops mattering once the project is on
metered access.

**Drop the subscription CLIs once a metered provider exists.** Rejected. They are already installed,
already authenticated, and cost nothing marginal. They remain useful as fallback capacity and as the
comparison baseline that ADR-007's model-agnostic principle wants.

**Route by naming models at the call site.** Rejected: it couples every agent to a specific vendor's
model names, which is what ADR-007 exists to prevent.

## Consequences

**Easier:** unattended execution, scheduled work, agents that make their own follow-up calls, and
review steps that run on a different model from the work being reviewed. Adding a model becomes a
configuration line.

**Harder / newly required:** the router gains an enforcement responsibility it did not have, and
that enforcement must be tested by proving a refusal, not by observing permitted calls succeed.

**Constrained:** the licensing question is not resolved — it is *accepted as a risk on subscription
providers only*, and the `unattended` field is the control that keeps it revocable. Any future
finding that a provider's terms forbid this can be applied by changing one field, per provider,
without touching architecture.

**Deferred:** which metered provider, and when. Also deferred: tool use by models and dispatch of
model output, which are **security** questions and are not touched by this ADR. ADR-025's other
properties — the credential boundary in §1, and the bounded context in §8 — **survive intact**.

**Cost:** metered access introduces the project's first usage-based AI spending. The budget ledger
must gain a usage-based line when the provider is chosen, per `PROJECT.md` §10.

## Validation / revisit trigger

Revisit if:

- a provider's terms are found to explicitly permit or forbid automated subscription use — in either
  direction, set that provider's field and record the finding;
- unattended work is observed exhausting a provider ahead of the owner's own use, which would mean
  §6's cap or floor is set wrong;
- a metered provider is selected, at which point the subscription entries should be reconsidered on
  their merits rather than left `true` by inertia;
- account action or throttling is observed on either subscription.

**Validation required before this ADR is considered implemented:** the refusal path in §3 must be
proved with a fixture provider set to `unattended: false`, against a positive control. An
eligibility check that has only ever permitted is unvalidated — the project has recorded nine
instances of checks reporting results they could not support.
