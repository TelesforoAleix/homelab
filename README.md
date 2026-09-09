# Home Lab

**Home Lab** is a learning-first, self-hosted AI systems laboratory built on inexpensive hardware.

The project explores how interfaces, agents, model providers, tool execution, knowledge retrieval, automation, infrastructure, security, and eventually local AI fit together. The goal is not to rush toward a single finished assistant. The goal is to understand the layers by building them progressively, replacing components intentionally, and documenting the trade-offs.

## Reference build

The canonical implementation uses a **Lenovo ThinkCentre M700 Tiny** as an always-on orchestration and infrastructure node.

Current known hardware:

- Intel Core i5-6600T — 4 cores / 4 threads
- 8 GB DDR4 RAM
- 256 GB SSD
- Wi-Fi
- Bluetooth
- Purchase price: **700 DKK used**

This machine is intentionally **not** a local-LLM workstation. Hosted AI models are used first. A separate NVIDIA/CUDA node may be added later if local inference becomes relevant.

## Who this project is for

This repository is aimed at people with a business and some technical background who are comfortable with computers and light programming, but who are not necessarily experienced Linux or systems engineers. It is intended for people who want to learn by building their own AI lab, automation environment, or personal knowledge system.

## Documentation model

- [`guide/`](guide/) — explanation-first material for people reproducing and learning from the project.
- [`docs/`](docs/) — concise operational truth about the reference implementation: architecture, decisions, build history, costs, state, and handovers.
- [`PROJECT.md`](PROJECT.md) — the working contract for humans and AI agents contributing to the repository.
- [`ROADMAP.md`](ROADMAP.md) — planned implementation phases.

## Project philosophy

1. Build simple layers before adopting large frameworks.
2. Understand important AI-generated code and configuration before calling it complete.
3. Document decisions, including mistakes and reversals.
4. Prefer reproducible configuration over undocumented manual state.
5. Keep the system model-agnostic.
6. Treat security as part of the learning objective.
7. Keep `main` in a known-working state.
8. Optimize the reference build for affordability and learning, not maximum compute.

## Current status

**Phases 00–09 complete.** Next: **foundations** — backup, plus the disk-encryption decision left
open in ADR-015.

| Phase | State |
|---|---|
| 00 — Repository bootstrap & planning | ✅ Complete |
| 01 — Ubuntu Server on the reference node | ✅ Complete |
| 03 — Remote access (SSH keys, Tailscale, VS Code) | ✅ Complete — run ahead of 02 by choice |
| 02 — Linux fundamentals | ✅ Complete |
| 04 — Git & GitHub fundamentals | ✅ Complete |
| 05 — Docker & Docker Compose | ✅ Complete |
| 06 — AI CLI Access | ✅ Complete |
| 07 — Telegram interface | ✅ Complete |
| 08 — Router & executors | ✅ Complete |
| 09 — Model executor (subscription-backed) | ✅ Complete |

The reference node runs Ubuntu Server 26.04.1 LTS, is administered entirely remotely over Tailscale
with key-only SSH, and has **no monitor or keyboard attached**. Docker Engine and Compose are
installed, with no persistent containers running.

You can message the node from a phone and get an answer: host status, one allowlisted service
restart, or a question passed to a model. See [`ROADMAP.md`](ROADMAP.md) for what comes next and
[`docs/reference/project-state.md`](docs/reference/project-state.md) for the verified current
state — which is written from live output, never from intent.

## How it works

Everything the node does for its owner runs through one chain, built one layer per phase:

```text
Telegram  →  Router  →  Executor  →  /proc, systemctl, or a model
(interface)  (one          (one job     (the thing that
             auth check)    each)        actually does it)
```

**The interface** is a Telegram bot — a systemd service running as its own account, `homelab-bot`,
which owns nothing and can log in nowhere. It uses long polling, so **the node opens no listening
socket for it**: the connection is outbound. `ss -tln` reports the same six listeners it did before
the bot existed, and `:22` is the only one reachable off-box.

**The router** holds the single authorisation check. Every privileged action in the project passes
through one `if` statement, and nothing else is allowed to decide entitlement. Executors register
themselves in a registry, so `/help` — and the command menu on your phone — are *generated* from the
code rather than maintained by hand.

**The executors** do one thing each:

| Command | What it does |
|---|---|
| `/status`, `/disk`, `/uptime` | Read `/proc` and `statvfs()`. No subprocess is ever forked |
| `/restart <service>` | Restarts **one** allowlisted service |
| `/ask <question>` | Sends the question plus the `/status` figures to a model |

