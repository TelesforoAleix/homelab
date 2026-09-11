# ADR-034: The Agent Contract — portable capabilities, backend tools, and independent authority

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** ADR-027 in full. Changes ADR-025 §10 (see §13).
- **Superseded by:** none. **Extended by ADR-044** (2026-09-11) with a boundary this ADR does not
  cover: a declared capability grants nothing, and which **services** a *client* may reach is checked
  first and is the stronger boundary.

## Context

ADR-027 was written on 2026-09-10, in a single day alongside ADR-028, ADR-029 and ADR-030. It
answered a real question — *how does Factory declare an agent such that homelab can read it* — and it
answered it with a premise that did not survive contact with the phase meant to implement it.

That premise was **Factory composes agents from homelab's tool vocabulary**. Phase 19 existed to
publish that vocabulary, and its brief was rejected during design review on 2026-09-11 before any
implementation began. The full record is
[`19-tool-vocabulary-design-review-outcome.md`](../handovers/19-tool-vocabulary-design-review-outcome.md);
this ADR is the governance change that review requires, and it does not re-argue the review.

Three findings force a replacement rather than an amendment.

**The coupling was backwards.** ADR-031 §4 requires Factory to be independently adoptable. If a
Factory agent names `read_repo`, and `read_repo` is a homelab tool, then Factory cannot be used
without homelab — which is what ADR-031 §4 forbids. The owner rejected the coupling during review.
Repairing this means changing what a manifest names, which is ADR-027 §2, §3, §4 and §5 — most of
the ADR.

**Two of the five proposed tool names came from ADR-027's own example manifest**, not from a real
workflow. `read_repo` and `post_review` were illustrative; Phase 19 inherited them as requirements
and discovered they could not run on the reference node at all, because ADR-032 forbids private
project content there. An example manifest had quietly become a specification.

**The human ceiling in §4 is wrong, not merely inconvenient.** ADR-027's own revisit trigger named
this case exactly: *"an agent legitimately needs to act with authority the calling human lacks,
which would mean §4 is wrong rather than merely inconvenient."* The owner wants unattended
specialists — a Brain specialist that answers a bounded question for a project agent without handing
that agent access to Brain. The trigger fired. This ADR is the response to it.

What has **not** changed is the reason ADR-027 existed: enforcement belongs where it is enforced, and
a manifest is a request rather than a grant. That survives intact and is restated below.

## Decision

### 1. What this replaces, section by section

ADR-027 is superseded **in full**, so that there is one document to read rather than an accepted ADR
plus a layer of exceptions. Most of it survives in substance. The table is the supersession record:

| ADR-027 | Fate | Where it lands |
|---|---|---|
| §1 — system agents vs work agents, by the swap-out test | **Retained** | §3 below, unchanged |
| §2 — an agent declares five things | **Changed** | §4: `capabilities` and `tools` are separate fields; `model_policy` is removed |
| §3 — Factory declares, homelab enforces | **Retained, re-scoped** | §2: still true of *tools*; Factory now owns *capabilities* |
| §4 — `agent.tools ∩ caller authorisation` | **Changed** | §8: the caller ceiling is removed for service specialists; the other terms remain and grow |
| §5 — unknown tool name is a load failure | **Retained, moved earlier** | §6: incompatibility now fails before *activation*, not at dispatch |
| §6 — tools open one agent at a time; destructive needs moment-of-action approval | **Retained** | §7 and §12 |
| §7 — prose specification is the human source of truth | **Retained** | §15, unchanged |

Three ADRs cite ADR-027 and are **not** disturbed by this replacement: ADR-028 and ADR-029 (the
dependency direction), and ADR-031 §11 (manifests are JSON — this review did not reopen the
serialisation). ADR-031 §2's *"if it can be refused, it's homelab"* test is preserved and sharpened
by §2 below. ADR-026 §4 is preserved explicitly — see §5.

### 2. Factory declares portable capabilities; backends provide concrete tools

> **Factory agents declare portable capabilities. Execution backends provide concrete tools.**

A **capability** states an outcome an agent needs: `repository_read`, `review_append`. It is
portable, it names no implementation, and Factory owns its definition.

A **tool** is an executable implementation of a capability inside one backend. Homelab owns its
concrete tools, and owns the approved mapping from capability to tool.

Homelab is **one advanced backend, not a prerequisite**. The same Factory capability may be
satisfied by Codex, by Claude Code, by a direct API integration, by MCP, or by a backend's own
implementation. An adopter can run Factory with none of them, in manual mode.

