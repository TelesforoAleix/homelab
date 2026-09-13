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
| `04-git-github.md` | Phase 04 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation |
| `04-git-github-handover.md` | Phase 04 completion handover | **Written** 2026-09-09 — addressed to Phase 05; outcome Complete |
| `05-docker.md` | Phase 05 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation |
| `05-docker-handover.md` | Phase 05 completion handover | **Written** 2026-09-09 — addressed to Phase 06; outcome Complete |
| `06-ai-cli-access.md` | Phase 06 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation |
| `08-router-executors.md` | Phase 08 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation |
| `08-router-executors-handover.md` | Phase 08 completion handover | **Written** 2026-09-09 — addressed to Phase 09; outcome Complete |
| `07-telegram.md` | Phase 07 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation |
| `07-telegram-handover.md` | Phase 07 completion handover | **Written** 2026-09-09 — addressed to Phase 08; outcome Complete |
| `06-ai-cli-access-handover.md` | Phase 06 completion handover | **Written** 2026-09-09 — addressed to Phase 07; outcome Complete |
| `09-model-executor.md` | Phase 09 brief | **Accepted** 2026-09-09, self-ratified under ADR-017; committed before implementation as `351f825`. Carries the roadmap amendment (Voice → Phase 17) in its §0.1 |
| `09-model-executor-handover.md` | Phase 09 completion handover | **Written** 2026-09-09 — addressed to the **foundations** phase (backup + ADR-015 encryption); outcome Complete. Records three deviations |
| `18-foundations.md` | Phase 18 brief | **Accepted** 2026-09-10, self-ratified under ADR-017; committed before implementation. Carries ADR-026..029 forward per §0.2, and records the **TPM 1.2** finding that reshapes the ADR-015 decision |
| `18-foundations-handover.md` | Phase 18 handover | **Complete** 2026-09-11. All five objectives met. Three of the brief's own premises proved wrong: the console existed all along, the package is `libtss2-rc0t64`, and the SHA-256 PCR bank cannot be allocated from Linux at all. Produces **ADR-032**, whose content gate binds Phase 21 and Phase 10 — **discharged for the
  encrypted volume by ADR-037 §7**; the unencrypted root still may not hold it |
