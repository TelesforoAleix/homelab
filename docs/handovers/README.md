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
| `01-ubuntu-server.md` | Phase 01 brief | **Ratified** 2026-09-08, subject to six amendments (recorded in its §0.1) — all reconciled |
| `01-ubuntu-server-handover.md` | Phase 01 completion handover | **Returned to Project Planning** 2026-09-08 — outcome Complete |