This changes ADR-027 §3's *direction of naming* while keeping its reason. Factory still declares and
homelab still enforces; what Factory declares is now a request for an *outcome* rather than a
reference to homelab's internal vocabulary. The asymmetry ADR-031 §2 states is unchanged: a
capability can be refused, so refusal still lives in the backend.

**Homelab publishes no concrete tool until it implements one for a real need.** This is the direct
lesson of `read_repo` and `post_review`: a name in an example is not a contract, and a vocabulary
published ahead of its consumers is a guess. Factory may publish a portable capability that no
current backend supports; homelab may not publish a tool it has not built.

### 3. System agents and work agents (ADR-027 §1, unchanged)

| | Repository | Purpose |
|---|---|---|
| **System agents** | `homelab` | Operate the AI harness itself — agent selection, model selection, context assembly, decomposition, review routing |
| **Work agents** | `factory` | Do work on a project — implementation, review, release, product ownership |

The test remains: **does it survive The Factory being swapped out?** A homelab system agent that
reads Factory definitions and chooses among them is this contract working, not an exception to it.

### 4. What an agent declares

The five fields become four, and one of them splits:

```json
{
  "agent": "review-qa",
  "context": ["ticket", "diff", "acceptance-criteria"],
  "skills": ["fresh-context-review"],
  "capabilities": ["repository_read", "review_append"],
  "tools": ["optional_local_specialized_tool"],
  "unattended": true
}
```

- **`capabilities`** — portable requirements. The field reusable catalogue agents use.
- **`tools`** — exact concrete tool names, for user-created agents where portability is
  deliberately unnecessary. Optional, and naming one is a decision to be non-portable.
- **`model_policy`** — **removed**. See §5.

Keeping the two concepts in separate fields is the point. A single merged list would make
portability invisible at a glance and would let a portable agent acquire a backend-specific
dependency without anyone noticing the change in kind.

**The exact schema is not decided here** — field types, versioning, and validation rules belong with
the Factory Workbench design. JSON remains the serialisation (ADR-031 §11, not reopened).

### 5. Model selection belongs to homelab — and ADR-026 §4 is preserved, not superseded

Agents do **not** declare `model_policy` and never name a provider or a model. The router receives:

- the agent role;
- a bounded task summary rather than the full private task;
- validated task metadata — priority, severity, complexity;
- required capabilities and context characteristics;
- model availability, eligibility, capacity, cost and latency.

**ADR-026 §4 survives intact.** It decides that *"an agent declares what it requires — 'cheap
classification', 'fresh-context review' — and the router selects"*, and adds that *"the declaration
form is ADR-027's business"*. Removing `model_policy` changes the **form**, which is precisely what
§4 delegates. The principle it states is unchanged, and is better served:

> **The agent's role is its declaration of need.**

`review-qa` carries more routing signal than a hand-written tier does, and unlike a tier it cannot
drift out of sync with what the agent actually is. This is stated explicitly because removing a
field named in ADR-026 §4's own sentence, without saying so, would contradict an accepted ADR
silently — which `AGENTS.md` forbids.

**Priority, severity and complexity are hints, never selectors.** They cannot choose a model, cannot
reach a model tier on their own, and cannot bypass the pre-call budget check ADR-033 requires. This
follows from §11's instruction hierarchy: an agent's own statement about its work is data, not an
instruction. Without this rule an agent routes itself to an expensive model by asserting that its
task is hard, and the spend governor notices only after the cost is committed.

The target is an AI-assisted routing agent. Routing **starts deterministic** because that is what can
be validated, and deterministic routing is retained as the fallback. The AI router sees only the
bounded routing summary unless a future decision widens that boundary explicitly.

### 6. Compatibility is checked before activation, not discovered at dispatch

A backend advertises the capabilities and concrete tools it actually supports. Before an agent is
activated for work, its requirements are checked against the selected backend.

- Workbench **may load** a valid agent definition whose requirements the current backend cannot meet.
- It **must refuse to activate** that agent before work begins, naming **every** missing requirement.

ADR-027 §5's refusal is retained and moved earlier. "Load now, discover refusal at dispatch" is
rejected: it starts work that cannot finish, and it reports one missing name at a time.

An **unknown concrete tool name still fails clearly** in the backend asked to execute it. A dropped
requirement is never a warning.

**The machine-readable advertisement protocol is not decided here.**

