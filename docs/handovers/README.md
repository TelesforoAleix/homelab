# Phase Handovers

This directory keeps cross-context project memory inside the repository.

Phases are **self-contained and sequential** (ADR-017). Each phase context writes its own brief,
implements the work, and writes a handover addressed to the next phase. There is no separate
planning context.

Lifecycle:

```text
previous phase's handover
    ↓
phase context writes its brief  ← committed BEFORE implementation
    ↓
implementation + tests + docs
    ↓
Definition of Done, applied literally
    ↓
handover written into this directory
    ↓
next phase reads it
```

The brief must be committed before implementation begins. Written afterwards it is documentation,
not governance — and it was Project Planning's review of the brief that caught the most valuable
corrections in Phase 01, a check that no longer exists.

Use `docs/templates/phase-brief-template.md` at phase start and `docs/templates/phase-handover-template.md` at phase completion.

## Current documents

| File | Kind | Status |
|---|---|---|
| `project-planning.md` | Master governance context | **Historical** — retired 2026-09-08 by ADR-017. Retained unrewritten as the record of how Phase 00 and Phase 01 were actually run |
| `01-ubuntu-server.md` | Phase 01 brief | **Ratified** 2026-09-08, subject to six amendments (recorded in its §0.1) — all reconciled |
| `01-ubuntu-server-handover.md` | Phase 01 completion handover | **Returned to Project Planning** 2026-09-08 — outcome Complete |
| `03-remote-access.md` | Phase 03 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation |
| `03-remote-access-handover.md` | Phase 03 completion handover | **Written** 2026-09-09 — addressed to Phase 02; outcome Complete |
| `02-linux-fundamentals.md` | Phase 02 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation |
| `02-linux-fundamentals-handover.md` | Phase 02 completion handover | **Written** 2026-09-09 — addressed to Phase 04; outcome Complete |
