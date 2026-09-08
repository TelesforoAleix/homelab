# Project Planning Handover — HISTORICAL

> **Superseded 2026-09-08 by [ADR-017](../decisions/ADR-017-self-contained-sequential-phases.md).**
> The separate Project Planning context has been retired; phases are now self-contained and
> sequential, and the repository is the sole governance authority.
>
> This file is **retained unchanged below** as project history. It describes the model under which
> Phase 00 and Phase 01 were actually run, including the ratification of the Phase 01 brief. Per
> `PROJECT.md` §11, project history is not rewritten to look linear.
>
> Much of its standing content — the audience definition, documentation model, hardware tiers,
> budget model and completion standard — remains valid and is reflected in `PROJECT.md`,
> `docs/standards/` and `docs/reference/`. Where this file and `PROJECT.md` disagree about
> *governance*, `PROJECT.md` and ADR-017 win.

---

## Role of Project Planning

Project Planning is the master governance context for Home Lab.

It owns:

- roadmap and sequencing;
- cross-phase architectural decisions;
- repository/documentation standards;
- phase scope and Definition of Done;
- handovers to/from dedicated phase contexts;
- reconciliation of new learning back into the master architecture.

## Established audience

Business/technical users who are comfortable with technology and some programming but are not experienced Linux/system administration engineers. They want to learn by building an AI lab, automation environment, or second-brain system.

## Documentation model

### `guide/`
Explanation-first human material: enough theory to understand decisions, followed by commands/configuration, tests, alternatives, and actual reference-build lessons.

### `docs/`
Concise operational truth for the real project and future collaborators/AI agents.

## Hardware guidance model

Use three conceptual tiers:

1. Minimum orchestration node.
2. Recommended Home Lab node.
3. Local-AI / GPU node.

The M700 is the canonical reference implementation for the orchestration path. Alternative machines are guidance, not alternate canonical builds.

## Budget model

Record actual spend for hardware, subscriptions, APIs/gateways, and token/usage costs. Add rough reproduction estimates in DKK and EUR where useful. Favor used hardware and budget-friendly choices.

## Phase numbering

Use stable numbered phases. Insert additional work as `x.x-<phase-name>` rather than renumbering established phases.

Multiple pre-development guides may use `00-*`.

## Completion standard

A phase requires working functionality, reproducibility, validation, security consideration, guide + project docs, ADRs where needed, actual costs where applicable, tested versions, lessons/failures, a known-working `main`, and a structured handover.

## AI development rule

AI is intentionally used heavily. Important AI-generated components must remain understandable, testable, documented, and reproducible.

## Transparency rule

Document meaningful mistakes/reversals as:

1. initial assumption;
2. what happened;
3. what was learned;
4. what changed.