### 7. Tool properties replace the scalar capability level

ADR-027 inherited `READ` / `PRIVILEGED` / `UNAVAILABLE` from the Telegram router. One scalar cannot
express "may read the repository but may only append a review", and it mixes privilege with
implementation status. A tool contract instead carries independent properties:

| Property | Values |
|---|---|
| **effect** | `read`, `append`, `modify`, `control` |
| **minimum approval** | `automatic`, `approve_when_granted`, `approve_each_action` |
| **runtime availability** | supported / unsupported |
| **target scope** | the projects, records, services or other objects the implementation may touch |

**Homelab defines the minimum approval policy. Factory may make an agent or workflow stricter and
can never weaken homelab's minimum.** Destructive host control requires approval at each action —
ADR-027 §6's rule, now expressible rather than implied.

Availability stops being vocabulary data: a backend advertises what it has (§6) rather than
publishing a name annotated as unavailable.

**The exact schema for these properties is not decided here.**

**A tool contract evolves compatibly under its own name.** Improvements should reach every agent
using a tool without anyone editing a manifest, so: faster, safer, more accurate or
backward-compatible changes keep the name; every known internal consumer is tested before merge;
existing inputs, outputs and minimum safety guarantees stay compatible. A genuinely incompatible
public change requires a **new version**, because unknown external adopters cannot be repaired
automatically.

### 8. Two kinds of agent authority — and the human ceiling is removed for one of them

ADR-027 §4 held that an agent may never exceed what the human it acts for could do directly, and its
Consequences foreclosed *"service agents with their own elevated identity"*. **That is reversed for
service specialists**, on the owner's explicit decision and on ADR-027's own revisit trigger.

| | **User-delegated agent** | **Service specialist** |
|---|---|---|
| Acts for | a specific human, on a specific task | itself, within a narrow service mandate |
| Ceiling | what that human is authorised for | its own independently granted authority |
| Human in the loop | yes | not necessarily |
| Example | an implementation agent on a project task | the Brain specialist answering a bounded question |

A service specialist's authority is **narrow, independently granted, bounded, and audited**. It is
not a general elevation: a Brain specialist may search Brain, and that is all it may do.

**Delegation does not transfer access.** A coding agent may *ask* the Brain specialist a bounded
question. It does not thereby gain the ability to search Brain. This is the property that makes the
reversal safe, and it is what ADR-027 §4 was reaching for with a blunter instrument.

The intersection ADR-027 §4 introduced is retained and widened. The effective execution boundary is:

```text
approved agent definition
∩ active project/task assignment
∩ work-item context scope
∩ approved capability-to-tool mapping
∩ backend tool and target policy
∩ applicable moment-of-action approval
```

For a user-delegated agent, the caller's own authorisation remains a term in that intersection. For a
service specialist it is replaced by the specialist's own mandate — which is the whole of the change.

### 9. Agent-to-agent requests are explicit delegation, independently validated

A request from one agent to another is a delegation, and the **receiving** agent validates it against
its own role, the active project and workflow, permitted delegation relationships, scope and
data-sharing policy, tool approval policy, and remaining budget.

> **"A teammate asked" is never sufficient authorisation.**

Without this, an agent with no merge authority reaches merge authority by asking a release agent to
merge for it, and every boundary in this ADR becomes advisory.

Another agent's response — the Brain specialist's included — is **advisory**. It cannot grant a tool,
change project scope, weaken an approval, or redefine the receiving role. Every proposed state
transition is validated by Workbench or homelab.

### 10. Capability-to-tool mapping is a security decision

`repository_read` can be implemented as a provenance-returning reader of explicitly named files, or
mapped carelessly onto a broad shell. Both satisfy the name.

**New or changed capability-to-tool mappings require human approval.** Where a capability requires
technical enforcement, a human may not override an incompatible backend and call prompt-only
compliance enforcement. The choice is another adapter, or an honestly weaker capability.

If homelab lacks a needed mapping or tool, the project orchestrator creates a private capability-gap
proposal. Human approval in the homelab inbox is required before a sanitised proposal reaches
homelab's public backlog. **Acceptance into the backlog neither creates nor grants a tool.**

### 11. Execution identity is attached by the runtime, not claimed by the model

Agents have **logical identities** carried by the trusted runtime. An agent does not receive an OS
account or a credential merely because it exists.

