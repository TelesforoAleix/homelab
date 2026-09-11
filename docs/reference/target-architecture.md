# Target Architecture — the Home Lab AI Operating System

- **Written:** 2026-09-11
- **Status:** Living document. It describes **the end state we are building toward** and the current
  truth of each layer.
- **Standing:** This is not an ADR and it does not decide anything. Where it disagrees with an
  accepted ADR, the ADR wins and this document is wrong. It is the map every later phase is
  measured against; a phase that changes a layer updates its section here.

## What this document is for

The roadmap answers *what do we do next*. The ADRs answer *what did we decide, and why*. Neither
answers **what is this system supposed to be when it is finished**, and without that answer the
layers drift into each other and a phase can claim work that belongs to another.

Each layer below states its responsibility, what it must **not** do, what it receives and hands on,
what exists today, what constrains it, how it behaves when something it depends on is missing, and
what is still open. That is a map of intent and current truth, held separately from the decisions
that produced it.

## 1. The end state, in a paragraph

**Home Lab is the central AI operating system.** It runs continuously and listens. A request arrives
from one of several clients, and Home Lab decides what kind of request it is, whether it splits,
which services handle each piece, what information is needed and where from, what the model actually
sees, which model runs it, on which inference source, and what happens to the result — with budgets,
approvals, identity and audit applying throughout. It holds the knowledge. It orchestrates the AI.

It performs the work a coding agent such as Codex or Claude Code normally performs **internally**:
context selection, task decomposition, retrieval decisions, per-call model selection and controlled
execution. That is the measure of what belongs in it.

## 2. Clients are not layers

**The Factory is a consumer of this system, not a part of it.** It is an AI software-development
platform that needs AI capabilities; the owner's primary use of it is coding. It sits beside the
other clients, not above them.

This matters more than it reads. If the harness is designed around Factory's needs it stops being
general, and Factory's assumptions leak into the core where they cannot be removed later.

| Client | State | Notes |
|---|---|---|
| **Telegram** | Built (Phases 07–09) | Long-polling, so no listening socket (ADR-023) |
| **Scheduler** | Not built | A *client*, not a subsystem — a scheduled task is a request with no human waiting |
| **Factory / Workbench** | Workbench built, provisional (Phase 20.0) | Reaches the harness through a configured adapter (ADR-035 §4) |
| **Voice** | Not built (Phase 17) | A modality over an existing client, not a client of its own |

**"Always running" is a requirement on the system, not a layer.** The server is up and listening;
what varies is what wakes it.

## 3. The layer map

```text
   Telegram    Scheduler    Factory    Voice          ← clients
        └───────────┴───────────┴─────────┘
                        │
                        ▼
   ┌──────────────────────────────────────────────┐
   │ 1  Entry            accept, identify, normalise │
   │ 2  Understanding    what kind of request is this│
   │ 3  Decomposition    does it split, into what    │
   │ 4  Service routing  who handles each piece      │
   │ 5  Information      web · brain · repos · system│
   │ 6  Context + cache  what the model actually sees│
   │ 7  Model selection  which model for this call   │
   │ 8  Execution        which inference source       │
   │ 9  Result handling  to whom, recorded where     │
   └──────────────────────────────────────────────┘
        │                                    │
   governance: identity · budgets ·     observability
   approvals · audit · refusals · trust
```

Layers are not equal in size. 5, 6 and 8 are large enough to need sub-phases of their own; 1, 2 and 9
are comparatively small. **Research required is a better splitting criterion than lines of code.**

---

## Layer 1 — Entry

**Responsibility.** Accept a request from a client, attach the runtime's own record of who and where
it came from, and hand a normalised request onward.

**Must not.** Interpret the request. Decide what to do with it. Hold a credential for anything
downstream. Trust anything the client says about identity.

**Receives** a client-shaped message. **Hands on** a normalised request plus an attached origin and
identity that the request itself cannot set (ADR-034 §11).

