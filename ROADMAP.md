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

Status: **Complete** (2026-09-09), run after Phase 03 by the owner's sequencing decision. Phase
numbers are stable by the rule below; that was a sequencing decision, not a renumbering.

- Brief: [`docs/handovers/02-linux-fundamentals.md`](docs/handovers/02-linux-fundamentals.md)
- Handover: [`docs/handovers/02-linux-fundamentals-handover.md`](docs/handovers/02-linux-fundamentals-handover.md)
- Guide: [`guide/02-linux-fundamentals/`](guide/02-linux-fundamentals/README.md)
- Standard: [`docs/standards/safe-changes-headless.md`](docs/standards/safe-changes-headless.md)
- Reference: [`docs/reference/linux-command-reference.md`](docs/reference/linux-command-reference.md)
- Decision: ADR-020 (change safety on a console-less node) — Accepted

**Delivered:** a guide taught from this machine's own files, an operator command reference, a
change-safety standard binding on every later phase, `scripts/macos/preflight.sh`, and
`scripts/server/lab-sandbox.sh` for practising the write side of users, groups, permissions and
units on disposable objects. Three diagnostic packages installed; nothing else on the node changed.

**Deliberately not taught** — later phases must not assume it: no networking changes were practised,
no `sudoers` editing, no firewalling, no backup or restore, and no LVM growth. Those were classified
read-only because the node has no console.

## Phase 03 — Remote Access

Establish SSH keys, Tailscale, and VS Code Remote SSH so the server can run headless and be safely administered from the MacBook.

Status: **Complete** (2026-09-09), brought forward ahead of Phase 02 by the owner's decision — see
the Phase 02 entry above. Key-only SSH, Tailscale, VS Code Remote SSH, and the console physically
removed. Closes Phase 01's principal open risk.

- Brief: [`docs/handovers/03-remote-access.md`](docs/handovers/03-remote-access.md)
- Handover: [`docs/handovers/03-remote-access-handover.md`](docs/handovers/03-remote-access-handover.md)
- Guide: [`guide/03-remote-access/`](guide/03-remote-access/README.md)
- Decisions: ADR-018 (SSH access policy), ADR-019 (tailnet configuration) — both Accepted

**Inherited from Phase 01:**

- ✅ **Closed** Phase 01's principal open risk: SSH accepted password authentication. It no longer
  does (ADR-018).
- **Do not cite Tailscale's Ubuntu documentation.** It still references Noble 24.04 and has no 26.04
  page; `tailscale.com/kb/1187/install-ubuntu-2604` returns HTTP 200 but serves a generic index. The
  `resolute` package repository is the authoritative source — see ADR-014.
- ✅ Superseded the unsatisfied DHCP-reservation control in ADR-016 — formally, in ADR-019.

## Phase 04 — Git & GitHub Fundamentals

Use the already-bootstrapped repository to deliberately learn and formalize commits, branches, merges, pull requests, conflict handling, tags/releases, `.gitignore`, and repository hygiene.

Status: **Complete** (2026-09-09). Brief committed before implementation per ADR-017.

**The repository was published in this phase** — `github.com/TelesforoAleix/homelab`, public, MIT for
code and CC BY-SA 4.0 for documentation (ADR-021). Until then it had no remote at all: 37 commits on
one disk with no backup. A full-history secrets audit ran before the first push and found nothing
that had to be removed.

**What this phase deliberately did not adopt**, so no later phase assumes it: no branch protection on
`main`, no commit signing, no CI or GitHub Actions, and no clone of the repository on the reference
node. Each is recorded with its reasoning in `docs/reference/git-workflow.md`.

## Phase 05 — Docker & Docker Compose

Learn containers and Compose, establish project conventions, and migrate appropriate services toward reproducible containerized deployments.

Status: **Complete** (2026-09-09). Docker Engine 29.8.0, Compose v5.5.1, and
containerd 2.3.5 installed from Docker's official apt repository. No persistent
containers are left running.