The runtime attaches immutable execution context: agent identity and version, project, work item,
active assignment, authorisation and budget state. The model supplies a proposed operation and its
arguments, and nothing else. **It cannot claim another identity, switch projects, or manufacture a
grant.**

The instruction hierarchy is fixed:

```text
homelab security and tool policy
→ approved Factory agent and skill definition
→ project policy
→ approved work-item instructions
→ retrieved context as untrusted data
```

Repository files, Brain results, API output and messages from other agents are **untrusted data by
default**. Text does not become an instruction because it uses imperative language.

### 12. Catalogue agents, project rosters, and when a change takes effect

- Factory holds a reusable **catalogue** of agent definitions.
- A project's canonical **roster** lives in that project's private `ops/` (ADR-028).
- **Humans add agents to a project.** The orchestrator may recommend an addition through the inbox;
  it cannot approve one or edit the roster itself.
- Approving an agent chooses **task-scoped** or **team-scoped** membership. Task-scoped membership
  ends automatically with the task.
- Shared specialists are enabled **explicitly per project**, never globally.

**Definitions are live; tasks are pinned.** Adding a tool or skill to a catalogue agent makes it
available everywhere that agent works — like a person being upskilled. The controls:

- global catalogue changes require human approval;
- an approved addition takes effect for that agent's **next** task, not during an active one;
- **security revocations and emergency suspensions take effect immediately**;
- every work item records the exact agent-definition version or content digest it used.

ADR-027 §6's incremental principle is retained: tools open **one agent at a time**, advisory agents
first, each with the reason recorded.

Agents are **stateless between tasks**. An active task may hold bounded temporary conversation
context; anything needed later becomes an explicit record in Factory, project `ops/`, or Brain. Task
history stores observable decisions, concise rationale, messages, tool requests and results,
evidence, approvals, model usage, cost and outputs. It does **not** store hidden chain-of-thought.

### 13. A model's tool request becomes an untrusted request — a deliberate change to ADR-025 §10

ADR-025 §10 states that the model's output is never an instruction, and it was proved by making a
model emit `/restart ssh.service` and confirming that nothing happened. **A system with tool-using
agents cannot keep that sentence literally**, and pretending otherwise would be the silent
contradiction this project's rules exist to prevent.

The safe preservation of ADR-025 is not *"nothing the model emits ever reaches a dispatcher"*. It is:

1. no raw provider CLI receives ambient filesystem, shell, credential or OS tools — **unchanged**;
2. model output is untrusted — **unchanged**;
3. only a **structured request** enters the trusted runtime;
4. runtime identity, assignment, scope, mapping, budget and approval checks all run **before** any
   action;
5. the model cannot directly dispatch, nor grant itself anything.

Items 1 and 2 are the security properties. Item 3 is what changes: the inert-by-architecture
property of ADR-025 §10 is replaced by checked-by-runtime. **This change is recorded here and takes
effect only when tool-using agents are implemented.** Until then ADR-025 §10 stands as written, and
the Phase 09 canary check continues to apply.

### 14. Refusals are structural, and must be proved by attempt

Retained from ADR-027 and extended:

- an unknown concrete tool name **fails clearly** in the backend asked to execute it;
- capability incompatibility fails **before activation**, naming every missing requirement;
- no tool or mapping silently grants itself authority;
- the default for an agent with no declared capabilities or tools remains **no tools**;
- `homelab-bot` receives neither AI credential;
- no secret enters Git, `ops/`, prompts, logs, or browser storage.

> **An authorisation check that has only ever permitted is unvalidated.**

Every refusal in this ADR is proved against a **planted positive control** — the byte-identical case
with only the offending element removed, which must succeed. See Validation below.

### 15. The prose specification remains the human source of truth (ADR-027 §7, unchanged)

A manifest sits **alongside** the role specification, not instead of it. The prose keeps explaining
*why* a boundary exists; the manifest states it in a form a machine can enforce. Neither is generated
from the other, and where they disagree that is a bug to reconcile, not a precedence rule to invoke.

## Alternatives considered

**Amend ADR-027 in place.** Rejected: §2, §3, §4 and §5 all change. What remains would be an ADR
whose every load-bearing section carried an exception, which is harder to read correctly than a
replacement — and `docs/decisions/README.md` forbids rewriting an accepted ADR regardless.

**Homelab owns the portable names; Factory composes from them.** This is ADR-027's design, and it
was the design review's own initial recommendation. **The owner challenged it and the recommendation
changed** — recorded here rather than smoothed away. It fails ADR-031 §4: an adopter running Factory
through Codex alone would be naming tools from a system they do not have.