**Today.** The Telegram bot and its router/executor exist and work, with two allowlists and one
privileged action. `Router.dispatch(user_id, text)` takes Telegram command text — it is a **command**
router, not a request endpoint, and should not be mistaken for this layer.

**Constraints.** Always listening. Never root, never a user-facing service as root. ADR-023's
no-listening-socket property is worth preserving where it can be.

**Degraded.** One client being unavailable must not affect the others. A scheduled trigger that fires
while the system is busy queues; it does not double-execute, and a trigger fires once however many
processes are running.

**Open.** One endpoint with per-client adapters, or per-client endpoints? Whether the scheduler is a
component here or a separate service that acts as a client.

---

## Layer 2 — Understanding

**Responsibility.** Decide what kind of request this is: a question, a task, a command, a project
instruction, an ongoing conversation. Decide whether it needs decomposition at all.

**Must not.** Execute anything. Choose a model. Gather information. Answer the request.

**Receives** a normalised request. **Hands on** a classification plus a bounded restatement of what
is being asked.

**Today.** Nothing. This is a **gap** — no phase covers it.

**Constraints.** It must be cheap and bounded, because it runs before any budget decision has been
informed by what the work actually is. If classification itself needs a model call, that call is the
first spend of the request and must be the smallest one.

**Degraded.** Unclassifiable is a valid outcome and routes to a default path, not to a failure.

**Open.** Deterministic rules, model-assisted, or both? What the taxonomy actually is — that list is
a design exercise, not an implementation detail. Whether classification and decomposition are one
step or two.

---

## Layer 3 — Decomposition

**Responsibility.** Split a request into steps, order them, and mark which need their own service,
agent or context.

**Must not.** Choose models. Assemble context. Execute.

**Receives** a classified request. **Hands on** an ordered set of steps with dependencies.

**Today.** Nothing.

**Constraints.** Each step must be individually checkable, because a step that cannot be verified
cannot be retried safely. Steps inherit the parent request's budget rather than each getting a fresh
one — otherwise decomposition becomes a way to multiply spend.

**Degraded.** A request that does not decompose is a single step. That must be the cheap common case,
not a special case.

**Open.** Deterministic, model-assisted, or both — the routing precedent (start deterministic, keep
it as the fallback) is a strong prior but not a decision. What happens to later steps when an early
one fails or is refused.

---

## Layer 4 — Service routing

**Responsibility.** Decide which service handles each step: web research, knowledge retrieval, code
execution, a specialist agent, a direct model call.

**Must not.** Choose the model — that is layer 7. Execute. Grant a capability that was not already
approved.

**Receives** steps. **Hands on** each step addressed to a service.

**Today.** Nothing. The Telegram router dispatches *commands*, which is a different problem.

**A distinction worth fixing now.** A **service** is a long-lived provider of a capability. A **tool**
is a single callable action. Layer 4 routes to services; tools are what a service exposes. Conflating
them is how a tool registry becomes a service registry by accident.

**Constraints.** This is where ADR-034 §2's capability-to-tool mapping lives, and ADR-034 §10 makes
each new mapping a human-approved security decision. A capability the backend cannot satisfy fails
**before activation**, naming every missing requirement (ADR-034 §6).

**Degraded.** A service being unavailable is a refusal with a reason, never a silent substitution.

**Open.** Whether "capability" and "service" are the same granularity. How a specialist with its own
narrow authority (ADR-034 §8) is addressed.

---

## Layer 5 — Information gathering

**Responsibility.** Obtain the material a step needs — **with provenance** — from the web, the
knowledge base, project repositories, or system state.

**Must not.** Decide what is relevant to the final answer (layer 6). Confer trust. Let retrieved text
become an instruction.

**Receives** an addressed step. **Hands on** material plus, for every item, where it came from, when,
and at what revision.

**Provenance is a first-class output, not metadata.** Everything downstream — the trust state in
layer 6, the citation in layer 9, the audit record — depends on it existing from the start. It cannot
be reconstructed later.

**Today.** Nothing.

