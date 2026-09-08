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
| Phase 01 brief | Drafted by the phase context, **pending Project Planning ratification** (`docs/handovers/01-ubuntu-server.md`) |
| Guide | Written (`guide/01-ubuntu-server/README.md`); reference-build experience and tested versions still empty by design |
| Scripts | Written and syntax-checked; USB writer safety guards tested |
| ADR-014 / 015 / 016 | Accepted |
| Installation on hardware | **Not started** |
| Validation | **Not started** |

## Accepted high-level decisions

See `docs/decisions/` for full ADRs. Current direction includes:

- used budget hardware as the reference platform;
- M700 as orchestration/infrastructure node;
- Ubuntu Server LTS, pinned to 26.04.1 LTS (ADR-014);
- whole-disk LVM without full-disk encryption, chosen for unattended headless boot (ADR-015);
- Wi-Fi as the reference network link, with reliability to be validated (ADR-016);
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

## Known unknowns

- M700 RAM module layout (1×8 GB vs 2×4 GB) — scheduled for Phase 01 Part A; also recoverable
  afterwards via `sudo dmidecode -t memory`.
- **Wireless adapter model** — newly identified as a Phase 01 risk. If the installer cannot detect
  the card, ADR-016 must be revisited and the change escalated to Project Planning.
- Exact versions of tools to be installed in future phases.
- Exact Claude/ChatGPT subscription costs to record in the ledger.
- Public repository license.
- Final GitHub repository owner/name if different from `homelab`.

## Open risks carried forward

- SSH password authentication will be enabled by the Phase 01 install and is only closed in Phase 03.
- No encryption at rest (ADR-015), which compounds with the cleartext Wi-Fi passphrase (ADR-016).
  Phase 13 should treat these together.

## Immediate next planning action

1. Project Planning ratifies or amends the Phase 01 brief.
2. The install is performed on the M700 following `guide/01-ubuntu-server/README.md`.
3. Real output is recorded into the guide, `hardware.md`, `software-stack.md` and the build log
   before Phase 01 is declared complete.
