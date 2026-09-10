# ADR-027: The Agent Contract

- **Status:** Accepted
- **Date:** 2026-09-10
- **Supersedes:** none
- **Superseded by:** none

## Context

Two systems have been built independently and now need to meet.

**Homelab has a runtime.** `services/telegram-bot/router.py` holds a registry of `Executor`
entries, each declaring a `Capability` (`READ`, `PRIVILEGED`, `UNAVAILABLE`), dispatched through a
single authorisation boundary. Two allowlists separate *may you use the bot* from *may you invoke
this executor*, with the second enforced as a subset of the first at load time. The router's own
docstring anticipates this moment: *"Phase 10 adds knowledge retrieval, Phase 12 adds automation."*

**The Factory has definitions.** `04-agents/role-registry.md` defines, per role: authority, ticket
powers, review and release authority, and explicit boundaries such as *"cannot approve own execution
or release"*. These are operating contracts written in prose for a human or a coding agent to read
in an editor. They are not loadable by anything.

The gap is not a missing design. It is a missing **form** — a way for Factory to declare an agent
such that homelab can read it, and a rule for what homelab does with that declaration.

Two constraints from ADR-025 remain shut and this ADR is the key to both:

- **the model gets no tools** — verified in Phase 09 with a canary file against a positive control;
- **model output is never dispatched** — proved by making a model emit `/restart ssh.service`, which
  it did, with no effect.

Those are security decisions, not licensing ones, and ADR-026 does not touch them. Opening them
requires knowing which agent may use which tool — which is exactly what this ADR defines.

## Decision

### 1. There are two kinds of agent, and they live in different repositories

| | Repository | Purpose | Examples |
|---|---|---|---|
| **System agents** | `homelab` | Operate the OS itself | agent selection, model selection, context assembly, request decomposition, review routing |
| **Work agents** | `factory` | Do work on a project | Execution Agent, Review/QA Agent, Release Agent, Product/Feature Owner |

**The test: does it survive The Factory being swapped out?** A component that chooses *which* agent
to call is homelab. An agent that writes a PRD is Factory.

The *selection logic* belongs to homelab; the *catalogue it selects from* belongs to Factory. A
homelab system agent reading Factory manifests and choosing among them is this contract working as
intended, not an exception to it.

### 2. An agent declares five things

```yaml
agent: review-qa
context:      [ticket, diff, acceptance-criteria]   # what it needs to see
skills:       [fresh-context-review]                # procedures it follows
tools:        [read_repo, post_review]              # what it may actually do
model_policy: fresh-context-review                  # the KIND of model it needs
unattended:   true                                  # may it run without a human
```

**An agent never names a model.** It declares a need — "cheap classification", "fresh-context
review" — and the router selects per ADR-026 §4. This is what makes models pluggable, and it is why
the same definition runs on a different model tomorrow without being edited.

### 3. Factory declares; homelab enforces

**The tool vocabulary and its capability levels belong to homelab**, because homelab is what
enforces them. Factory composes agents from that vocabulary. A manifest is a *request*, never a
grant.

This direction is the whole point. Enforcement written into the manifest would mean the fast-moving
catalogue could widen its own permissions, which is the opposite of a contract.

### 4. Declared tools are intersected with caller authorisation

Phase 08 established two allowlists — authentication and authorisation — with the second enforced
as a subset of the first at load time. This ADR adds a third term, evaluated at dispatch:

```text
effective tools = agent.tools  ∩  what this caller is authorised for
```

An agent may never exceed its declared set, **and** may never exceed what the human on whose behalf
it acts could have done directly. An agent is not a privilege escalation path.

The check happens in `Router.dispatch()`, which the existing docstring already names as the single
authorisation boundary: *"nothing else in the codebase is permitted to decide entitlement."* That
property is preserved, not extended sideways.

### 5. An unknown tool name is a refusal, not a warning

If a manifest names a tool the homelab vocabulary does not contain, the agent **fails to load**.
It does not load with that tool silently dropped.

