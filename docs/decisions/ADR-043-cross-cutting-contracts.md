# ADR-043: Cross-cutting contracts and living specifications

- **Status:** Proposed
- **Date:** 2026-09-11
- **Supersedes:** none. **Amends** ADR-017 in two narrow respects. Applies ADR-031 §9.
- **Superseded by:** none

## Context

ADR-017 made phases self-contained and sequential, and abolished the separate planning context: each
phase writes its own brief, and cross-phase changes are recorded as ADRs carried into the next brief.
That solved a real problem — a planning layer that accumulated authority without doing the work.

Two things have since strained it.

**Cross-cutting concerns.** Identity, budgets, approvals, audit and trust state apply at every layer of
the target architecture. In a strictly sequential model such a concern is either built once, early,
against requirements nobody has yet, or rebuilt in every phase that needs it. There is already
evidence: approvals, budgets, audit and identity were implemented in Phase 20.0 inside Factory
Workbench, and the same concerns appear again in the Phase 23 brief for the harness.

**Standing documents.** The target architecture and the constraint review are not phase artifacts.
They describe what the system is meant to be and which decisions still serve it, across all phases.
Under a literal reading of ADR-017 they are the separate planning context it abolished.

## Decision

### 1. Sequential self-contained phases stay

Unchanged. Each phase writes its brief before implementation, implements, and hands over. This ADR
does not reintroduce a planning authority, and no document below may direct a phase — only describe.

### 2. Cross-cutting concerns are specified once and implemented per scope

A concern that applies at every layer is written **once as a normative contract**, and each component
implements it for its own scope.

This is not new — it is ADR-031 §9 applied: *"Contracts between layers live in homelab... Each public
repository additionally carries a normative specification of the contract it must satisfy."* It was
already the rule and was not being used.

**Two implementations of one contract is the design, not duplication.** Workbench approves a merge in
a project; the harness approves a service call on the system. Same shape — bound to one immutable
action including its revision, invalidated when a material input changes, expiring — different
subject. Sharing code would make Factory depend on homelab, which ADR-042 forbids.

**The real risk is drift**, and the mitigation is that the contract is normative, lives in `homelab`,
and both sides' tests are written against it rather than against each other.

### 3. Living specifications are legitimate artifacts

Three kinds of document, with three jobs:

| Document | Answers |
|---|---|
| **ADRs** | What was decided, and why. Historical; never rewritten |
| **Living specs** — the target architecture, per-layer specs | What the system is meant to be, and what is true now |
| **Roadmap** | What order we do it in |

A living spec **decides nothing**. Where it disagrees with an accepted ADR, the ADR wins and the spec
is wrong. That is what keeps it from becoming the planning context ADR-017 removed: it has no
authority, only currency.

The phase that changes a layer updates that layer's spec. Nobody owns the specs but the phases.

### 4. What this does not change

Cross-phase architectural decisions are still recorded as ADRs and carried into the next brief. A
phase still may not apply one silently. `AGENTS.md`'s operating rules are untouched.

## Alternatives considered

**Build each cross-cutting concern once, early, as its own phase.** Rejected: it would specify
approvals and budgets before there is a second consumer to check them against, which is how a
contract acquires one implementation's accidents.

**Let each phase implement what it needs and reconcile later.** Rejected — that is the drift this ADR
exists to prevent, and reconciling two live approval models after both have records is much harder
than agreeing the contract first.

**Reinstate a planning context to hold the architecture.** Rejected outright. ADR-017 removed it for
good reasons. A document with no authority is not a context with authority.

## Consequences

**Easier.** A concern is argued once. A later phase consumes a contract instead of re-deciding it, and
the reasons behind it are readable rather than reconstructed.

**Harder, and it is a real cost.** Living specs must be maintained or they become the worst artifact
in the repository — a confident description of something that is no longer true. A stale spec is worse
than none, because people trust it.

**Newly required:** the Definition of Done gains an item — *the specs for layers this phase touched
are updated* — or the specs will rot within two phases.

**Constrained:** a living spec never decides anything, and never directs a phase.

## Validation / revisit trigger

1. Two components implement the same contract and **both test against the contract**, not each other —
   approvals are the first case, in Workbench and the harness.
2. A phase that changes a layer updates that layer's spec in the same merge.
3. The target architecture and the roadmap do not contradict each other; where they do, one of them is
   fixed rather than both surviving.

**Revisit if:** specs go stale in practice, which means the Definition of Done item is not working and
the honest answer is fewer specs rather than aspirational ones; or the contract-per-scope split starts
producing incompatible behaviour, which would mean §2 is wrong and shared code is needed after all.
