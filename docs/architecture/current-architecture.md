# Current Architecture

**State:** Phase 01 complete — the reference node runs Ubuntu Server. This is the first genuinely
deployed component; everything below it is still planned.

## Physical roles

```text
MacBook Pro
    │  development / administration interface
    │  ssh (password auth — hardened in Phase 03)
    ▼
Lenovo ThinkCentre M700 Tiny  —  "homelab"
    Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic
    UEFI boot · LVM without encryption (ADR-015) · 232 GB root
    Wi-Fi wlp1s0, 2.4 GHz (ADR-016) · eno1 present, unused
    Recovers unattended from AC power loss in ~23 seconds
```

## Deployed

| Component | State |
|---|---|
| Ubuntu Server 26.04.1 LTS | **Active** |
| OpenSSH server (socket-activated) | **Active** — password auth, hardened in Phase 03 |
| netplan + wpasupplicant (Wi-Fi) | **Active** |
| unattended-upgrades | **Active** |
| Wi-Fi power-save suppression | **Active** — `config/systemd/` |

## Confirmed architectural direction

```text
Interface  →  Router  →  Executor  →  Tool / Model / Service
```

The first remote interface is planned to be Telegram. Initial model executors are planned around
Claude Code CLI and OpenAI Codex CLI where officially supported through existing subscriptions.

## Not implemented yet

- SSH key authentication and hardening (Phase 03)
- Tailscale and VS Code Remote SSH (Phase 03)
- Docker / Compose baseline (Phase 05)
- Telegram bot (Phase 07)
- router/executor code (Phase 08)
- knowledge/RAG services (Phase 10)
- automation (Phase 12)
- firewall, encryption at rest (Phase 13)
- local GPU node (Phase 16)

Update this document when a phase changes the actually deployed architecture.