### The part that is actually interesting

Two examples of the pattern this project is really about — putting a boundary somewhere it can be
*proved*, rather than somewhere it can be *asserted*.

**The bot performs a privileged action while having gained no privilege.** `/restart` works, yet
`id homelab-bot` is byte-identical to the day the account was created: no `sudo` rule, no group, no
capability. The authority lives in a polkit rule scoped to one user, one unit and one verb, evaluated
inside PID 1 — outside the process it grants. `sudo` could not be used at all, because `sudo` is
setuid and the bot runs under `NoNewPrivileges=yes`, which refuses setuid outright.

**The bot can reach a model without ever holding a credential.** The AI CLIs are authenticated to
the owner's account, `aleix`, and `homelab-bot` provably cannot read either credential file — that is
tested by attempting the read on every verification run. So the credential never moved; the *call*
did:

```text
Telegram → homelab-bot ──socket──▶ homelab-model-helper → Claude / Codex
           no credential           runs as aleix, already has them
```

Who may ask is decided by three directives in a systemd `.socket` unit — owner `aleix`, group
`homelab-bot`, mode `0660` — enforced by the kernel before the helper process exists. Note the
direction: **the bot was never added to a group; the socket was given the group the bot already
had.** A rule in a unit file cannot be bypassed by a bug in the program it protects.

### How changes reach the machine

Nothing is configured by hand and remembered. Configuration lives in the repository, is copied to
the node, and is applied by a committed script that **verifies the running system afterwards** —
because a daemon does not re-read its configuration just because you edited it.

```text
config/     the exact file that is installed on the node
services/   the code that runs there
scripts/    installers and verifiers -- guarded, and they refuse rather than guess
```

The verifiers are written to a rule this project learned the hard way: **a check that cannot
determine an answer must say `UNKNOWN`, never a plausible-looking result.** They test by *attempting*
a forbidden action rather than by reading a configuration file and reasoning about it.

## What this repository is honest about

The build log records what went wrong, in the order it happened, including mistakes that were
published before being noticed. It is not tidied up afterwards — that is deliberate, and it is
probably the most useful thing here.

A recurring example, recorded across nine instances: **a check reporting a confident result it could
not support.** A secrets scanner that reported all sixteen classes clean having searched zero of 213
blobs. A test that printed `ok ... cannot restart ssh.service` when what had actually happened was
that a password prompt went unanswered. A verifier reporting `FAIL: token does not exist` about a
file in a directory it lacked permission to traverse — while the service was authenticating with
that token.

Each one is written up with the cause and the fix in [`docs/build-log/`](docs/build-log/), and the
generalised rules live in [`scripts/README.md`](scripts/README.md).

## Start here

| If you want to… | Go to |
|---|---|
| **Understand a topic and reproduce it** | [`guide/`](guide/) — explanation-first: one directory per phase, plus `00-*` for hardware, budget and overview |
| **Know the current, verified state of the node** | [`docs/reference/project-state.md`](docs/reference/project-state.md) |
| **Understand why something is the way it is** | [`docs/decisions/`](docs/decisions/) — 25 ADRs |
| **See what went wrong and how it was fixed** | [`docs/build-log/`](docs/build-log/) |
| **See the architecture as it stands today** | [`docs/architecture/current-architecture.md`](docs/architecture/current-architecture.md) |
| **Read the actual code** | [`services/`](services/), [`scripts/`](scripts/), [`config/`](config/) |
| **See what it cost** | [`docs/reference/costs.md`](docs/reference/costs.md) — every entry, including the zeroes |

If you are reproducing the project, begin with [`guide/README.md`](guide/README.md) and work through
the phases in the order given in [`ROADMAP.md`](ROADMAP.md).

If you are contributing or using an AI coding agent, read [`PROJECT.md`](PROJECT.md) and [`AGENTS.md`](AGENTS.md) before making changes.

## License

This repository uses **two licences**, because it is mostly writing and partly code.

| What | Licence |
|---|---|
| **Documentation** — `guide/`, `docs/`, and the root Markdown files | [CC BY-SA 4.0](LICENSE-docs) |
| **Code** — `scripts/`, `config/`, `infrastructure/`, `services/`, `experiments/` | [MIT](LICENSE) |

In short: you may reuse and adapt the guide, including commercially, if you
give credit and share adaptations under the same terms. The scripts carry no
share-alike obligation. Full detail, including why the licences are split, is
in [`LICENSE-docs`](LICENSE-docs) and
[`ADR-021`](docs/decisions/ADR-021-repository-publication.md).