This is deliberate and follows the project's own hard-won rule that fixes must be structural rather
than intentional. A dropped-tool warning is a message nobody reads at 3am; a load failure is a state
that cannot be ignored. It mirrors `load_ids()`, where an empty required allowlist is fatal because
an empty file must never mean "allow everyone".

### 6. Tools open per agent, never globally

ADR-025's locks are not lifted wholesale. They open **one agent at a time**, each time by adding a
declared tool to a specific manifest, with the reason recorded.

The first agents should be advisory — they read and recommend, the human acts. This matches how The
Factory already classifies most of its own roles: *"Advisory-only role: reads, synthesizes,
recommends, or routes without mutating code, docs, ops state, or release state by default."*

**Anything destructive additionally requires approval at the moment of action**, not merely a
declared tool. Phase 08's `/restart` grant — one user, one unit, one verb — is the shape to copy,
and the reason it is reviewable is that it is narrow.

### 7. The prose specification remains the source of truth for humans

A manifest sits **alongside** the existing role specification, not instead of it. `role-registry.md`
and the individual role specs keep explaining *why* a boundary exists; the manifest states it in a
form a machine can enforce. Neither is generated from the other, and where they disagree that is a
bug to be reconciled, not a precedence rule to be invoked.

## Alternatives considered

**Homelab keeps its own agent registry and merely references Factory as documentation.** Simplest,
and it leaves the current router untouched. Rejected: every new Factory agent would require a
homelab code change, coupling a catalogue that is meant to change constantly to a runtime that is
meant to be stable. That is precisely the coupling the two-repository split exists to prevent.

**Factory owns the capability levels too, and homelab just executes what it is told.** Rejected
outright. Enforcement must live where it is enforced. A public, fast-moving definitions repository
that can grant itself privileges is not a contract — it is a configuration file with a security
boundary written on it.

**Generate the manifest from the prose specification.** Attractive, and rejected for now: it would
require the prose to become structured enough to parse reliably, which would damage the thing that
makes those specs useful. Revisit if manifest and prose drift often in practice.

**One capability level per agent, matching today's `Executor.capability`.** Rejected: a single enum
per agent cannot express "may read the repository but may only post a review", which is exactly the
distinction the Factory role boundaries already make.

## Consequences

**Easier:** adding an agent becomes a Factory change with no homelab deployment. Tool use can be
opened incrementally with a reviewable diff per agent. Model substitution stops touching agent
definitions at all.

**Harder / newly required:** homelab must maintain a named tool vocabulary as a stable public
interface. Renaming a tool becomes a breaking change for every manifest that names it — which is
the correct cost, but it is a cost.

**Newly required:** `Executor` gains a set-valued notion of permitted tools per caller, which is the
second change to that class since Phase 08. Phase 09's precedent applies — the change is additive
with defaults, so no existing executor is altered, and the reason is recorded rather than smuggled
in through module-level state.

**Constrained:** an agent can never do more than the human it acts for. This forecloses "service
agents with their own elevated identity" as a design, deliberately, and consistently with the
credential boundary ADR-025 §1 established.

**Deferred:** how the knowledge base is queried by an agent — that is ADR-030, written alongside
Phase 10 when retrieval is concrete enough to specify honestly. Also deferred: the approval
mechanism for destructive actions in §6, which needs a real destructive action to design against.

## Validation / revisit trigger

Revisit if:

- the five declared fields in §2 prove insufficient for a real agent — likely candidates for a sixth
  are budget and latency;
- prose specifications and manifests drift repeatedly, suggesting generation is worth reconsidering;
- an agent legitimately needs to act with authority the calling human lacks, which would mean §4 is
  wrong rather than merely inconvenient.

**Validation required before this ADR is considered implemented**, each proved against a positive
control rather than observed to pass:

1. A manifest naming an unknown tool **fails to load** (§5).
2. An agent invoking a tool outside its declared set is **refused, on the reason** (§4).
3. An agent acting for a non-privileged caller cannot invoke a `PRIVILEGED` executor **even when it
   declares that tool** (§4).
4. The canary-file check from Phase 09 still passes for any agent with no declared tools —
   confirming the default remains "no tools" rather than becoming "all tools".

An authorisation check that has only ever permitted is unvalidated.