| `15.0-model-registry.md` | Phase 15.0 brief | **Accepted** 2026-09-10, self-ratified under ADR-017; committed before implementation. Implements ADR-026 §2/§3/§4/§6. ~~Sequenced after Phase 18~~ **Revised 2026-09-13** before implementation: inherits ADR-033 (provider chosen, nothing metered here), ADR-034 §5 (routing key is the role; hints never select), ADR-047 and the Phase 13 baseline; §6.5–6.6 added; tests 11–15 added; socket baseline seven. **Implemented and closed 2026-09-13**; §9 amended during S1 (`metered`/`credential` presence refused, reason stated) |
| `23-homelab-ai-foundation.md` | Phase 23 brief | **Accepted** 2026-09-11, self-ratified under ADR-017; committed before implementation. Implements ADR-034 §5/§11/§13, ADR-033 §5, ADR-035 §4. Its §0.1 records that **two accepted gates** constrain the phase's own core capability — ADR-032 §2 (no project content on the node) and ADR-025 §8 (only the question may leave) — and §0.2 makes *where the harness runs and what may leave* a checkpoint decision before implementation. Resolves Phase 20.0's inherited adapter risk. **Superseded in part 2026-09-11** by ADR-037 – ADR-044: both gates in its §0.1 are resolved and §0.2's checkpoint decision is taken. Preserved unrewritten; a fresh brief is owed |
| `20.0-minimal-factory-workbench-handover.md` | Phase 20.0 handover | **Complete** 2026-09-11. All seven objectives met; delivered into **`factory`**, not this repository. 41 tests, the synthetic project's 14 steps and 7 planted refusals, and a clean-clone run with no homelab — which discharges **ADR-031 §4** by demonstration. Produces **ADR-036**. Records two bugs found by running it: a `git reset --hard` that deleted an approval record, and `rev-parse` failing on an unborn branch. **States plainly that the adapter interface is unproved** — one implementation only |
| `20.0-minimal-factory-workbench.md` | Phase 20.0 brief | **Accepted** 2026-09-11, self-ratified under ADR-017; committed before implementation. Implements ADR-035 §2/§4/§5/§7 and ADR-034 §6. The deliverable lands in the **`factory`** repository, not this one. Records a verified reading of Factory at `97ccb86`: the **read half already exists** as an 864-line read-only `dashboard/`, and a browser page **cannot** run the acceptance project — §6.1 is the decision that shapes the phase. **Amended the same day** on the owner's correction: Factory's V1.6/V2/V3 already specify the writable control plane and already framed the CLI/server/webview bridge decision, and what exists is an **MVP, not a constraint** |
| `19-tool-vocabulary.md` | Phase 19 brief | **Superseded 2026-09-11 before implementation. Do not implement.** Originally accepted 2026-09-10 and preserved unrewritten as history; its five-name vocabulary was rejected and it is no longer a prerequisite for Phase 20. |
| `19-tool-vocabulary-design-review-outcome.md` | Design-review handover | **Written 2026-09-11.** The owner rejected Phase 19's direct Factory→Homelab tool coupling before implementation. Records the replacement portable-capability/backend-tool boundary, Factory Workbench, agent/project/approval model, synthetic acceptance project, required successor ADRs, roadmap consequences, and unresolved decisions. **The current Phase 19 brief must not be implemented.** |
| `18.1-encryption-execution.md` | Phase 18.1 brief | **Accepted** 2026-09-11 (ADR-045), self-ratified under ADR-017; committed before implementation. Executes ADR-037 §0–§7 and proposes ADR-046 alongside it |
| `18.1-encryption-execution-handover.md` | Phase 18.1 completion handover | **Written** 2026-09-12 — addressed to Phase 18.2, Phase 12, Phase 13 and Phase 14; outcome Complete. Records six runbook defects found by execution, the declined `blkdiscard` proposal, and the owner's decision to decline §6.5's `/status` lock-state line |
| `12-scheduling-monitoring-notifications.md` | Phase 12 brief | **Merged to `main`** 2026-09-12 (`ab093ef`) before implementation per ADR-017. Scheduler as trigger source, watchdog, notifier; §6 forbids any model call from this phase |
| `12-scheduling-monitoring-notifications-handover.md` | Phase 12 completion handover | **Written** 2026-09-12 — addressed to Phase 18.2, Phase 15.1 and whoever next touches `homelab-notify@.service`; outcome Complete. Records the `last`-is-missing episode and its wrong first conclusion, two `pipefail` traps, and the per-crash `OnFailure=` semantics |
| `18.2-migration-to-the-server.md` | Phase 18.2 brief | **Merged to `main`** 2026-09-12 (`93e9af8`) before implementation per ADR-017; **corrected during S1** (§6.3, §6.4, §6.6, §8 row 7, §16) with the observations in the commit. Five clones into the volume, Workbench as a loopback service, the tunnel, the socket-accounting rule |
| `18.2-migration-to-the-server-handover.md` | Phase 18.2 completion handover | **Written** 2026-09-12 — addressed to Phase 13 (promoted to next), Phase 23.0 and Phase 14; outcome Complete. Records the `WorkingDirectory=` → `RequiresMountsFor=` false alert, the SSH alias split, that the Workbench never commits, and the `factory-ops` record findings |
| `13-security-hardening.md` | Phase 13 brief | **Merged to `main`** 2026-09-12 (`1b35b0b`) before implementation per ADR-017; **corrected during S1** (§2, §4.2, §6.4, §8 row 6 — IPv6 `FORWARD` already `DROP`; "every service unit"). Walks every item addressed to Phase 13 by name (18.2, 18.1, 18, 03 debts, project-state) to an OBSERVED outcome — closed, narrowed or declined with a reason; service security baseline as a standard; ADR-046 revalidated; BIOS password, console timeout, Tailscale ACL, `DOCKER-USER`, second SSH key; `systemd-creds` evaluated under three conditions |
| `15.0-model-registry-handover.md` | Phase 15.0 completion handover | **Written** 2026-09-13 — addressed to Phase 15.1, Phase 23.0 and Phase 14; outcome Complete. The provider/model/route entry shapes to copy; how the refusal was proved (fixture derived from the example, positive control, node run as `aleix`); the owner floor and its number (half); fallback within a route only; `metered`/`credential` presence refused until the governor; the wire protocol field by field for 23.0; five lessons incl. the fixture that passed vacuously and the installer's own probe in the swap window |
| `13-security-hardening-handover.md` | Phase 13 completion handover | **Written** 2026-09-13 — addressed to Phase 15.0 (next), Phase 23.0 and Phase 14; outcome Complete. 27 items closed/narrowed/declined; the watchdog-loads-the-token finding; the TPM seal (pulled disk) vs BIOS password (USB boot) distinction; two PREDICTED rows named; twelve lessons including the same-day backup overwrite handed to Phase 14 |
