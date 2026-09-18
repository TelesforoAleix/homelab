# Home Lab

> [!IMPORTANT]
> **Version 1 closed on 2026-09-18.** This repository is preserved publicly as a historical,
> educational and reproducible reference; it is no longer under active development. The completed
> system, guides, decisions and failures remain useful, while future roadmap items and the target
> architecture were not all implemented. Version two is being developed as a separate project; a
> link will be added when it has a stable public location. Start with the
> [closure handover](docs/handovers/project-closure.md).

**Home Lab** is a learning-first, self-hosted AI systems laboratory built on inexpensive hardware.

The project explores how interfaces, agents, model providers, tool execution, knowledge retrieval, automation, infrastructure, security, and eventually local AI fit together. The goal is not to rush toward a single finished assistant. The goal is to understand the layers by building them progressively, replacing components intentionally, and documenting the trade-offs.

## Reference build

The canonical implementation uses a **Lenovo ThinkCentre M700 Tiny** as an always-on orchestration and infrastructure node.

Current known hardware:

- Intel Core i5-6600T — 4 cores / 4 threads
- 32 GB DDR4 RAM (2 × 16 GB; upgraded from 8 GB on 2026-09-14)
- 256 GB SSD
- Wi-Fi
- Bluetooth
- Purchase price: **700 DKK used**

This machine is intentionally **not** a local-LLM workstation. Version one used hosted AI models;
a separate NVIDIA/CUDA inference node was considered but not added.

## Who this project is for

This repository is aimed at people with a business and some technical background who are comfortable with computers and light programming, but who are not necessarily experienced Linux or systems engineers. It is intended for people who want to learn by building their own AI lab, automation environment, or personal knowledge system.

## Documentation model

- [`guide/`](guide/) — explanation-first material for people reproducing and learning from the project.
- [`docs/`](docs/) — concise operational truth about the reference implementation: architecture, decisions, build history, costs, state, and handovers.
- [`PROJECT.md`](PROJECT.md) — the historical working contract used to govern version one.
- [`ROADMAP.md`](ROADMAP.md) — completed phases and unfinished historical plans.

## Project philosophy

1. Build simple layers before adopting large frameworks.
2. Understand important AI-generated code and configuration before calling it complete.
3. Document decisions, including mistakes and reversals.
4. Prefer reproducible configuration over undocumented manual state.
5. Keep the system model-agnostic.
6. Treat security as part of the learning objective.
7. Keep `main` in a known-working state.
8. Optimize the reference build for affordability and learning, not maximum compute.

## Final version-one status

Version one closed with a real reference system running on the node. It includes the Linux and
remote-administration foundation, Docker conventions, a Telegram control surface, credential-
isolated model access, multiple configured providers, fail-closed spend controls, encrypted project
storage, backup and recovery evidence, monitoring and notifications, security hardening, Factory
Workbench, and a loopback Home Lab harness endpoint.

The project stopped before the accepted Run-centered target architecture was implemented. In
particular, v1 does **not** contain durable Home Lab Runs, general decomposition and planning,
context assembly, capability-based service routing or governed generic tool dispatch. Phase 23.1
was not delivered.

A final read-only architecture and overengineering review did **not** find that the delivered v1
system was needlessly rebuilding an agent framework. Its credential isolation, provider registry,
fail-closed spend controls, systemd boundaries, encrypted storage and local policy enforcement solve
Home Lab-specific platform problems. The review found the larger reinvention risk in the unbuilt
roadmap—generic workflow graphs, tool protocols and retrieval machinery—and identified the weight of
the documentation/governance process itself as the cost already being paid. Closing v1 preserves
the useful platform work without committing version two to that future complexity.

Use these documents to distinguish fact from intent:

| Question | Source |
|---|---|
| What did v1 achieve and why did it close? | [`docs/handovers/project-closure.md`](docs/handovers/project-closure.md) |
| What was actually delivered? | [`docs/architecture/current-architecture.md`](docs/architecture/current-architecture.md) |
| What was planned but unfinished? | [`docs/architecture/target-architecture.md`](docs/architecture/target-architecture.md) and the historical [`ROADMAP.md`](ROADMAP.md) |
| What was observed on the reference node? | [`docs/reference/project-state.md`](docs/reference/project-state.md) |
| Why was the project closed? | [`ADR-052`](docs/decisions/ADR-052-close-version-one-and-preserve-the-repository.md) |

## How it works

Version one ended with two principal request paths, built progressively across the phases:

```text
Factory Workbench → loopback harness endpoint → model-helper → configured provider
Telegram bot --------------------------------→ model-helper → configured provider
```

The harness is a synchronous v1 compatibility endpoint, not the Run-centered orchestrator described
by the unfinished target architecture. Telegram remains a separate direct client of the model
helper.

**The Telegram interface** is a systemd service running as its own account, `homelab-bot`,
which owns nothing and can log in nowhere. It uses long polling, so **the node opens no listening
socket for it**: the connection is outbound. The Workbench and harness listeners bind to loopback;
remote administration uses the Tailscale path.

**The Telegram router** holds its authorization check. Every privileged Telegram action passes
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
`homelab-model`, mode `0660` — enforced by the kernel before the helper process exists. The bot and
harness are the two allowed socket consumers. A rule in a unit file cannot be bypassed by a bug in
the program it protects.

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
| **Understand why something is the way it is** | [`docs/decisions/`](docs/decisions/) — the complete ADR history |
| **See what went wrong and how it was fixed** | [`docs/build-log/`](docs/build-log/) |
| **See the architecture as it stands today** | [`docs/architecture/current-architecture.md`](docs/architecture/current-architecture.md) |
| **Read the actual code** | [`services/`](services/), [`scripts/`](scripts/), [`config/`](config/) |
| **See what it cost** | [`docs/reference/costs.md`](docs/reference/costs.md) — every entry, including the zeroes |

If you are reproducing parts of version one, begin with [`guide/README.md`](guide/README.md), then
use completed phase handovers to identify what was actually validated. `ROADMAP.md` is preserved as
historical planning and must not be read as an active sequence.

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