- Brief: [`docs/handovers/05-docker.md`](docs/handovers/05-docker.md)
- Handover: [`docs/handovers/05-docker-handover.md`](docs/handovers/05-docker-handover.md)
- Guide: [`guide/05-docker/`](guide/05-docker/README.md)
- Reference: [`docs/reference/docker-reference.md`](docs/reference/docker-reference.md)
- Decision: ADR-022 (Docker runtime and container conventions) — Accepted

**Inherited forward:** every published port names an explicit interface; `-p
8080:80` is forbidden because Docker DNAT happens before host firewall `INPUT`
rules. `aleix` is in the `docker` group, which is root-equivalent and must never
be granted to service accounts. Phase 13 must account for Docker's firewall
interaction, rootful/user-namespace trade-off, and latent IPv6 forwarding
asymmetry.

## Phase 06 — AI CLI Access

Install and validate Claude Code CLI and OpenAI Codex CLI using officially supported subscription-backed authentication where available. Document trade-offs against API usage without prematurely introducing an API architecture.

Status: **Complete** (2026-09-09). Claude Code `2.1.236` stable and Codex CLI `0.153.4` are installed
as native, user-scoped interactive tools on the reference node. Claude uses Claude Pro subscription
OAuth; Codex uses Sign in with ChatGPT. No API key, usage-billed fallback, Node.js runtime, daemon,
listener, or persistent container was introduced.

- Brief: [`docs/handovers/06-ai-cli-access.md`](docs/handovers/06-ai-cli-access.md)
- Handover: [`docs/handovers/06-ai-cli-access-handover.md`](docs/handovers/06-ai-cli-access-handover.md)
- Guide: [`guide/06-ai-cli-access/`](guide/06-ai-cli-access/README.md)
- Reference: [`docs/reference/ai-cli-reference.md`](docs/reference/ai-cli-reference.md)
- Decision implemented: ADR-008 (subscription-backed AI CLI access first)

**Inherited forward:** these credentials belong to the human administrator and live in
`/home/aleix`; they are not a service identity. Phase 07 must not give its Telegram account access
to them or the Docker group. Phase 08 must decide explicitly whether personal subscription-backed
CLIs are supportable for unattended execution. Subscription windows are finite and cannot be
treated as an availability SLA.

## Phase 07 — Telegram Interface

Build a minimal Telegram bot with deterministic infrastructure/status commands. Keep it unprivileged.

Status: **Complete** (2026-09-09). Brief committed before implementation per ADR-017.

Delivered as a **native systemd service** (not a container), running as a dedicated account in no
privileged group, scoring **1.3 OK** on `systemd-analyze security`. **Long polling, so it opens no
listening socket** — which is what makes a network service acceptable on a node with no firewall.
Standard library only; the bot never forks a process. Isolation proved by attempted access (ADR-023).

**Deliberately read-only, with no escalation built.** Phase 08 owns the executor pattern; widening
the service account is its decision to make, not to inherit. Moving to webhooks would change the
exposure model completely and needs its own ADR.

## Phase 08 — Router & Executors

Introduce an explicit router/executor abstraction and connect multiple model/tool executors, initially keeping routing deterministic and understandable.

Status: **Complete** (2026-09-09). Brief committed before implementation per ADR-017.

Delivered as a **registry-based router** inside the bot process, with six executors at three
capability levels and **two allowlists** — authentication (may you use the bot) and authorisation
(may you invoke this executor), the second enforced as a subset at startup.

**One privileged action, and the service account gained nothing.** `/restart` is scoped by a polkit
rule to one user, one unit and one verb, plus a second allowlist inside the bot; `id homelab-bot` is
byte-identical to Phase 07 and there are zero sudoers entries. polkit rather than sudo because the
unit sets `NoNewPrivileges=yes`, which refuses setuid outright — and because a malformed polkit rule
denies where a malformed sudoers file breaks `sudo` on a console-less node (ADR-024).

**The model executor is registered and deliberately not connected.** ADR-008 authorises
subscription-backed *interactive* access and is silent on unattended use. **Phase 09 must resolve
that on its merits and record it as an ADR** — not by copying a personal OAuth credential to a
service account.

## Phase 09 — Model Executor (subscription-backed)

Status: **Complete** (2026-09-09). Brief committed before implementation per ADR-017 (`351f825`).

