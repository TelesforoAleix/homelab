# Definition of Done

This is a convenience copy of the project-wide phase completion standard in `PROJECT.md`.

A phase is complete when all applicable items are satisfied:

- [ ] Functional objective works.
- [ ] Configuration/setup is reproducible.
- [ ] Validation/tests have passed.
- [ ] Important security implications were considered.
- [ ] Relevant repository files are committed.
- [ ] Human-facing guide is updated.
- [ ] Project/internal documentation is updated.
- [ ] ADRs are created or updated where necessary.
- [ ] Actual costs are recorded where applicable.
- [ ] Problems, failed approaches, and lessons are recorded.
- [ ] Tested versions are recorded.
- [ ] No unexplained critical AI-generated component remains.
- [ ] `main` represents a known-working state.
- [ ] The system reports no failed units and no degraded state.
- [ ] A structured handover is written into `docs/handovers/`, stating what the next phase inherits.

## Note on the health check

The "no failed units / no degraded state" item was added after Phase 01 (ADR-017). That phase
produced a machine which passed every functional test — installed, reachable over SSH, surviving a
power cut — while a boot unit failed and every startup wasted two minutes. Functional success does
not imply a healthy system. On Linux, `systemctl is-system-running` and `systemctl --failed` are the
cheap check.