| Source | State |
|---|---|
| **Web / online research** | **Gap.** No phase covers it anywhere in the roadmap |
| **Knowledge base (Brain)** | Phase 10 and its sketched sub-phases; unbuilt |
| **Project repositories** | Blocked on the node by ADR-032 §2 |
| **System state** | Exists — the `/status` figures |

**Constraints.** **ADR-032 §2** forbids the knowledge base, any project repository, product source or
`ops/` record on the node — *including a derived index or embedding*. **ADR-025 §8** permits only the
question and the `/status` figures to leave the machine; anything more needs its own ADR, which
ADR-033 §6 names as the immediate next decision. These two together decide *where this layer can run*
before they decide anything about how it works.

**Degraded.** Missing embeddings, a dead search provider or an unreachable knowledge store removes a
source and says so. It does not crash the request and does not silently answer from less.

**Open.** Whether the Brain specialist queries retrieval itself or delegates to a Brain-native agent —
deliberately unresolved by the Phase 19 design review; do not invent an answer. How web content is
bounded, since a fetched page is unbounded attacker-influenced text.

---

## Layer 6 — Context assembly and cache

**Responsibility.** Decide what the model actually sees, and in what order.

**Must not.** Gather (layer 5). Trust what it assembles. Reorder the stable prefix for convenience.

**Receives** material with provenance. **Hands on** an assembled context plus a trust state.

**Two mechanisms this layer owns.**

**The stable prefix.** Cache economics are *engineered, not inherited*. The favourable numbers
observed in comparable harnesses are a property of their prefix discipline, not of the models they
call — the invariant part first, the volatile part last, and never reordered to make an
implementation simpler. This is the assumption most likely to be made silently and found false after
the cost model has been built on it.

**Trust as a runtime state.** Retrieved content is untrusted data (ADR-034 §11) — text does not become
an instruction because it uses imperative language. Beyond labelling it, **the arrival of untrusted
content arms an action gate**: high-impact tool calls later in the same run require exact approval
that they would not have required otherwise. Trust is therefore a runtime state that changes, not a
fixed label — the marking does work rather than decorating a prompt.

**Today.** Nothing.

**Constraints.** ADR-025 §8 is the hard boundary — this layer decides what leaves the machine, so the
egress ADR gates it. The instruction hierarchy is fixed: homelab policy → agent definition → project
policy → work-item instructions → retrieved context as untrusted data.

**Degraded.** Over-budget context is trimmed by a stated rule with the trimming recorded, never by
dropping whatever was last.

**Open.** What the stable prefix contains. Whether compaction is summarisation (a model call, and
therefore spend) or truncation.

---

## Layer 7 — Model selection

**Responsibility.** Choose which model serves this call.

**Must not.** Accept a model, provider, tier or path from an agent (ADR-034 §5). Let an agent's own
assessment of its work reach a model tier. Bypass the pre-call budget check.

**Receives** the agent role, a bounded task summary, validated metadata, and capability/context
characteristics. **Hands on** a chosen model and route.

**Today.** `services/model-helper/` — 714 lines, a two-provider router with per-provider limits and
automatic fallback, tested against a genuinely exhausted provider. What does not exist is models as
**configuration** rather than two entries in Python.

**Constraints.** **ADR-026 §4 survives ADR-034**: the agent declares a need and the router selects —
only the *form* changed. **The agent's role is its declaration of need.** Priority, severity and
complexity are **hints, never selectors**: they cannot reach a tier on their own, because an agent's
claim about its own work is data, not an instruction. Without that rule an agent routes itself to an
expensive model by asserting its task is hard, and the governor notices after the money is spent.

**Degraded.** No eligible model is a refusal with a reason. Fallback is explicit and recorded, and
once a route has produced substantive output it is **pinned** — mid-answer switching produces results
nobody can reason about afterwards.

**Open.** Whether the AI-assisted router is worth building at all. Deterministic selection from the
role may be sufficient for a long time, and deterministic routing is the fallback regardless.

---

## Layer 8 — Execution

