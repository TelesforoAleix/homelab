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

**Phases 00–03 complete. Phase 04 — Git & GitHub Fundamentals in progress.**

| Phase | State |
|---|---|
| 00 — Repository bootstrap & planning | ✅ Complete |
| 01 — Ubuntu Server on the reference node | ✅ Complete |
| 03 — Remote access (SSH keys, Tailscale, VS Code) | ✅ Complete — run ahead of 02 by choice |
| 02 — Linux fundamentals | ✅ Complete |
| 04 — Git & GitHub fundamentals | 🔄 In progress |

The reference node runs Ubuntu Server 26.04.1 LTS, is administered entirely
remotely over Tailscale with key-only SSH, and has **no monitor or keyboard
attached**. See [`ROADMAP.md`](ROADMAP.md) for what comes next and
[`docs/reference/project-state.md`](docs/reference/project-state.md) for the
verified current state.

## Start here

If you are reproducing the project, begin with [`guide/README.md`](guide/README.md).

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
