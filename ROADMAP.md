# Home Lab Roadmap

The roadmap is intentionally progressive. Phase numbers should remain stable. If new work must be inserted, use a sub-phase such as `5.1-<phase-name>` rather than renumbering everything.

Multiple `00-*` guides may exist for pre-development documentation.

## Phase 00 — Pre-development and repository bootstrap

Purpose: establish project scope, hardware rationale, governance, repository structure, budget tracking, architecture baseline, and documentation standards before implementation.

Status: **Complete** (2026-09-08). Documentation and governance were finished at bootstrap; the
remaining hardware-verification checks were executed as **Phase 01 Part A**, as ratified by Project
Planning (amendment 2). No separate hardware implementation phase was required.

Closure condition: when the Part A checklist in
[`guide/01-ubuntu-server/`](guide/01-ubuntu-server/README.md) is recorded in
`docs/reference/hardware.md`, the Phase 00 prerequisite is **satisfied** and this phase closes.
(Ratified by Project Planning, 2026-09-08, amendment 2.)

**Closed 2026-09-08.** Part A resolved the RAM layout (1 × 8 GB, one slot free) and the wireless
adapter (Intel Wireless-AC 8260), confirmed storage and CPU, and validated USB ports, video output
and fan noise. All recorded in `docs/reference/hardware.md`.

Planned/pre-development guides may include:

- `00-project-overview`
- `00-hardware-selection`
- `00-reference-build`
- `00-budget-and-costs`
- additional `00-*` topics as the project grows

## Phase 01 — Ubuntu Server

Install Ubuntu Server LTS on the reference node, establish a reproducible base installation, and verify the resulting server state.

Status: **Complete** (2026-09-08). Ubuntu Server 26.04.1 LTS installed and validated, including the
unattended AC power-loss recovery test. Handover returned to Project Planning.

Absorbs the remaining Phase 00 hardware validation as Part A.

- Brief: [`docs/handovers/01-ubuntu-server.md`](docs/handovers/01-ubuntu-server.md) (Ratified)
- Guide: [`guide/01-ubuntu-server/`](guide/01-ubuntu-server/README.md)
- Decisions: ADR-014 (release), ADR-015 (disk layout), ADR-016 (network link) — all Accepted

## Phase 02 — Linux Fundamentals

Learn and document the Linux concepts required to operate Home Lab safely: filesystem, users/groups, permissions, packages, processes/services, logs, storage basics, networking basics, shell workflow, and `tmux`/core tooling as appropriate.

Status: **Deferred, not skipped.** The owner chose on 2026-09-09 to run Phase 03 first, so that
Phase 01's principal open risk — SSH password authentication — is closed before a long
documentation-heavy phase, and so that Phase 02 is carried out over key-based remote access rather
than password login with a monitor attached. Phase numbers are stable by the rule below; this is a
sequencing decision, not a renumbering.

**Inherited from Phase 01:** the handover's "ground already covered" table lists LVM, permissions and
ownership, systemd units, apt, netplan and `journalctl` as topics already exercised in anger. Build
on them as worked examples rather than teaching them from zero. Phase 03 adds more of the same —
see its handover.

## Phase 03 — Remote Access

Establish SSH keys, Tailscale, and VS Code Remote SSH so the server can run headless and be safely administered from the MacBook.

Status: **In progress** (started 2026-09-09), brought forward ahead of Phase 02 by the owner's
decision — see the Phase 02 entry above.

- Brief: [`docs/handovers/03-remote-access.md`](docs/handovers/03-remote-access.md)

**Inherited from Phase 01:**

- Closes Phase 01's principal open risk: **SSH currently accepts password authentication.**
- **Do not cite Tailscale's Ubuntu documentation.** It still references Noble 24.04 and has no 26.04
  page; `tailscale.com/kb/1187/install-ubuntu-2604` returns HTTP 200 but serves a generic index. The
  `resolute` package repository is the authoritative source — see ADR-014.
- Supersedes the unsatisfied DHCP-reservation control in ADR-016: Tailscale gives the node a stable
  identity independent of its LAN address.

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

**Inherited from Phase 01 — must be addressed, not inherited silently:**

**ADR-015 must be explicitly revisited before this phase stores real data.** The reference node has
no encryption at rest, accepted on the premise that it holds nothing sensitive. A Second Brain breaks
that premise. Converting an unencrypted root filesystem afterwards generally means a reinstall, so
the decision belongs at the start of this phase, not the end.

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

Changes that materially affect multiple phases are **captured as ADRs and carried into the next
phase's brief** (ADR-017). There is no separate planning context to return them to; the phase that
discovers the change is the phase that records it.