**Responsibility.** Run the call against an inference source and normalise what comes back.

**Must not.** Give any raw provider process ambient filesystem, shell, credential or OS tools
(ADR-025). Dispatch model output. Make a metered call before the spend governor exists (ADR-033 §5).

**Receives** an assembled context and a chosen model. **Hands on** a normalised result with usage.

**Four inference sources, one selection problem:**

| Source | State |
|---|---|
| **Subscription CLIs** (Claude, Codex) | Built. Interactive, `aleix`-scoped, neither is a service |
| **Metered gateway** (Vercel AI Gateway) | Decided (ADR-033), unbuilt. **Governor first** |
| **Cloud compute** | **Gap.** Named as a direction, in no phase |
| **Own GPU node** | Phase 16, conditional |

**Constraints.** Provider capability and **model** capability are different facts — a provider may
support tools while a specific model it serves does not. Unknown cost stays `unknown` and is never
replaced with a confident estimate.

**This is where the largest security change on the roadmap happens.** ADR-034 §13 converts ADR-025
§10's *"the model's output is never an instruction"* from **inert by architecture** to **checked by
runtime**: only a structured request enters the trusted runtime, and identity, assignment, scope,
mapping, budget and approval all run before any action. Until that ships, §10 stands as written and
the Phase 09 canary check applies.

**Degraded.** A provider being exhausted or unreachable is a normal operating state with a legible
message, never an outage.

**Open.** Which real adapter first. Whether cloud compute is a provider or a deployment target.

---

## Layer 9 — Result handling

**Responsibility.** Return the result to the right place and record what happened.

**Must not.** Let a result become an instruction for the next step without passing the trust rules.
Store hidden chain-of-thought.

**Receives** a normalised result. **Hands on** a reply to the client and durable records.

**Today.** The Telegram reply path. Nothing general.

**Constraints.** Durable state is explicit (ADR-034 §12): agents are stateless between tasks, and
anything needed later becomes a record in Factory definitions, project `ops/`, or Brain. Task history
stores observable decisions, rationale, messages, tool requests and results, evidence, approvals,
model usage, cost and outputs — **not** hidden reasoning.

**Degraded.** A result that cannot be delivered is still recorded.

**Open.** Where results live per client. What gets promoted into Brain, and by what rule.

---

## 4. Governance, which runs under every layer

These are not a layer. They apply at each one, and a design that bolts them on at the end will have
the wrong shape.

| Concern | Rule | State |
|---|---|---|
| **Identity** | Attached by the runtime, never claimed by the model (ADR-034 §11) | Implemented in Workbench |
| **Budgets** | Two limits per task — monetary and model-call. First reached stops execution | Implemented in Workbench; **the system-wide governor does not exist** |
| **Spend governor** | Four windows; attended and unattended separate; checked before the call; persists across restart; **fails closed** (ADR-033 §5) | **Does not exist. Precondition for any paid call** |
| **Approvals** | Bound to one immutable action including its revision; changing a material input invalidates it | Implemented in Workbench |
| **Audit** | Append-only, hash-chained, **records refusals too** | Implemented in Workbench |
| **Refusals** | Structural, and proved by attempt against a planted positive control | Practised since Phase 08 |
| **Trust** | Provenance attached at gathering; untrusted content arms the action gate | Not built |
| **Observability** | The administration dashboard (Phase 22) | Not built |

> **An authorisation check that has only ever permitted is unvalidated** — and one that has only ever
> refused is broken. Every rule gets both tests.

## 5. Constraints that shape the whole design

- **ADR-032 §2** — no knowledge base, project repository, product source or `ops/` record on the node,
  including a derived index or embedding, until encryption is revisited.
- **ADR-025 §8** — only the question and the `/status` figures leave the machine. Widening needs its
  own ADR. This is the immediate next architectural decision (ADR-033 §6).
- **ADR-025 §1, §10** — credential boundary and the dispatch lock; §10 changes only under ADR-034 §13.
- **ADR-020** — the node has no console. Classify any change touching network, boot, authentication or
  the admin account before making it.
