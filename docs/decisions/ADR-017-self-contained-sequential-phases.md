# ADR-017: Self-contained sequential phases; retire the Project Planning context

- **Status:** Accepted
- **Date:** 2026-09-08
- **Supersedes:** the governance model in `PROJECT.md` §13 (two-context model)
- **Superseded by:** none

## Context

Home Lab was bootstrapped with a two-context governance model: a standing **Project Planning**
context owned the roadmap, cross-phase decisions, phase scope and the Definition of Done, while each
phase ran in its own working context. Project Planning wrote the brief; the phase context returned a
handover.

Phase 01 exercised that model fully, and it worked — Project Planning ratified the Phase 01 brief
with six amendments, several of which materially improved it.

The project owner has decided the model is no longer appropriate: **phases are self-contained and
run one after another.** For a single-owner project, maintaining a second standing context is
overhead that the repository can absorb.

## Decision

Retire the separate Project Planning context. **The repository is the sole governance authority.**

Each phase context now owns the whole cycle:

| Function | Previously | Now |
|---|---|---|
| Phase brief | Written by Project Planning, ratified | **Written by the phase context**, committed before implementation begins |
| Roadmap and sequencing | Project Planning | `ROADMAP.md`, amended by the phase that learns something |
| Cross-phase decisions | Escalated to Project Planning | **Recorded as an ADR** and carried into the next phase's brief |
| Handover | Returned to Project Planning | **Written into the repository**, addressed to the next phase |
| Standards and Definition of Done | Project Planning | `PROJECT.md` and `docs/standards/`, amended via ADR |

Reading earlier documents: where an accepted ADR or a Phase 01 document says "escalate to Project
Planning", read it as **"record an ADR and carry it into the next phase's brief."** Those documents
are not edited — see *Consequences*.

## The cost of this change, stated plainly

This removes an independent review step, and that step demonstrably worked. Project Planning's
amendments to the Phase 01 brief produced:

- the `Tested with` vs `Requires` split in ADR-014, without which the project would have implied
  followers needed an exact point release;
- the installer fallback path in ADR-016, which would otherwise have been buried in troubleshooting
  where someone with a dead installer would find it too late;
- the hardening of the power-loss test into four named criteria plus a firmware prerequisite,
  without which the test could have passed vacuously.

A phase context reviewing its own brief will not reliably catch equivalents. Three compensating
controls are therefore **mandatory**, not advisory:

1. **The brief is written and committed before implementation starts.** Its value is as a
   specification, not a retrospective narrative. A brief written afterwards is documentation, not
   governance.
2. **Every handover states what the next phase inherits** — open risks, unsatisfied controls, and
   decisions the next phase must not silently adopt. This replaces the reconciliation Project
   Planning performed.
3. **The Definition of Done is applied literally, item by item.** It is now the only standing check
   on phase quality. Phase 01 showed why that matters: every functional test passed on a machine
   that was quietly degraded, and only a literal reading of the checklist caught it.

## Alternatives considered

- **Keep the two-context model.** It worked. Rejected by the owner as disproportionate overhead for
  a single-person project, which is a legitimate call — the model's benefit is real but its cost is
  paid on every phase.
- **Drop phase briefs entirely** and work directly from `ROADMAP.md`. Rejected. Phase 01 began
  without a brief and the first thing the phase context had to do was write one, because a one-line
  roadmap entry is not a specification. The brief survives; only its authorship changes.
- **Retain Project Planning purely as a reviewer.** Rejected as the same overhead without the
  ownership that made it coherent.

## Consequences

- Faster: no round trip between contexts to start or finish a phase.
- The repository must be read, not assumed. A phase context begins by reading `PROJECT.md`,
  `ROADMAP.md`, `docs/reference/project-state.md`, the previous phase's handover, and the ADRs.
- **Historical documents are not rewritten.** The Phase 01 brief, its handover, the build logs and
  ADR-014/015/016 all reference Project Planning and a ratification that genuinely happened.
  `PROJECT.md` §11 forbids rewriting history to look linear, and that applies to governance history
  too. `docs/handovers/project-planning.md` is retained and marked historical.
- Phase 01's "recommended roadmap changes" had no recipient once this decision took effect. They have
  been actioned directly into `PROJECT.md` and `ROADMAP.md` rather than left orphaned.
- The risk this decision accepts is **scope drift and unreviewed decisions**. There is no longer
  anyone to say "that is a cross-phase change, take it back to planning."

## Validation / revisit trigger

Revisit if any of the following appear:

- a phase begins implementation before its brief is committed;
- a handover omits what the next phase inherits, and the next phase is surprised by an inherited risk;
- a phase silently contradicts an accepted ADR instead of superseding it;
- the Definition of Done starts being marked complete on items that were not literally verified.

Any of these means the compensating controls are not holding, and the review function needs
reinstating in some form.
