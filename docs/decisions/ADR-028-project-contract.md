# ADR-028: The Project Contract

- **Status:** Accepted
- **Date:** 2026-09-10
- **Supersedes:** none
- **Superseded by:** none

## Context

The Factory is designed to operate on many projects. Its own README says so: *"It is not
built for any single project, but should be reusable for
future tools, products, demos, and client/project work."*

Today it has operated on two — itself, and one product project — and both sets of records live inside the same
private repository as the method that produced them. That works while there is one repository. It
stops working the moment The Factory becomes a public repository (ADR-029) and projects get their
own private ones.

The Factory has already designed most of the answer. `templates/project-workspace/` defines a
workspace with `.github/`, `agents/`, `product/` and `ops/`, the last with fourteen subfolders —
tasks, tickets, runs, reviews, releases, approvals, context-packs, interactions, learning and more.
`FIRST-USE.md` already instructs the operator to *"Confirm whether the project is general Factory
work or work on a specific project."*

It also poses one question and deliberately leaves it open:

> *"Decide whether project-local `agents/` should copy definitions, sync selected files, or only
> link back to the brain for now."*

This ADR answers it, and states the rule that makes The Factory reusable rather than forked.

## Decision

### 1. The Factory is stateless method; the project carries all state

The Factory repository contains agents, skills, workflows, roles, departments and templates. It
contains **no record of any project it has been operated on** — no tickets, no runs, no reviews, no
approvals, no decisions.

Every operational record belongs to the project it was produced for. This is ADR-029's
method/output boundary applied to a running system: The Factory is the method, and everything
produced by operating it is output.

### 2. Every Factory-managed project holds its own coordination layer

A project gets the `project-workspace/` structure inside its own repository. That workspace is where
The Factory reads current state and writes results. It is the project's coordination layer, and it
lives with the project so that the project remains understandable without The Factory present.

A project repository must be readable on its own. Someone opening it should be able to see what was
decided and why, without cloning a second repository to interpret it.

### 3. Project-local `agents/` references The Factory; it never copies it

This answers `FIRST-USE.md` §3.

**A copy forks silently. A reference breaks loudly.** If each project vendors its own copy of the
role specifications, then a fix to a role boundary reaches no existing project, every project drifts
independently, and the claim that The Factory is reusable becomes false one project at a time —
with nothing reporting that it happened.

What a project holds locally is **selection and override**: which agents and skills are enabled for
this project, and any project-specific narrowing of them. Narrowing is permitted. Widening is not —
a project may not grant an agent authority the Factory definition does not give it, for the same
reason ADR-027 §3 puts enforcement in the runtime rather than the manifest.

### 4. A project records which version of The Factory it ran under

Because The Factory evolves quickly and projects do not, a reference to "current Factory" would mean
a role's authority could change retroactively under a project already in flight, and the project's
own records would no longer describe the rules they were produced under.

So each project records the Factory commit or tag its workspace is operating against, and updates it
deliberately. This is the same discipline `PROJECT.md` §9 already applies to software: **record the
version actually used**, distinguishing what was tested from what is required.

### 5. A project declares its identity, and The Factory targets exactly one

Before The Factory does work, the project declares: its identity, what knowledge is in scope, and
which agents and skills are enabled. The Factory operates on one project at a time and **writes
only inside the project it was invoked for**.

There is no ambient "current project". A Factory operation that cannot name its target does not run.

### 6. The Factory's own records are project records too

The Factory being operated on itself is not a special case — it is a project, and its 22 dogfood
tickets, runs and reviews are that project's output. They do not travel with the public method
repository.

Where they land is left open in ADR-029 §6 and decided during the split, with the files in view.
What is decided here is that they are **output**, and so cannot go public with the method.

## Alternatives considered

**Copy Factory definitions into each project (vendoring).** Genuinely tempting: it makes each
project self-contained and immune to upstream change, which is the property §4 works to recover by
other means. Rejected because it defeats reusability — improvements never propagate, and drift is
invisible rather than merely inconvenient. §4 gets the pinning benefit without the forking cost.

**Keep per-project state inside The Factory, one folder per project.** This is effectively the
current arrangement. Rejected: it makes a public method repository accumulate private operational
records, which ADR-029 forbids, and it means a project cannot be understood without access to The
Factory.

**Let The Factory infer the project from the working directory.** Rejected: an ambient current
project is how work gets written into the wrong repository. §5 requires an explicit target for the
same reason Phase 08's escalation names one unit rather than accepting whatever it is given.

**No project-local `agents/` at all — everything resolved from The Factory at run time.** Rejected:
projects legitimately differ in which agents are enabled and how narrowly, and there must be a place
to record that which is not the shared method.

## Consequences

**Easier:** The Factory becomes genuinely reusable and publishable. A project repository is
self-contained and readable. Improving a role improves it everywhere at once, at each project's
chosen pace.

**Harder:** cross-repository resolution. A project workspace referencing Factory definitions needs a
mechanism to resolve them — a submodule, a pinned clone, or a fetch. That mechanism is not chosen
here and belongs to the phase that first needs it.

**Newly required:** every project records a Factory version and updates it deliberately. A project
that never updates is a project running on old rules, which is acceptable but should be visible.

**Constrained:** a project can narrow an agent but never widen it. Some genuinely project-specific
authority may therefore need to become a Factory-level concept first, which is slower — and is the
intended trade.

**Deferred:** the resolution mechanism in the paragraph above; where The Factory's own dogfood
records land (ADR-029 §6); and whether a project workspace should live at the repository root or in
a subdirectory.

## Validation / revisit trigger

Revisit if:

- the narrowing-only rule in §3 blocks a legitimate project need more than once;
- version pinning in §4 proves to be ignored in practice, which would mean it needs to be enforced
  rather than recorded;
- a project genuinely needs two Factory versions at once, which this ADR does not contemplate.

**Validation required before this ADR is considered implemented:**

1. A project workspace resolves Factory definitions **without a local copy of them**, demonstrated
   on a real project rather than the template.
2. A project attempting to widen an agent's authority beyond its Factory definition is **refused, on
   the reason** — tested against a positive control, not observed to fail.
3. A Factory operation invoked without a named target project **does not run**.
4. The Factory repository contains no ticket, run, review, approval or decision record belonging to
   any project — checked by the ADR-029 §5 boundary gate, which must itself be validated against
   planted content.
