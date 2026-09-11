# ADR-035: Factory Workbench — Factory executes project operations, backends execute AI

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** none. **Refines** ADR-031 §1, §4, §7 and §9 — see §1. ADR-031 stands otherwise.
- **Superseded by:** **ADR-038** (2026-09-11) supersedes §7's *"The first real Workbench runs on the
  MacBook"* — everything runs on the server, and Workbench binds loopback reached by SSH tunnel. The
  rest of §7 and the rest of this ADR stand.

## Context

ADR-031 §1 states that Factory *"is **fully operational as a specification** and never executes. That
is not a gap in Factory to be closed later; it is what Factory is."*

That sentence was written on 2026-09-10 and it is no longer true of the system the owner wants. The
Phase 19 design review on 2026-09-11 established that users interact with Factory primarily through
**Factory Workbench** — executable software, living in the Factory repository, that opens a project,
writes its records, and invokes AI work through a configured adapter. The full record is
[`19-tool-vocabulary-design-review-outcome.md`](../handovers/19-tool-vocabulary-design-review-outcome.md).

The sentence was not careless. It was protecting something real: enforcement written into the thing
being enforced is not a contract. The problem is that it protects that property by over-claiming —
it forbids *all* execution in order to forbid *enforcement*, and those are not the same thing.
Writing a ticket into a project's `ops/` is execution. It enforces nothing.

The correct boundary is narrower, and it is the only thing this ADR changes about §1:

> **Factory Workbench executes Factory project operations; the configured backend executes AI and
> concrete tools.**

Two further consequences follow from the same review and are recorded here rather than left to be
rediscovered: ADR-031 §7's prerequisite on homelab's tool vocabulary is dead, and ROADMAP Phase 22
currently conflates two different dashboards.

This ADR is a **refinement, not a replacement**. ADR-031 is long, most of it is untouched, and
superseding it wholesale to change four sections would discard nine that are still correct.

## Decision

### 1. What this changes in ADR-031, and what it does not

| ADR-031 | Fate |
|---|---|
| §1 — *Factory declares. Homelab enforces. Projects accumulate. Brain supplies.* | **Retained.** The boundary rule is unchanged |
| §1 — *"fully operational as a specification and never executes"* | **Changed** — §2 below. Replaced by the narrower execution boundary |
| §2 — the refusable/followable test for tools vs skills | **Retained**, with a clarification — §3 |
| §3 — privacy is per-artifact | Untouched |
| §4 — each public layer independently adoptable | **Retained and strengthened** — §5 |
| §5 — the topology | Untouched |
| §6 / §6.1 — the brain rename, deferred | Untouched |
| §7 — Factory rewritten in a dedicated phase | **Retained**; its *prerequisite* is removed — §8 |
| §8 — project documentation stays in the project | Untouched |
| §9 — one plan and one progress record, in homelab | **Retained and extended** — §9 |
| §10 — this is ADR-029's revisit | Untouched |
| §11 — agent manifests are JSON | Untouched. Not reopened |

ADR-034 is the companion to this ADR: it replaces ADR-027 and defines the agent contract. Where the
two touch — capabilities versus tools — ADR-034 is the authority and this ADR refers to it.

### 2. Factory executes project operations; the backend executes AI

**Factory Workbench** lives in the Factory repository and is executable software. It:

- opens an existing project by being pointed at its project root or `ops/`;
- creates a new project and its minimum valid `ops/` structure;
- manages tasks, inbox messages, team assignments, reviews, workflow state and approvals;
- validates and directly writes the project's Factory records;
- invokes AI work through a **configured execution adapter**.

It **contains no homelab credentials, no model registry, and no homelab tool implementations.**

That last line is where ADR-031 §1's protected property actually lives. Workbench executes *record
operations* — the nouns and rules Factory already owns, applied to a project's own files. It does
not execute AI, does not hold provider credentials, and does not implement or grant a tool. The
asymmetry ADR-031 §1 gives as its reason is intact: Factory still cannot enforce what constrains it.

### 3. The refusable/followable test still holds, and a capability is a third thing

ADR-031 §2 separates a tool from a skill: *"If it can be refused, it's homelab. If it can only be
followed, it's factory."*

ADR-034 §2 introduces **portable capabilities**, which Factory owns and a backend can refuse. Read
carelessly, that breaks the test. It does not, and the distinction is worth stating because it will
be misread otherwise:

| | Owned by | Refusable |
|---|---|---|
| **Skill** | Factory | No — it grants nothing, so there is nothing to deny |
| **Capability** | Factory | It is a **request** for a refusable outcome |
| **Tool** | the backend | Yes — this is the thing that refuses |

