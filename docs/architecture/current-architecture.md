# Current Architecture

**State:** Phases 01–06 complete — the reference node runs Ubuntu Server, is administered remotely
over Tailscale with key-only SSH, and has Docker Engine/Compose plus two subscription-authenticated
AI operator CLIs. **The console has been physically removed**; the node is genuinely headless.

Phase 02 changed nothing here, which its brief predicted: it taught the architecture rather than
altering it. Its only lasting change to the node is three diagnostic packages. What it *did* add is
a constraint on how this architecture may be changed from now on —
[`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md) (ADR-020).

## Physical roles

```text
MacBook Pro  —  development / administration interface
    │  Ed25519 key, passphrase in the login keychain (ADR-018)
    │  VS Code Remote SSH over the same "homelab" alias
    │
    ├── ssh homelab      → MagicDNS over Tailscale     ← primary
    │                      WireGuard mesh (ADR-005, ADR-019)
    │
    └── ssh homelab-lan  → 192.168.1.57 on the LAN     ← fallback
                           kept because there is no console any more
    ▼
Lenovo ThinkCentre M700 Tiny  —  "homelab"
    Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic
    UEFI boot · LVM without encryption (ADR-015) · 232 GB root
    Wi-Fi wlp1s0, 2.4 GHz (ADR-016) · eno1 present, unused
    SSH: publickey only. No passwords, no root login (ADR-018)
    Docker Engine 29.8.0 + Compose v5.5.1, rootful (ADR-022)
    Claude Code 2.1.236 + Codex CLI 0.153.4, interactive only (ADR-008)
    NO MONITOR, NO KEYBOARD — all DRM connectors report disconnected
    Cold-boots headless to a reachable state in ~26 seconds
```

## Deployed

| Component | State |
|---|---|
| Ubuntu Server 26.04.1 LTS | **Active** |
| OpenSSH server (socket-activated) | **Active** — key-only; passwords and root login refused (ADR-018) |
| Tailscale 1.102.3 | **Active** — MagicDNS primary route, node key expiry disabled (ADR-019) |
| VS Code Remote SSH | **Active** — `~/.vscode-server` on the node |
| netplan + wpasupplicant (Wi-Fi) | **Active** |
| unattended-upgrades | **Active** |
| Wi-Fi power-save suppression | **Active** — `config/systemd/` |
| Docker Engine / Compose | **Active** — no persistent containers; explicit-interface port publishing required (ADR-022) |
| Claude Code 2.1.236 | **Active** — `aleix`-scoped operator CLI using Claude Pro subscription OAuth; no daemon |
| Codex CLI 0.153.4 | **Active** — `aleix`-scoped operator CLI using Sign in with ChatGPT; no daemon |
| Bubblewrap 0.11.1 | **Active** — Ubuntu package used by the Codex Linux sandbox |

## Confirmed architectural direction

```text
Interface  →  Router  →  Executor  →  Tool / Model / Service
```

The first remote interface is planned to be Telegram. Claude Code and Codex now work as interactive
operator tools through existing subscriptions. They are not yet executors: Phase 08 must decide
whether personal subscription credentials are supported or appropriate for unattended use.

## Not implemented yet

- Telegram bot (Phase 07)
- router/executor code (Phase 08)
- knowledge/RAG services (Phase 10)
- automation (Phase 12)
- firewall, encryption at rest (Phase 13)
- local GPU node (Phase 16)

Update this document when a phase changes the actually deployed architecture.
