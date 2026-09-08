# Phase Handovers

This directory keeps cross-context project memory inside the repository.

The master Project Planning context creates the brief for a dedicated phase. The phase-specific working context implements the work and returns a structured handover.

Suggested lifecycle:

```text
Project Planning
    ↓
phase brief / handover file
    ↓
phase-specific chat + IDE/AI tools
    ↓
implementation + tests + docs
    ↓
completed handover
    ↓
Project Planning
```

Use `docs/templates/phase-brief-template.md` at phase start and `docs/templates/phase-handover-template.md` at phase completion.

## Current documents

| File | Kind | Status |
|---|---|---|
| `project-planning.md` | Master governance context | Standing |
| `01-ubuntu-server.md` | Phase 01 brief | **Proposed** — drafted by the phase context because no brief had been created; awaiting Project Planning ratification |