The test discriminates **tools from skills**, and that is what it was written to do. A capability is
not a tool that moved repositories; it is the request, and the refusal still happens in the backend
that owns the tool. ADR-031 §2's table — which assigns the vocabulary, the implementations and the
skills to repositories by citing ADR-027 — is superseded in its citations by ADR-034 and in its
*vocabulary* row by ADR-034 §2. The test itself stands.

### 4. Execution adapters

Workbench invokes AI through one configured adapter. The eventual set:

| Adapter | Notes |
|---|---|
| **Homelab** | The owner's advanced backend |
| **Direct API key** | The user's own key |
| **Claude / Codex subscription CLIs** | Locally authenticated, *if* official support and implementation complexity make it practical |
| **MCP and other service integrations** | |
| **Manual mode** | No AI execution at all |
| **Deterministic fake adapter** | For repeatable automated tests |

Only the **deterministic fake adapter** is fixed. Which real adapter is implemented first is
deliberately open.

From Workbench's side, *"run this through homelab"* and *"run this through Claude Code"* are the
**same shape of adapter**. That is what makes the abstraction load-bearing rather than tidy, and it
is the mechanism by which ADR-031 §4's standalone requirement is actually met.

### 5. Standalone adoptability, met rather than asserted

ADR-031 §4 requires each public layer to be independently adoptable and makes it a validation
criterion, noting that **no public repository currently has a working standalone quickstart**.

Workbench plus the adapter set in §4 is how Factory meets it: an adopter runs Factory through Codex,
Claude Code, an IDE, direct APIs, MCP, or manual operation, with no homelab installed.

Factory ships a **public, synthetic, resettable coding project** that is simultaneously the
standalone quickstart, the end-to-end acceptance test, the development fixture, the learning example,
and the environment in which refusals are planted and proved. Its scope is specified in the design
review and belongs in the Workbench phase brief, not here.

**Factory is fork-and-customise software.** Each adopter edits and configures their own installation
and does not receive upstream changes automatically; a later update is a deliberate merge with
collisions resolved by the adopter. No central live registry, no global namespace machinery, no
automatic override layer. Simple exact names hold until real collisions justify more.

### 6. There are two dashboards, not one dashboard that moved

ROADMAP Phase 22 currently reads as moving the Factory dashboard into homelab. That conflates two
products with different scopes and different owners:

| Factory Workbench | Homelab administration dashboard |
|---|---|
| One project at a time | The whole AI system |
| Project `ops/` and the project inbox | The homelab-wide approval inbox |
| Tasks, team, reviews, workflow | Models, providers, costs, tools, runtime health |
| Portable execution adapters | Authoritative homelab execution and configuration |
| **Lives in Factory** | **Lives in homelab** |

One Workbench installation opens many projects, so dashboard code is never copied into a project.
Each project's private content and inbox stay in that project's `ops/` (ADR-028, ADR-031 §8).

### 7. Credentials, binding, and where Workbench runs

**Credentials** use the operating system's credential store where available; environment variables or
a protected user-local secret file **outside every repository** are the fallbacks. A credential never
enters project `ops/`, committed Factory configuration, logs, or browser storage. Workbench does not
store a GitHub token — GitHub mode uses the user's already-authenticated `gh` CLI.

**Local Workbench binds to `127.0.0.1`** and has no separate application login: the OS user boundary
is sufficient for a single-user local tool, and inventing an auth system for it would be security
theatre with a maintenance cost.

The first real Workbench runs on the **MacBook**. A later homelab-hosted deployment is
**Tailscale-only** initially and adds application authentication and secure sessions before it is
anything else. **Public exposure is not part of this design** and would need its own decision.

### 8. ADR-031 §7's prerequisite is removed

ADR-031 §7 makes the Factory rewrite conditional: *"homelab must first publish its named tool
vocabulary and capability levels, so the rewrite has something to compose against."*

That prerequisite is **void**. It rests entirely on ADR-027 §3 and §5, which ADR-034 replaces, and on
Phase 19, which was superseded before implementation. Under ADR-034 §2 the rewrite composes against
**Factory's own portable capabilities**, which Factory owns and can therefore define without waiting
for anything.

The rest of §7 stands: Factory's content is kept, its markdown-heavy format is discarded, nothing is
written into the old format, and the rewrite is a dedicated phase.

**The dependency inverts.** Concrete homelab tools should follow observed capability gaps rather than
precede them — the failure mode Phase 19 demonstrated was publishing a vocabulary before any consumer
existed to shape it.

### 9. The plan stays in homelab even though the code lives in Factory

ADR-031 §9 puts one roadmap and one progress record in homelab, and §4 clarifies that this governs
the owner's own system development while what Factory *ships* is method and contracts, never the
owner's roadmap.

Workbench is the first case where those two sentences could be read as conflicting: the code lives in
Factory, so does its plan move too? **No.**

| Lives in Factory | Lives in homelab |
|---|---|
| Workbench code, the synthetic acceptance project, the portable capability definitions, the standalone quickstart | The plan to build them, the progress record, and the contracts they must satisfy |