**One merged list of names, portable or concrete.** Simpler manifest, and rejected: portability
becomes invisible, and an agent acquires a backend-specific dependency without the change being
legible in a diff.

**Keep `model_policy` alongside the role.** Rejected: two declarations of the same need drift, and
the hand-written one wins by being more specific while being less accurate. The role cannot drift out
of sync with what the agent is, because it *is* what the agent is.

**Keep the human ceiling and give the Brain specialist a human operator.** Rejected by the owner: it
makes every knowledge query synchronous on a human, which defeats the purpose of a specialist. The
access-non-transfer rule in §8 is what makes removing the ceiling safe.

**A central live registry of capability names for all adopters.** Rejected: Factory is
fork-and-customise software, adopters do not receive upstream changes automatically, and simple exact
names are sufficient until real collisions justify more.

## Consequences

**Easier.** Factory becomes genuinely standalone — it can be adopted through Codex, Claude Code, an
IDE, direct APIs, MCP or manual operation with no homelab install. Adding an agent stays a Factory
change with no homelab deployment. Homelab stops owing a public tool vocabulary before it has
consumers, which is the obligation that produced an unimplementable phase.

**Harder.** There are now two vocabularies to keep coherent — portable capabilities and concrete
tools — plus a mapping between them that is itself a security artifact requiring approval. That is
strictly more machinery than ADR-027 had, and it is the cost of Factory standing alone.

**Newly required.** A backend capability-advertisement mechanism; a compatibility check that runs
before activation; a capability-gap proposal path through the homelab inbox; per-work-item recording
of agent-definition versions; and a delegation validator on the receiving side of every agent-to-agent
request.

**Constrained.** Homelab may not publish a concrete tool it has not implemented. Factory may not
weaken a homelab minimum approval. An agent may not select its own model, nor reach a model tier by
describing its own task as hard.

**Reversed.** ADR-027's foreclosure of *"service agents with their own elevated identity"* is
withdrawn. This is a real widening of the system's authority model and is recorded as such, not as a
clarification. Its safety rests entirely on §8's non-transfer rule and §9's receiver-side validation;
if either is implemented weakly, this ADR is worse than what it replaces.

**Deferred, deliberately.** Whether the Brain specialist queries retrieval itself or delegates to a
Brain-native agent; the exact manifest schema; the capability-advertisement protocol; the
effect/approval/target-scope schema; the default approval expiry; the AI router's implementation and
provider. These are listed as open in the design review and are **not** invented here.

**Untouched.** ADR-032's content gate. The storage-classification discussion drifted into the design
review and the owner stopped it; nothing here changes what may be stored on the node.

## Validation / revisit trigger

**Validation required before this ADR is considered implemented.** Each item is proved by attempt
against a planted positive control — the byte-identical case with only the offending element removed,
which must succeed:

1. An agent requiring a capability the selected backend does not advertise **fails to activate**, and
   the refusal names **every** missing requirement, not the first.
2. An unknown **concrete** tool name fails clearly in the backend asked to execute it.
3. A user-delegated agent acting for a non-privileged caller cannot invoke a privileged tool **even
   when its definition names that tool**.
4. A coding agent that may ask the Brain specialist a question **cannot itself search Brain** — the
   non-transfer rule in §8, which is the single property the authority reversal rests on.
5. A delegated request that the receiving agent's own role forbids is **refused by the receiver**,
   with "a teammate asked" recorded as insufficient.
6. An agent asserting high complexity or severity **does not reach a more expensive model** and does
   not bypass the pre-call budget check.
7. An approved catalogue addition **does not take effect during an active task**; a security
   revocation **does** take effect immediately.
8. An agent with no declared capabilities and no declared tools still passes the Phase 09 canary
   check — the default remains "no tools", not "all tools".

**Revisit if:**

- a real agent needs a declaration this contract has no field for — budget and latency remain the
  likeliest candidates, as they were under ADR-027;
- portable capabilities prove too coarse to map safely, so that every mapping needs bespoke review
  and the portability buys nothing;
- adopter name collisions occur in practice, which would reopen the rejected registry;
- the separation between `capabilities` and `tools` is routinely bypassed by agents naming concrete
  tools, which would mean portability is not actually wanted;
- any prose-versus-manifest drift becomes frequent enough to reconsider generation (ADR-027's
  original trigger, retained).
