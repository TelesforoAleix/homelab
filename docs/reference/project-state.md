# Current Project State

- **Project:** Home Lab
- **Master planning context:** Project Planning
- **Current phase:** 01 — Ubuntu Server (**in progress**)
- **Reference node:** Lenovo ThinkCentre M700 Tiny
- **Target OS:** Ubuntu Server 26.04.1 LTS (ADR-014)
- **Current implementation state:** Repository, Phase 01 brief, guide, scripts and ADRs prepared.
  **The operating system has not yet been installed** — the reference node still runs its original
  Windows installation.

## Phase 01 status

| Item | State |
|---|---|
| Phase 01 brief | **Ratified** by Project Planning 2026-09-08 with six amendments, all reconciled (`docs/handovers/01-ubuntu-server.md` §0.1) |
| Guide | Written (`guide/01-ubuntu-server/README.md`); reference-build experience and tested versions still empty by design |
| Scripts | Written and syntax-checked; USB writer safety guards tested |
| ADR-014 / 015 / 016 | **Accepted**, all amended 2026-09-08 per ratification |
| Phase 00 hardware prerequisite | Part A **identification complete** 2026-09-08; physical validation (USB / video / fan) still outstanding |
| Installation on hardware | **Not started** |
| Validation | **Not started** |

### Phase 00 closure

Phase 00's documentation and governance work is complete. Its only outstanding items are the
hardware-verification checks, which Project Planning ruled (amendment 2) are executed as **Phase 01
Part A** — there is no separate hardware implementation phase or working context.

**Closure condition:** when the Part A checklist is recorded in `docs/reference/hardware.md`, the
Phase 00 prerequisite is satisfied and both this file and `ROADMAP.md` must be updated to say so.

**Status 2026-09-08:** the *identification* half of Part A is done and recorded — RAM layout,
storage, wireless adapter and CPU are all confirmed. The *validation* half — USB ports, video
output, fan noise under load — has not been reported. Phase 00 therefore remains open on that one
item, which is quick to complete while the monitor is still attached.

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

- Whether the essential physical checks (USB ports, video output, fan noise) pass — the last item
  gating Phase 00 closure.
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

1. ~~Project Planning ratifies or amends the Phase 01 brief.~~ **Done 2026-09-08** — ratified with
   six amendments, all reconciled.
2. ~~Perform Part A identification.~~ **Done 2026-09-08** — results recorded in
   `docs/reference/hardware.md`.
3. Complete the remaining Part A physical checks (USB, video, fan), closing Phase 00.
4. In Part D, enable CPU virtualization, set `After Power Loss -> Power On`, and preserve UEFI boot.
5. Perform Parts B–F following `guide/01-ubuntu-server/README.md`.
6. Record real output into the guide, `hardware.md`, `software-stack.md` and the build log.
7. Phase 01 is not complete until the unattended AC power-loss recovery test passes on all four
   proof points (boot, network, SSH, remote reachability).