Connect the model executor that Phase 08 registered and deliberately left inert, so the bot can
answer open questions rather than only fixed ones.

**How it was connected is the result worth remembering.** `homelab-bot` provably cannot read either
AI credential, so the call moved into a separate service running as `aleix` that the bot asks over a
UNIX socket. The credential never moved. `id homelab-bot` is byte-identical and `ss -tln` still
reports six listeners — a UNIX socket is a file, not a port (ADR-025).

- ✅ Two providers with **independent** usage limits and automatic fallback. Not a demonstration:
  Claude was exhausted when the first live `/ask` ran, and Codex answered it. Wiring both was the
  owner's decision, against the assistant's recommendation, and the owner was right.
- ✅ Cheapest model by default — `haiku`, `gpt-5.6-luna`.
- ✅ The model gets **no tools**, verified with a canary file rather than assumed, and its output is
  never dispatched — proved by asking the model to emit `/restart ssh.service`, which it did, with
  no effect.
- ✅ Only the question and the five `/status` figures leave the machine. Logs are excluded because
  anything able to write a log line could otherwise choose what gets sent.
- ⚠️ **The licensing question is still open.** ADR-008 covers interactive use only. Phase 09
  connected the model under a constraint rather than an answer: **owner-initiated calls only.**
  **Phase 12 must not make unattended calls without a new ADR.**
- ⚠️ Fixed a Phase 07 defect found here: `StartLimitIntervalSec` sat in `[Service]`, where systemd
  ignores it, leaving the bot's restart limit **unreachable** for two phases.

**Amended 2026-09-09.** This slot was "Voice". The owner's reasoning, recorded rather than applied
silently: **voice on top of six deterministic commands is a slower way to type `/status`.**
Speech-to-text only becomes worth having once there is something worth saying, which means a model
executor comes first. **Voice moves to Phase 17** and arrives into an interface that can answer.

Numbers stay stable; running order is flexible — the same convention under which Phase 03 ran before
Phase 02.

## Phase 10 — Knowledge / Second Brain

Introduce file ingestion/indexing/retrieval while keeping source storage separate from agent intelligence. Begin with a simple RAG-style architecture before comparing more complex retrieval systems.

**Amended 2026-09-10.** The knowledge base has already recorded its own retrieval architecture
decision, independently of this project, and this phase should **adopt it rather than re-derive
it**: Markdown stays the source of truth, every graph, vector index or summary is a rebuildable
derived view, and the progression runs structured index → hybrid retrieval → lightweight graph →
selective community summaries → full GraphRAG. That last step is gated by the knowledge base's own
rule — **only once a known-answer eval set exists** and simpler retrieval has repeatedly failed on
real questions.

First slice is expected to be retrieval **with no model call at all**, so nothing new leaves the
machine and ADR-025 §8 is untouched; widening `/ask` with retrieved context is a separate decision
with its own ADR.

**ADR-030 — the Knowledge Contract** is written in this phase, not before it: specifying how an
agent queries the knowledge base before retrieval exists would be guessing. It implements ADR-010 as
a queryable interface returning provenance, never raw filesystem access.

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

**Inherited from Phase 03 — must be addressed, not inherited silently:**

- **A backup SSH key or recovery path.** Phase 03 removed the console and left a single Ed25519 key
  as the only way in. Losing it means losing access to a machine with no monitor attached. This is
  debt Phase 03 created and did not close.
- **Node key expiry is deliberately disabled** on the server (ADR-019). A real security control was
  switched off for availability, because a lapsed key silently removes a console-less node from the
  tailnet. Revisit on its merits.
- **Tailscale SSH was declined** (ADR-019), keeping OpenSSH keys as the authentication mechanism.
  Worth re-evaluating here with ACLs in scope.
- **Firewall (UFW) and `fail2ban`** were both explicitly deferred from Phase 03 to here.

## Phase 14 — Reproducibility / Infrastructure as Code

Move toward rebuilding/replacing the M700 with minimal manual configuration using appropriate provisioning and deployment automation.

## Phase 15 — Model Gateways & Routing

