# Current Project State

- **Project:** Home Lab
- **Governance:** Self-contained sequential phases; the repository is the sole authority (ADR-017)
- **Current phase:** 02 — Linux Fundamentals (**complete**, 2026-09-09), run after Phase 03 by the
  owner's sequencing decision. Next: Phase 04 — Git & GitHub Fundamentals.
- **Reference node:** Lenovo ThinkCentre M700 Tiny
- **Target OS:** Ubuntu Server 26.04.1 LTS (ADR-014)
- **Current implementation state:** Ubuntu Server 26.04.1 LTS on the reference node, administered
  entirely remotely. `ssh homelab` reaches it over Tailscale by MagicDNS name, authenticated by an
  Ed25519 key; passwords, keyboard-interactive and root login are all refused. VS Code Remote SSH
  works. **The monitor and keyboard have been physically removed** — the node is genuinely headless
  and cold-boots to a reachable state in 25.8s.

## Phase 01 status

| Item | State |
|---|---|
| Phase 01 brief | **Ratified** by Project Planning 2026-09-08 with six amendments, all reconciled (`docs/handovers/01-ubuntu-server.md` §0.1) |
| Guide | ✅ Complete (`guide/01-ubuntu-server/README.md`), including reference-build experience and tested versions — filled in by performing the install, which corrected it five times |
| Scripts | Written and syntax-checked; USB writer safety guards tested |
| ADR-014 / 015 / 016 | **Accepted**, all amended 2026-09-08 per ratification |
| Phase 00 hardware prerequisite | ✅ **Closed** 2026-09-08 — identification and physical validation both complete |
| Installation on hardware | ✅ **Complete** 2026-09-08 |
| Validation | ✅ **Passed**, including unattended power-loss recovery |
| Handover | ✅ [`01-ubuntu-server-handover.md`](../handovers/01-ubuntu-server-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-08 — `77476eb` |

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

- ~~SSH password authentication~~ — ✅ **closed 2026-09-09** by Phase 03 (ADR-018). The server
  advertises `publickey` only.
- **Single SSH key, no backup, and no console.** Phase 03 removed the monitor and left one Ed25519
  key as the only way in. New debt, owned by Phase 13. Phase 02 did not close this — it made
  lockout-class changes *recoverable while remote access still works* (ADR-020), which is a different
  thing from a recovery path.
- **The volume group has no free extents.** The root LV consumes all 235.4 G, so storage cannot be
  grown by `lvextend`; it needs another disk. Found in Phase 02, not owned by any phase yet.
- **Node key expiry deliberately disabled** on the Tailscale node (ADR-019) — a security control
  traded for availability. Phase 13 must revisit it rather than inherit it.
- Wi-Fi is a single point of failure for *both* access routes. `eno1` is present and unused.
- No encryption at rest (ADR-015), which compounds with the cleartext Wi-Fi passphrase (ADR-016).
  Phase 13 should treat these together.
- **Phase 10 must not silently inherit ADR-015.** Once the node stores significant sensitive or
  personal Second Brain data, encryption at rest must be reconsidered on its merits — and converting
  an unencrypted root filesystem after the fact usually means a reinstall.

## Phase 02 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`02-linux-fundamentals.md`](../handovers/02-linux-fundamentals.md), committed before implementation |
| Standard | ✅ [`safe-changes-headless.md`](../standards/safe-changes-headless.md), referenced from `AGENTS.md` |
| ADR-020 | ✅ **Accepted** — change safety on a console-less node |
| Guide | ✅ [`guide/02-linux-fundamentals/`](../../guide/02-linux-fundamentals/README.md) |
| Command reference | ✅ [`linux-command-reference.md`](linux-command-reference.md) |
| Scripts | ✅ `scripts/macos/preflight.sh`, `scripts/server/lab-sandbox.sh` — both run on the real machine |
| Tooling | ✅ `tree` 2.3.1-1, `ncdu` 1.22-1build1, `ripgrep` 15.1.0-1ubuntu1 |
| Validation | ✅ All checks passed with captured output; sandbox created, exercised and removed |
| Handover | ✅ [`02-linux-fundamentals-handover.md`](../handovers/02-linux-fundamentals-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-09 — `0e26859` |

**What Phase 02 deliberately did not teach**, so no later phase assumes it: no networking changes
were practised, no `sudoers` editing, no firewalling, no backup or restore, and no LVM growth. Those
were classified Tier 3 — studied by reading, not by changing — because the node has no console and
Phase 13 will have a better safety net.

## Phase 03 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`03-remote-access.md`](../handovers/03-remote-access.md), committed before implementation |
| Implementation | ✅ Key-only SSH, Tailscale 1.102.3, VS Code Remote SSH, console removed |
| Validation | ✅ All checks passed, re-run after a headless cold boot |
| ADR-018 / ADR-019 | ✅ **Accepted** |
| Guide | ✅ [`guide/03-remote-access/`](../../guide/03-remote-access/README.md) |
| Handover | ✅ [`03-remote-access-handover.md`](../handovers/03-remote-access-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-09 — `5804da6` |

**Sequencing:** the owner chose on 2026-09-09 to run Phase 03 ahead of Phase 02. Phase 01 named SSH
password authentication as its principal open risk, and Phase 02 is a long documentation-heavy phase
that would have left that risk open throughout. Phase 03 also gives Phase 02 a better environment to
be carried out in: key-based login, a stable `ssh homelab` alias, VS Code Remote SSH, and no attached
console. **Phase 02 is deferred, not skipped, and keeps its number.**

## Superseded planning note

The block below was written when Phase 01 closed, before the sequencing decision above. It is kept
rather than rewritten (`PROJECT.md` §11).

**Its instruction has since been discharged.** Phase 02 ran on 2026-09-09 and wrote its brief first,
committing `docs/handovers/02-linux-fundamentals.md` as `6ddf2a5` before any implementation existed.
The block is retained as the record of what was expected, not as an outstanding action.

**Phase 01 is complete and merged. Phase 02 has not started.**

1. **The Phase 02 context writes its own brief** at `docs/handovers/02-linux-fundamentals.md`, using
   `docs/templates/phase-brief-template.md`, and **commits it before implementation begins**
   (ADR-017).

   > Phase 01 began with no brief at all and the phase context had to draft one mid-flight. Under
   > the new model nobody else will write it, so this is now the phase's own first task rather than
   > something to wait for.

2. ~~Review Phase 01's recommended roadmap changes.~~ **Actioned 2026-09-08**, since ADR-017 left
   them with no recipient:
   - system-health assertion added to the Definition of Done in `PROJECT.md` and
     `docs/standards/definition-of-done.md`;
   - the Tailscale documentation warning written into the Phase 03 roadmap entry;
   - the ADR-015 revisit requirement written into the Phase 10 roadmap entry.

3. Sequencing is the owner's call. Phase 02 (Linux Fundamentals) is next by number; Phase 03 (Remote
   Access) closes Phase 01's principal open risk — SSH password authentication.

## Starting state for the next phase

Re-verified 2026-09-09 at the close of Phase 02.

| Fact | Value |
|---|---|
| Host | `homelab`, Lenovo M700 Tiny |
| OS | Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic |
| Primary access | `ssh homelab` → MagicDNS over Tailscale |
| Fallback access | `ssh homelab-lan` → `192.168.1.57` on the LAN |
| Authentication | **Public key only.** No passwords, no keyboard-interactive, no root login |
| Tailnet | `100.71.62.71`; node key expiry disabled |
| Admin user | `aleix`, sudo-capable; **`sudo` requires a password — no `NOPASSWD`** |
| Storage | LVM, 232 GB root, unencrypted |
| Health | `systemctl is-system-running` → `running`, no failed units |
| Tooling | `tmux` 3.6, `htop`, `jq`, `git`, `vim`, `nano`, `less`, `lsof`, plus `tree`, `ncdu`, `ripgrep` |
| Listening | `:22` only off-box; everything else on loopback or the tailnet — unchanged by Phase 02 |
| Boot | 25.8s cold, headless, to reachable |
| **Console** | **None.** Monitor, keyboard and DP→HDMI cable removed; all DRM connectors `disconnected` |

Reproduce with `scripts/server/verify-install.sh` (Phase 01 base) and
`scripts/server/verify-remote-access.sh` (Phase 03 posture; run under `sudo` for a complete report).

> **The console is gone.** This is now a written standard rather than a warning:
> [`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md), adopted as
> ADR-020 and referenced from `AGENTS.md`. Apply it before any change touching network, remote
> access, authentication, boot, or the admin account. `scripts/macos/preflight.sh` checks the parts
> a machine can check.
