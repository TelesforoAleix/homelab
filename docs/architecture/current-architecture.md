# Current Architecture

**State:** Phases 01–07 complete — the reference node runs Ubuntu Server, is administered remotely
over Tailscale with key-only SSH, and has Docker Engine/Compose plus two subscription-authenticated
AI operator CLIs. **The console has been physically removed**; the node is genuinely headless.

**Phase 07 is the first phase to change this document's substance rather than its version numbers.**
The node now runs a service. `Interface → Router → Executor` is no longer entirely aspirational: the
Interface layer exists, as a read-only Telegram bot on its own unprivileged account. The Router and
Executor layers do not, and Phase 08 owns them.

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
    homelab-telegram-bot.service — read-only status bot (ADR-023)
        runs as homelab-bot (uid 999), no shell, no home, no privileged group
        long polling: OUTBOUND HTTPS only, no listening socket
        systemd-analyze security: 1.3 OK
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
| **Telegram status bot** | **Active** — `homelab-telegram-bot.service`, the project's first service. Read-only, standard library only, never forks a process. Long polling means **no listening socket**; isolation proved by attempted access (ADR-023) |

## Confirmed architectural direction

```text
Interface  →  Router  →  Executor  →  Tool / Model / Service
```

**The Interface layer now exists.** A read-only Telegram bot runs as its own unprivileged account
and calls nothing — it answers from `/proc` and `statvfs()` and never forks a process. It is
deliberately not wired to anything: there is no router, no executor, and no escalation path.

Claude Code and Codex work as interactive operator tools through existing subscriptions. They are
**not** executors, and `homelab-bot` provably cannot read either credential. Phase 08 must decide
whether personal subscription credentials are supported or appropriate for unattended use — and must
not resolve it by copying an OAuth file to a service account because it works interactively.

The boundary Phase 08 inherits is a shape, not a proposal: one access check before dispatch, an
account that holds nothing, and a service that cannot execute a program.

## Not implemented yet

- router/executor code (Phase 08)
- knowledge/RAG services (Phase 10)
- automation (Phase 12)
- escalation / privileged actions from the interface (Phase 08 — deliberately absent, see ADR-011)
- alerting or metrics on any service (nothing reports the bot dying)
- any backup of the node (Phase 13)
- firewall, encryption at rest (Phase 13)
- local GPU node (Phase 16)

Update this document when a phase changes the actually deployed architecture.