§9 is unchanged and now covers a case it had not yet met. An adopter who forks Factory gets the
software and writes their own plan, exactly as §4 says.

## Alternatives considered

**Leave ADR-031 §1 as written and treat Workbench as an exception.** Rejected: "never executes" is
stated as a definition of what Factory *is*, not as a constraint with exceptions. An unstated
exception to a definition is how the next reader concludes the opposite in good faith.

**Supersede ADR-031 in full, as ADR-034 does to ADR-027.** Rejected on the difference between the two
cases: ADR-027's load-bearing sections nearly all changed, so a replacement was easier to read
correctly. Here nine sections of eleven are untouched, and a full replacement would mean re-ratifying
the brain deferral, the per-artifact privacy rule and the topology as a side effect of a dashboard
decision.

**Put Workbench in homelab.** This was the design review's own initial recommendation, and **the
owner rejected it** — recorded rather than smoothed away. Standalone Factory users need the same
operating interface, and a Workbench in homelab is a Workbench they cannot have. The result is two
dashboards (§6) rather than one in the wrong place.

**No Workbench; drive Factory through a coding agent in an editor.** This is the status quo and it
works for the owner today. Rejected as the target: it makes every project operation depend on a
model's willingness to follow prose, when writing a validated record is deterministic work that
should not be probabilistic.

**One dashboard covering both project and system concerns.** Rejected: it would be copied into
homelab and thereby made unavailable to standalone adopters, or generalised until it served neither
scope well.

**Give local Workbench its own application login.** Rejected for the local case: the OS user boundary
already separates users on a personal machine. Retained for the eventual hosted case, where it is a
genuine requirement rather than ceremony.

## Consequences

**Easier.** Factory becomes adoptable in practice rather than in principle — §4's criterion gets an
artifact that can actually be run. The Factory rewrite is unblocked immediately: it no longer waits on
a homelab vocabulary that was never built and is no longer planned in that form.

**Harder.** Factory acquires software, and with it a test suite, a release story, and a supported
adapter surface. A specification has no runtime bugs. This is the real cost of the change and it is
paid in the Workbench phase.

**Newly required.** An adapter interface stable enough that homelab and a subscription CLI implement
the same shape; a deterministic fake adapter, before any real one, so the acceptance project is
repeatable; and a credential path that uses the OS store on at least macOS.

**Constrained.** Workbench may not hold a homelab credential, a model registry, or a tool
implementation — the line that keeps ADR-031 §1's reason intact. Public exposure of a hosted
Workbench is outside this decision.

**Roadmap consequences, not allocated here.** Phase 20's scope is rewritten around the minimal
Workbench plus the synthetic acceptance project, with intensive development and the full catalogue
migration following the homelab AI foundation. Phase 22 becomes the **homelab administration
dashboard** and, when its prerequisites exist, the authenticated Tailscale hosting boundary. Final
sub-phase numbering and running order are **deliberately not fixed here** — that is roadmap
reconciliation work, and the roadmap's stable-numbering rule governs it.

**Deferred.** Which real adapter ships first; the hosted Workbench's authentication design; whether
Factory's retired `roadmap.md` content survives into homelab's plan, which ADR-031 §9 already assigns
to the rewrite phase.

## Validation / revisit trigger

**Validation required before this ADR is considered implemented**, each proved by attempt rather than
observed to pass:

1. The synthetic acceptance project runs **end to end with no homelab installed**, on the
   deterministic fake adapter — ADR-031 §4's criterion, met rather than asserted.
2. The same project runs on a **second** adapter without changing the project's records, which is
   what proves the adapter abstraction is real and not a single implementation with an interface
   drawn around it.
3. Workbench **refuses a direct agent write to `main`**, and refuses a merge whose human approval is
   not bound to the exact reviewed revision.
4. Every planted refusal in the fixture fires **and** its positive control passes: an unapproved
   agent addition, an unsupported backend capability, an approval-gated action waiting in the inbox,
   exhausted review rounds, an exhausted budget, and an agent exceeding project or context scope.
5. A grep of the Workbench tree and of a fixture project's `ops/` finds **no credential**, and the
   run produces none in its logs.
6. Local Workbench listens on `127.0.0.1` only — checked with `ss`/`lsof`, not assumed from
   configuration.

**Revisit if:**

- an adapter cannot be implemented against the interface without leaking backend-specific concepts
  into Workbench, which would mean §4's "same shape" claim is false;
- Workbench needs a homelab credential, a model registry or a tool implementation to do its job —
  the signal that §2's boundary is drawn in the wrong place;
- standalone adopters do not materialise, which would make §5's cost unjustified and reopen putting
  Workbench in homelab;
- a hosted Workbench is wanted before its authentication design exists, which would be the moment to
  decide public exposure rather than drift into it.
