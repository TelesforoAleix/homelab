# Current Project State

- **Project:** Home Lab
- **Master planning context:** Project Planning
- **Current phase:** 01 — Ubuntu Server (**complete**, 2026-09-08). Next: Phase 02 / 03.
- **Reference node:** Lenovo ThinkCentre M700 Tiny
- **Target OS:** Ubuntu Server 26.04.1 LTS (ADR-014)
- **Current implementation state:** Ubuntu Server 26.04.1 LTS installed and validated on the
  reference node. Reachable over SSH from the MacBook and recovers unattended from AC power loss.
  Windows removed.

## Phase 01 status

| Item | State |
|---|---|
| Phase 01 brief | **Ratified** by Project Planning 2026-09-08 with six amendments, all reconciled (`docs/handovers/01-ubuntu-server.md` §0.1) |
| Guide | Written (`guide/01-ubuntu-server/README.md`); reference-build experience and tested versions still empty by design |
| Scripts | Written and syntax-checked; USB writer safety guards tested |
| ADR-014 / 015 / 016 | **Accepted**, all amended 2026-09-08 per ratification |
| Phase 00 hardware prerequisite | ✅ **Closed** 2026-09-08 — identification and physical validation both complete |
| Installation on hardware | ✅ **Complete** 2026-09-08 |
| Validation | ✅ **Passed**, including unattended power-loss recovery |
| Handover | ✅ [`01-ubuntu-server-handover.md`](../handovers/01-ubuntu-server-handover.md) |
| `main` known-working | ⏳ pending merge of `feature/01-ubuntu-server` |

### Phase 00 closure

Phase 00's documentation and governance work was complete at bootstrap. Its remaining
hardware-verification checks were executed as **Phase 01 Part A**, as Project Planning ruled in
amendment 2 — no separate hardware implementation phase or working context was needed.

The agreed closure condition was that the Part A checklist be recorded in
`docs/reference/hardware.md`, with this file and `ROADMAP.md` updated to say so. That has been done.

**Status 2026-09-08: CLOSED.** Both halves of Part A are complete. Identification recorded RAM
layout, storage, wireless adapter and CPU; physical validation confirmed USB ports, video output and
acceptable fan noise. **Phase 00 is finished** — see `ROADMAP.md`.

## Accepted high-level decisions

See `docs/decisions/` for full ADRs. Current direction includes:

- used budget hardware as the reference platform;
- M700 as orchestration/infrastructure node;
- Ubuntu Server LTS as the hard requirement; 26.04.1 LTS as the *tested* reference build, with its
  ISO and checksum pinned for reproducibility rather than as a constraint (ADR-014);
- whole-disk LVM without full-disk encryption, chosen for unattended headless boot — a
  reference-build trade-off rather than a universal recommendation (ADR-015);
- Wi-Fi as the reference node's *initial* network link, with Ethernet preferred where practical, a
  documented installer fallback path, and reliability to be validated (ADR-016);
- MacBook-driven remote development;
- SSH keys + Tailscale + VS Code Remote SSH;
- model-agnostic architecture;
- explicit router/executor layers before agent frameworks;
- subscription-backed Claude Code/Codex first where officially supported;
- Telegram as first remote interface;
- knowledge storage separate from agents;
- unprivileged user-facing services;
- progressive automation;
- known-working `main` branch.

## Recently resolved (Phase 01 Part A, 2026-09-08)

- ✅ **M700 RAM module layout** — **1 × 8 GB, one of two slots occupied.** Open since project
  bootstrap. Upgrade path is now 8+8 = 16 GB, with 8+16 = 24 GB optional. **No upgrade is required
  before or during Phase 01.**
- ✅ **Wireless adapter model** — **Intel Dual Band Wireless-AC 8260 (802.11ac).** Uses the in-tree
  `iwlwifi` driver with `iwlwifi-8000C` firmware, which ships in Ubuntu's `linux-firmware` package.
  The ADR-016 risk that the installer cannot see the card is **substantially reduced**; the fallback
  path is retained but is now unlikely to be needed.

## Known unknowns

- Exact versions of tools to be installed in future phases.
- Exact Claude/ChatGPT subscription costs to record in the ledger.
- Public repository license.
- Final GitHub repository owner/name if different from `homelab`.

## Open risks carried forward

- SSH password authentication will be enabled by the Phase 01 install and is only closed in Phase 03.
- No encryption at rest (ADR-015), which compounds with the cleartext Wi-Fi passphrase (ADR-016).
  Phase 13 should treat these together.
- **Phase 10 must not silently inherit ADR-015.** Once the node stores significant sensitive or
  personal Second Brain data, encryption at rest must be reconsidered on its merits — and converting
  an unencrypted root filesystem after the fact usually means a reinstall.

## Immediate next planning action

**Phase 01 is complete and merged. Phase 02 has not started.**

1. **Project Planning must create the Phase 02 brief** at `docs/handovers/02-linux-fundamentals.md`,
   using `docs/templates/phase-brief-template.md`.

   > This is deliberately the first item. Phase 01 began with no brief — `project-state.md` had
   > listed creating one as the next planning action and it had never been done, so the phase context
   > had to draft its own and mark it *Proposed*. Nothing in the process detects a missing brief; the
   > phase context is the first to notice. Do not repeat that.

2. Review the three recommendations in the Phase 01 handover (§ Recommended roadmap changes),
   especially **adding a system-health assertion to the project-wide Definition of Done** in
   `PROJECT.md`. Phase 01 demonstrated that every functional test can pass on a degraded machine.

3. Decide sequencing. Phase 02 (Linux Fundamentals) and Phase 03 (Remote Access) are both unblocked.
   Phase 03 closes this phase's principal open risk — SSH password authentication — so if that risk
   is a concern it should come first.

## Starting state for the next phase

Verified as of 2026-09-08:

| Fact | Value |
|---|---|
| Host | `homelab`, Lenovo M700 Tiny |
| OS | Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic |
| Access | SSH from the MacBook, **password authentication** |
| Address | 192.168.1.57/21 over Wi-Fi `wlp1s0` (no DHCP reservation) |
| Admin user | `aleix`, sudo-capable; no direct root login |
| Storage | LVM, 232 GB root, 214 GB free, unencrypted |
| Health | `systemctl is-system-running` → `running`; boots in 23s |
| Recovery | Returns unattended from AC power loss (validated) |
| Console | Monitor and keyboard still attached; removed once Phase 03 proves remote access |

Reproduce this state check at any time with `scripts/server/verify-install.sh`.
