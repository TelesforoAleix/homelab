# ADR-045: Reshaping the roadmap around the layer model

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** the Sequencing note of 2026-09-11 in `ROADMAP.md`. Reshapes Phases 10–23 without
  renumbering any existing phase.
- **Superseded by:** none

## Context

The [target architecture](../architecture/target-architecture.md) describes nine request layers with
governance under all of them. Mapping the roadmap onto it exposed five layers with no phase, three
layers claimed by more than one phase, and one phase (23) spanning five layers plus the spend
governor.

`AGENTS.md` requires a change affecting multiple phases to be an ADR rather than a silent edit. This
is that ADR. The detail lives in `ROADMAP.md`; this records what changed and why.

## Decision

### 1. Phase numbers stay. Insertions are sub-phases

No existing phase is renumbered. New work becomes a sub-phase of the phase it belongs to, or a new
number at the end. This is the roadmap's own rule and the Phase 18 precedent.

### 2. The encryption work is Phase 18.1, and it comes first

ADR-037 executes a decision Phase 18 deferred, so it belongs to Phase 18 rather than to whatever
phase happens to need it. **Phase 18.1 — Encryption execution**: verify the backup by restoring,
shrink the root LV, create the LUKS volume, establish the SSH unlock path, and make
degraded-until-unlocked a tested state rather than an assumed one.

**It is first because everything touching knowledge or project content on the node waits on it**, and
because it needs the owner physically present — the only pending item that does.

**Phase 18.2 — Migration to the server** follows: `brain`, the projects, Factory and Workbench move
into the volume (ADR-038). Separate from 18.1 because the risk profiles are different — one is an
offline filesystem operation that can destroy data, the other is moving repositories that already
have remotes.

### 3. Phase 12 is repurposed, not absorbed

**This corrects an earlier assessment.** The target architecture recorded Phase 12 as absorbed,
because the scheduler is a client at layer 1 rather than a phase. That was half right and it dropped
something real.

**Phase 12 — Scheduling, monitoring and notifications** survives, holding the always-running
plumbing: the scheduler as a trigger source, a **watchdog** that observes, and a **notifier** that
reports. Recovery-oriented rather than real-time, because if the whole node is down nothing on it can
tell you, and reporting on recovery needs no external watcher.

**The watchdog must not share a process with what it watches**, and it lives on unencrypted root so
it works the moment the node boots — which is what lets it report *"back up, down 14 minutes, data
volume still locked"* after a power cut.

### 4. Layer 7 belongs to Phase 15. Phase 23 consumes it

The model registry and routing were claimed by Phase 15, Phase 15.0 and Phase 23. Resolved:

| | Scope |
|---|---|
| **15.0** | Model registry as configuration; `unattended` eligibility enforced structurally. Already briefed. Costs nothing — it uses the two subscription CLIs that exist |
| **15.1** | Metered provider integration **and the spend governor together** — ADR-033 says they ship together or not at all |
| **15** | Routing proper: deterministic first, deterministic retained as the fallback, AI-assisted as the target |

**Phase 23 does not rebuild any of it.**

### 5. Phase 23 becomes four sub-phases

It spanned five layers plus the governor. Split by layer, because that is where the research
boundaries actually fall:

| | Layers | Scope |
|---|---|---|
| **23.0** | 1, 2, 9 | The always-running endpoint; entry from every client; request classification; result handling. **Includes the Workbench→homelab adapter**, which is what finally tests the adapter interface Phase 20.0 left unproved |
| **23.1** | 3, 4 | Decomposition and service routing, with ADR-044's client exposure policy |
| **23.2** | 6 | Context assembly and the stable-prefix discipline, under ADR-039's egress policy |
| **23.3** | governance | Identity, budgets, approvals and audit as harness machinery, and the **ADR-034 §13 transition** — the largest security change on the roadmap |

### 6. Five gaps get homes

| Layer | Gap | Home |
|---|---|---|
| 2 — Understanding | no phase | **23.0** |
| 4 — Service routing | no phase | **23.1** |
| 5 — Web research | **no phase anywhere** | **Phase 24 — Web Research Service**, a new number |
| 8 — Cloud inference | a direction only | **Phase 15**'s provider work; noted, not a phase |
| 9 — Result handling | no phase | **23.0** |

### 7. Phase 11 is superseded

Phase 11 asked what abstractions an agent framework would replace, before committing to one. ADR-034
answered the contract question and Phase 20.0 answered the execution question by building it. The
phase is marked superseded rather than deleted; if a framework is ever wanted, the question is now
"does it replace what we built" rather than "what would it replace".

### 8. Knowledge is unblocked and keeps its sketched sub-phases

Phases 10.1 (ingestion), 10.2 (vector retrieval) and 10.3 (hybrid search) were sketched in the
roadmap's own sub-phase example and never filled in. They become real, and Phase 21's `brain`
repository split runs with them (ADR-031 §6). All of it now depends on **18.1 and 18.2** rather than
on ADR-032's gate being lifted.

## Alternatives considered

**Renumber everything to match the nine layers.** Rejected: it destroys the correspondence between
phase numbers and the record — handovers, ADRs, build logs and guides all cite them — for a tidiness
that helps nobody reading the history.

**Keep Phase 23 whole and sequence inside it.** Rejected. A phase spanning five layers cannot write
one brief, cannot have one Definition of Done, and cannot hand over. ADR-017's self-contained phase
is the unit that makes the project work.

**Give the spend governor its own phase.** Considered seriously. Rejected because ADR-033 §5 ties it
to metered access — *"the governor ships together with it or not at all"* — and separating them
invites a phase that ships a provider with the control still pending.

**Do the harness before encryption.** Rejected: layers 5 and 6 would be built against content that is
not there, and the shape of retrieval would be guessed.

## Consequences

**Easier.** Every layer has exactly one owner. Each phase is small enough to brief, validate and hand
over. The two gaps that would have been discovered mid-build — web research and result handling —
are now visible before anyone plans around their absence.

**Harder.** There are more phases, and more briefs to write. That is the cost of phases that can
actually be finished.

**Newly required:** briefs for 18.1, 18.2, 12, 15.1, 23.0–23.3 and 24. None exists. Phase 15.0's
brief exists and predates ADR-034; it needs the §5 amendment applied.

**Constrained:** no phase may claim a layer another phase owns. A phase that finds it needs to is
describing a dependency, not a scope change.

## Validation / revisit trigger

1. Every layer in the target architecture names exactly one owning phase, and every pending phase
   names the layers it owns. Checked by reading the two documents against each other.
2. No phase number is reused or renumbered — the existing record still resolves.
3. Each new sub-phase can state a Definition of Done that fits on one page. If it cannot, it is still
   too large.

**Revisit if:** a phase turns out to need a layer it does not own, which means §4–§6 drew a boundary
in the wrong place; or the sub-phase count makes the roadmap harder to read than the collisions did.
