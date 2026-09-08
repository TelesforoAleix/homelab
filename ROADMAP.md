# Home Lab Roadmap

The roadmap is intentionally progressive. Phase numbers should remain stable. If new work must be inserted, use a sub-phase such as `5.1-<phase-name>` rather than renumbering everything.

Multiple `00-*` guides may exist for pre-development documentation.

## Phase 00 — Pre-development and repository bootstrap

Purpose: establish project scope, hardware rationale, governance, repository structure, budget tracking, architecture baseline, and documentation standards before implementation.

Status: **In progress** — remaining hardware-verification items are folded into Phase 01 Part A,
because they must be performed before the reference node's disk is erased.

Planned/pre-development guides may include:

- `00-project-overview`
- `00-hardware-selection`
- `00-reference-build`
- `00-budget-and-costs`
- additional `00-*` topics as the project grows

## Phase 01 — Ubuntu Server

Install Ubuntu Server LTS on the reference node, establish a reproducible base installation, and verify the resulting server state.

Status: **In progress** — brief, guide, scripts and ADRs prepared; installation not yet performed.

- Brief: [`docs/handovers/01-ubuntu-server.md`](docs/handovers/01-ubuntu-server.md)
- Guide: [`guide/01-ubuntu-server/`](guide/01-ubuntu-server/README.md)
- Decisions: ADR-014 (release), ADR-015 (disk layout), ADR-016 (network link)

## Phase 02 — Linux Fundamentals

Learn and document the Linux concepts required to operate Home Lab safely: filesystem, users/groups, permissions, packages, processes/services, logs, storage basics, networking basics, shell workflow, and `tmux`/core tooling as appropriate.

## Phase 03 — Remote Access

Establish SSH keys, Tailscale, and VS Code Remote SSH so the server can run headless and be safely administered from the MacBook.

## Phase 04 — Git & GitHub Fundamentals

Use the already-bootstrapped repository to deliberately learn and formalize commits, branches, merges, pull requests, conflict handling, tags/releases, `.gitignore`, and repository hygiene.

## Phase 05 — Docker & Docker Compose

Learn containers and Compose, establish project conventions, and migrate appropriate services toward reproducible containerized deployments.

## Phase 06 — AI CLI Access

Install and validate Claude Code CLI and OpenAI Codex CLI using officially supported subscription-backed authentication where available. Document trade-offs against API usage without prematurely introducing an API architecture.

## Phase 07 — Telegram Interface

Build a minimal Telegram bot with deterministic infrastructure/status commands. Keep it unprivileged.

## Phase 08 — Router & Executors

Introduce an explicit router/executor abstraction and connect multiple model/tool executors, initially keeping routing deterministic and understandable.

## Phase 09 — Voice

Receive Telegram voice notes, transcribe them, and route the resulting text through the existing architecture. Cloud transcription may be used first.

## Phase 10 — Knowledge / Second Brain

Introduce file ingestion/indexing/retrieval while keeping source storage separate from agent intelligence. Begin with a simple RAG-style architecture before comparing more complex retrieval systems.

## Phase 11 — Agent Framework Experiments

Introduce one or more agent frameworks only after the manually built architecture is understood. Compare what abstractions they replace, what they solve, and what complexity they add.

## Phase 12 — Automation

Add scheduled or event-driven workflows where concrete use cases justify them.

## Phase 13 — Security Hardening

Deepen permissions, secrets, isolation, auditing, backups, and network controls based on the capabilities accumulated in earlier phases.

Security is still considered in every earlier phase; this phase is dedicated hardening rather than the first time security appears.

## Phase 14 — Reproducibility / Infrastructure as Code

Move toward rebuilding/replacing the M700 with minimal manual configuration using appropriate provisioning and deployment automation.

## Phase 15 — Model Gateways & Routing

Experiment intentionally with direct APIs, multiple hosted providers, unified gateways, cost/latency/quality routing, fallbacks, and observability.

## Phase 16 — Local AI / CUDA Node

If justified, add a separate NVIDIA/CUDA-capable node and experiment with local inference, quantization, serving, and potentially fine-tuning without forcing the orchestration node to become a GPU workstation.

## Roadmap rule

A later phase may be split into sub-phases when scope becomes too large. Example:

```text
10-knowledge
10.1-ingestion
10.2-vector-retrieval
10.3-hybrid-search
```

Changes that materially affect multiple phases should be returned to Project Planning and captured through ADRs where appropriate.
