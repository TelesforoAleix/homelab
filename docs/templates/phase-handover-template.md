# Phase XX Handover — <Phase name>

## Outcome

Complete / Partial / Blocked

## What the next phase inherits

**The section the next phase reads first.** Everything it must know before writing its own brief,
consolidated here rather than scattered across the sections below:

- **Verified starting state** — what actually exists and is running, with how to re-verify it.
- **Open risks** — including which phase is expected to close each.
- **Unsatisfied controls** — anything an accepted ADR requires that was not achieved, and why.
- **Decisions that must not be silently inherited** — where an assumption behind an accepted ADR may
  no longer hold for the next phase.
- **Ground already covered** — work this phase did incidentally that the next phase should build on
  rather than repeat.

Under ADR-017 there is no planning context to reconcile this; if it is not written here, it is lost.

## What was implemented

Concise description of the final working state.

## Final architecture/state

What changed relative to the starting state?

## Validation performed

Commands/tests/checks and results.

## Files changed

Key repository files/directories added or modified.

## Guide updates

Human-facing documentation produced/changed.

## Project documentation updates

Operational docs produced/changed.

## ADRs

Created, accepted, superseded, or proposed decisions.

## Tested versions

Actual versions used in the reference implementation.

## Security notes

Controls introduced, remaining risks, permissions, secrets handling.

## Costs

Actual new one-time, recurring, or usage-based costs.

## Problems / failures / lessons

Include meaningful mistakes and reversals.

## Deviations from phase brief

What changed and why?

## Open issues / technical debt

Anything deliberately deferred.

## Recommended roadmap changes

Cross-phase consequences. Action them directly into `ROADMAP.md`/`PROJECT.md` — there is no planning context to receive them (ADR-017).

## Definition of Done

- [ ] Functional objective works
- [ ] Reproducible
- [ ] Validated/tested
- [ ] Security considered
- [ ] Repository updated
- [ ] Guide updated
- [ ] Project docs updated
- [ ] ADRs handled
- [ ] Costs recorded
- [ ] Failures/lessons recorded
- [ ] Tested versions recorded
- [ ] Critical AI-generated components understood
- [ ] `main` known-working
- [ ] System reports no failed units / not degraded
- [ ] Handover written into `docs/handovers/`, stating what the next phase inherits
