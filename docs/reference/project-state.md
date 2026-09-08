# Current Project State

- **Project:** Home Lab
- **Master planning context:** Project Planning
- **Current phase:** 00 — Pre-development / repository bootstrap
- **Reference node:** Lenovo ThinkCentre M700 Tiny
- **Target OS:** Ubuntu Server LTS
- **Current implementation state:** Repository/bootstrap only; server stack not yet installed through this repository workflow

## Accepted high-level decisions

See `docs/decisions/` for full ADRs. Current direction includes:

- used budget hardware as the reference platform;
- M700 as orchestration/infrastructure node;
- Ubuntu Server LTS;
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

- M700 RAM module layout (1×8 GB vs 2×4 GB).
- Exact versions of tools to be installed in future phases.
- Exact Claude/ChatGPT subscription costs to record in the ledger.
- Public repository license.
- Final GitHub repository owner/name if different from `homelab`.

## Immediate next planning action

Create a dedicated Phase 01 Ubuntu Server brief/handover after any remaining Phase 00 hardware/pre-installation checks are completed.