Experiment intentionally with direct APIs, multiple hosted providers, unified gateways, cost/latency/quality routing, fallbacks, and observability.

**Amended 2026-09-10 — promoted, and it has already accidentally started.**
`services/model-helper/providers.py` is already a two-provider router with independent per-provider
limits and fallback proved against a genuinely exhausted provider. What does not exist is models as
*configuration* rather than two entries hardcoded in Python.

ADR-026 makes this phase load-bearing rather than exploratory: it is where the model registry, the
`unattended` eligibility field, and task-class routing are built. **A sub-phase 15.0 can run before
a metered provider is chosen**, generalising the existing router with the two subscription CLIs as
its first two entries. That proves the structure at no cost and makes adding a paid provider a
configuration change rather than a rewrite.

The refusal path must be proved with a fixture provider set to `unattended: false`, against a
positive control. An eligibility check that has only ever permitted is unvalidated.

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

## Phase 17 — Voice

Receive Telegram voice notes, transcribe them, and route the resulting text through the existing
architecture. Cloud transcription may be used first.

**Moved here from Phase 09 on 2026-09-09**, before any work was done on it. Voice is a modality on
top of the interface, not the interface itself: it becomes worth having once there is a model
executor to talk to. Running order is expected to be after the foundations work (backup and the
ADR-015 encryption decision), because voice notes and transcripts are the first data on this node
that would be painful to lose or to have read.

## Phase 18 — Foundations

Give the node a recovery story before it holds anything expensive to lose.

**Added 2026-09-10.** A new number rather than a renumbering, per the roadmap rule above. It carries
the work the Phase 09 handover addressed to "the foundations phase", plus the debts Phase 03
created and Phase 13 inherited but which cannot wait for a full hardening phase.

Scope:

- **A backup of the node.** It currently has none of any kind. Phase 04 gave the *repository* an
  offsite copy; it did nothing for the machine. Verified by **restoring**, not by a backup job
  reporting success.
- **The ADR-015 encryption decision**, made deliberately and made *now*. The root filesystem is
  unencrypted, accepted on the premise that the node held nothing sensitive. Phase 10 ends that
  premise, and converting an unencrypted root filesystem afterwards generally means a reinstall.
  This is the phase that decides, whichever way it decides.
- **A second SSH recovery path.** Phase 03 removed the console and left a single Ed25519 key as the
  only way into the machine. Losing it means losing a computer with no monitor attached.
- **`eno1` is present and unused.** Wi-Fi is a single point of failure for *both* access routes, and
  the node has demonstrated it can go dark. Worth resolving here rather than at Phase 13.

Phase 13 remains the dedicated hardening phase — firewall, `fail2ban`, Tailscale ACLs, node-key
expiry, rootless Docker. Phase 18 is narrower: it is about **recoverability**, not defence.

## Repository split (not a numbered phase)

Per ADR-029, the knowledge base splits into `factory` (public), a product repository (private) and `brain`
(private). This is repository work rather than node work, so it carries no phase number and can run
alongside Phase 18. It should not begin until ADR-027, ADR-028 and ADR-029 are settled, so each
piece lands in its permanent home with its contract already defined.

The split must be done with git operations, never by copying directories: the working tree holds
several gigabytes of gitignored video and `node_modules`, against roughly 20 MB of tracked content.

### Done on the laptop, 2026-09-10 (ADR-030)

**The split is complete on the development machine and on GitHub.** It was done with
`git-filter-repo`, not by copying, and each extraction was verified byte-identical against the
source before anything was deleted.

| Layer | Repository | State |
|---|---|---|
| Infrastructure | `homelab` | public, unchanged |
| Execution | `factory` | public; the duplicate copy in the knowledge base is gone |
| Projects | `projects/oncla`, `projects/factory` | **new**, both private |
| Knowledge | `brain` | private; 896 tracked files → 497 |

ADR-030 adds the `projects/` layer and closes ADR-029 §6 — every project carries its own `ops/`.

**Nothing was cloned onto the node.** That half is still gated by Phase 18, for the reason the
migration plan gave: cloning private repositories onto an unencrypted root filesystem with no
backup is exactly the event ADR-015 exists to be revisited before.
