# Services

Runnable Home Lab services belong here: the Telegram interface, and in future the router,
executors, knowledge services or APIs.

| Service | State |
|---|---|
| [`telegram-bot/`](telegram-bot/) | **Active** since Phase 07 — read-only status bot, standard library only, runs as the unprivileged `homelab-bot` account with no listening socket (ADR-023) |

Anything added here runs on a node with no console and no firewall. Two rules from Phase 07 apply to
whatever comes next:

- **A service gets its own unprivileged account.** Never `aleix`, never the `docker` group, never a
  shared identity. Prove the isolation by attempting the access, not by reading the unit file.
- **Prefer outbound-only.** The Telegram bot needs no inbound port because it long-polls. Anything
  that wants to listen is a change to the node's exposure model and needs an ADR, not a config line.
