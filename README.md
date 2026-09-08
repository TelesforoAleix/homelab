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

**Phase 00 — Repository Bootstrap / Pre-development planning**

The repository structure and project governance are being established before Ubuntu Server installation begins.

## Start here

If you are reproducing the project, begin with [`guide/README.md`](guide/README.md).

If you are contributing or using an AI coding agent, read [`PROJECT.md`](PROJECT.md) and [`AGENTS.md`](AGENTS.md) before making changes.

## License

A public repository license has **not yet been selected**. Do not assume reuse rights until a license is explicitly added.