- **ADR-011** — privilege separation. No user-facing service runs as root.
- **`AGENTS.md`** — prefer minimal, comprehensible implementations. Do not add Redis, PostgreSQL,
  queues or gateways because they are common; add them when a phase has a concrete need.

**Several of these constraints were written for a smaller system and are under review.** See
[`constraint-review.md`](constraint-review.md), which tests each against what the layers above need.
Until a successor ADR changes one, every constraint here remains in force.

## 6. What we deliberately do not build

Recorded so that a future phase does not quietly add them.

- **A workspace product.** Email, calendars, notes, a document editor, image generation and media
  libraries belong to a personal-AI-workspace thesis. Ours is infrastructure with Factory as a
  consumer and coding as the primary use.
- **One process holding everything.** Shell, filesystem, credentials, personal data and model
  execution must not share a single trust boundary. Prompt-level defence is not a process boundary,
  and a harness that conflates them cannot be reasoned about. Privilege separation is the design
  (ADR-011, ADR-025), not a later hardening pass.
- **A database, yet.** Relational plus JSON plus files plus a vector store means several sources of
  truth, uneven atomicity, and divergence between canonical and derived state. Files stay canonical
  until they demonstrably fail.
- **A central registry of anything for other adopters.** Factory is fork-and-customise software.

## 7. Failure modes this design rules out

Stated as standing rules, because each is cheap to prevent now and expensive to remove later.

1. **One definition per thing.** A tool's description, schema, aliases, handler, dispatch entry, UI
   control and retrieval metadata are one definition with several views — never several definitions
   kept in step by hand. Anything maintained in two places will diverge.
2. **Discovery is not authorization.** Selecting a relevant subset of tools is a *context economy*
   problem; permitting execution is a *security* problem. Separate mechanisms, and only the second is
   a boundary.
3. **Triggers fire once.** A scheduler must not double-execute because more than one process is
   running.
4. **Single-user is a decision, not a default.** Whether ownership is modelled from the start is
   decided deliberately; retrofitting it later leaves null-owner edge cases permanently.
5. **No parallel homes for one responsibility.** A migration finishes or is reverted; compatibility
   shims do not become architecture by remaining.

## 8. What this map says about the current roadmap

Findings only. **Reshaping the roadmap is a separate step and requires an ADR** (`AGENTS.md`:
changes affecting multiple phases are captured as ADRs, never applied silently).

**Gaps — layers with no phase at all:**

| Layer | |
|---|---|
| 2 — Understanding | nothing |
| 4 — Service routing | nothing |
| 5 — Web research | **nothing anywhere in the roadmap** |
| 8 — Cloud inference | named as a direction only |
| 9 — Result handling | nothing general |

**Collisions — one layer, several phases:**

- **Layer 7** — Phase 15, Phase 15.0 and Phase 23 all claim model registry and routing, and which
  one owns it is not settled.
- **Layers 5 and 6** — Phase 10 (knowledge, retrieval) and Phase 23 (context assembly) overlap.
- **Layer 4** — Phase 19 (concrete tools and mappings) and Phase 23 overlap.

**Absorbed:** Phase 12 (Automation) is the scheduler, which is a **client** at layer 1, not a phase of
its own.

**Probably superseded:** Phase 11 (Agent Framework Experiments) asked what abstractions a framework
would replace. ADR-034 and the Workbench answer most of that question already.

**Too large:** Phase 23 as briefed spans layers 3, 4, 6, 7 and 8 plus the governor. It is at least four
phases.

## 9. Open questions this document cannot answer

1. The taxonomy layer 2 classifies into.
2. Whether decomposition and classification are one step or two.
3. Where the harness runs, given ADR-032 — and therefore what the egress ADR must permit.
4. Whether the AI-assisted router is worth building at all.
5. Whether the Brain specialist queries retrieval itself or delegates.
6. What the stable prefix contains.
7. Whether single-user is a permanent decision or a current state.
8. The numeric spend ceilings.
