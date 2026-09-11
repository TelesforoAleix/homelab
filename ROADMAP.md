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

**The Knowledge Contract ADR** is written in this phase, not before it: specifying how an agent
queries the knowledge base before retrieval exists would be guessing. It implements ADR-010 as a
queryable interface returning provenance, never raw filesystem access.

**Corrected 2026-09-10 (ADR-031).** This paragraph previously reserved the number ADR-030 for that
contract. ADR-030 was subsequently used for the four-layer workspace, so the reservation was wrong.
No number is reserved here: the Knowledge Contract takes the next free number on the day it is
written.

**Phase 21 is now coupled to this phase (ADR-031 §6, as amended 2026-09-10).** The new public `brain`
is designed and built **together with** the ingestion pipeline and the RAG system decided here, not
before them, so that content migrates into a structure that has actually been designed. Until then
the existing private `brain` stays as it is, under its current name.

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

**Amended 2026-09-11, on ADR-034 §5.** The registry, the `unattended` field, the caps, the fallback
and *"callers never name a model"* are all retained. What changes is the **router's input**, because
ADR-034 removed `model_policy` from agents entirely. The statement this replaces is preserved:

> ~~it is where the model registry, the `unattended` eligibility field, and **task-class routing**
> are built.~~

The router instead receives the **agent role**, a **bounded task summary** rather than the full
private task, **validated task metadata**, and capability/context characteristics. The role *is* the
declaration of need, so **ADR-026 §4 is unchanged** — only its form is.

**Priority, severity and complexity are hints, never selectors.** They cannot reach a model tier on
their own and cannot bypass the pre-call budget check (ADR-033). An agent's claim about its own work
is data, not an instruction; without this rule an agent routes itself to an expensive model by
asserting that its task is hard.

**Routing starts deterministic and keeps deterministic routing as the fallback.** The AI-assisted
router is the *target*, and Phase 15.0 must not pretend to complete it. The
[Phase 15.0 brief](docs/handovers/15.0-model-registry.md) predates this amendment and inherits it.

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

Status: **Complete** (2026-09-11). All five functional objectives met: a tested console as the
second way in, a backup, a restore proved against a planted positive control, **ADR-032**
reaffirming ADR-015 with an explicit content gate, and `eno1` resolved as permanently down.

**Carried to Phase 21 and Phase 10 as a hard precondition:** until encryption is revisited and
executed, the node may not hold the knowledge base, any project repository, or any private
repository (ADR-032 §2).

- Handover: [`docs/handovers/18-foundations-handover.md`](docs/handovers/18-foundations-handover.md)
- Guide: [`guide/18-foundations/`](guide/18-foundations/README.md)
- Decisions: ADR-032 (new); ADR-015 reaffirmed; ADR-016 resolved

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

## Phase 19 — Tool Vocabulary & Capability Levels

Publish homelab's **named tool vocabulary and its capability levels** as a stable public interface,
so a Factory manifest has something real to compose against.

**Added 2026-09-10 (ADR-031).** New numbers rather than a renumbering, per the roadmap rule above and
the Phase 18 precedent.

ADR-027 §3 already places the vocabulary in homelab, because homelab is what enforces it, and ADR-027
§5 makes an unknown tool name a **hard load failure** rather than a warning. Together those make this
phase the prerequisite for Phase 20 and Phase 22: a manifest written before the vocabulary exists
either names tools that cannot load, or invents a vocabulary in the wrong repository.

ADR-027's own validation list applies here — each item proved against a positive control, not
observed to pass. **An authorisation check that has only ever permitted is unvalidated.**

**Superseded and deferred, 2026-09-11.** The brief's design was rejected before implementation —
see [`docs/handovers/19-tool-vocabulary-design-review-outcome.md`](docs/handovers/19-tool-vocabulary-design-review-outcome.md).
Factory agents declare **portable capabilities**; Homelab maps them to concrete tools. A manifest
naming Homelab tools could not load without Homelab, which contradicted ADR-031 §4.

**This phase is no longer a prerequisite for anything.** The statement it replaces is preserved
here as history rather than deleted (`PROJECT.md` §11):

> ~~**Prerequisite for:** Phase 20, and through it Phase 22.~~

**Tools are now designed only when concrete operational needs appear.** This phase resumes after
real Factory workflows and the Homelab foundations produce those needs, and a **fresh brief must be
written and committed first**.

**Restated 2026-09-11, after ADR-034 and ADR-035.** The successor ADRs are now written and accepted,
and they settle what this phase becomes. **ADR-034 §2** replaces the premise: Factory declares
portable capabilities, homelab owns concrete tools and the approved capability-to-tool mappings, and
homelab **publishes no concrete tool until it implements one for a real need**. **ADR-035 §8** voids
ADR-031 §7's prerequisite outright.

**The dependency inverts.** This phase no longer precedes Phase 20 — it follows the capability gaps
that Phase 20.0 and Phase 23 actually observe. Publishing a vocabulary before a consumer existed to
shape it is the failure this phase already demonstrated once, and the two tool names that could not
run on the node (`read_repo`, `post_review`) came from ADR-027's own *example* manifest rather than
from any workflow.

When it resumes, its fresh brief defines concrete homelab tools and their mappings under ADR-034 §7's
independent **effect / minimum approval / availability / target scope** properties — not the scalar
`READ`/`PRIVILEGED` level — plus capability advertisement, the pre-activation compatibility check
(ADR-034 §6), and planted refusal controls against **real** consumers.

- Brief: [`docs/handovers/19-tool-vocabulary.md`](docs/handovers/19-tool-vocabulary.md) — committed
  before implementation per ADR-017. Proposes a **five-name** vocabulary (`read_host_status`,
  `ask_model`, `restart_service`, `read_repo`, `post_review`), keeps ADR-025's two locks shut, and
  specifies the planted positive control that proves the refusal actually fires.

## Phase 20 — Factory Rewrite

Rewrite The Factory: **keep the content, discard the markdown-heavy format** (ADR-031 §7). The format
was designed for a different environment than the one Factory now has to run in.

**Nothing is to be written into the current format** in the meantime.

**No longer depends on Phase 19, as of 2026-09-11.** Phase 19 was superseded before implementation
and publishes no tool vocabulary. The statement this replaces is preserved as history:

> ~~**Depends on Phase 19.** The rewrite composes against homelab's published tool vocabulary;
> starting before it exists is the failure ADR-031 §7 names.~~

**Scope rewritten 2026-09-11, on ADR-035.** The successor ADRs are now written, so the provisional
note this replaces is discharged. It is preserved as history rather than deleted:

> ~~**Scope is being rewritten** around the minimal Factory Workbench and a synthetic, resettable
> end-to-end acceptance project, rather than the wholesale conversion of all Factory content. The
> successor ADRs are not yet written, so this entry is provisional.~~

**The work splits in two**, because the review found that a minimal executable slice and a wholesale
content conversion are different jobs with different prerequisites. Per the roadmap's sub-phase rule,
the first half becomes **Phase 20.0** below rather than a renumbering.

| | Phase 20.0 | Phase 20 |
|---|---|---|
| Deliverable | Minimal Factory Workbench + the synthetic acceptance project | Intensive Workbench development + full catalogue/content migration |
| Prerequisite | ADR-034, ADR-035 — **both accepted, so this is unblocked now** | Phase 23, the homelab AI foundation |
| Proves | That Factory stands alone (ADR-031 §4) | That Factory's content survives the format change (ADR-031 §7) |

**Phase 20 proper is the larger half and it now runs late**, after the homelab AI foundation exists.
Converting ten thousand lines of prose into a loadable operating model before the harness that
consumes it is built would shape the conversion around a guess.

**Also in scope: retiring Factory's parallel plan.** Everything is managed through one internal
system — homelab. One `ROADMAP.md`, one progress record. Factory's own `roadmap.md` V0–V4 series and
the **Locked Decisions** in its `progress.md` are **superseded** (ADR-031 §9, as amended 2026-09-10),
and folding them in belongs here: this is the phase already reading Factory's content end to end, so
deciding per item what survives into homelab's plan and what was already dead costs one pass rather
than two.

**Amended 2026-09-10.** When this phase was added earlier the same day it said Factory's `roadmap.md`
stayed in Factory as Factory's own plan, on the first draft of ADR-031 §9. That is no longer the
plan; the amendment to §9 replaced it. The earlier statement is recorded here rather than removed.

What Factory still ships is the **method, the contracts and the definitions** — never this project's
roadmap. An adopter takes those and writes their own plan (ADR-031 §4).

## Phase 20.0 — Minimal Factory Workbench

Build the **minimum Factory Workbench** and the **public synthetic acceptance project** that proves
it, per ADR-035. A sub-phase under the roadmap's rule above, not a renumbering.

**Added 2026-09-11.** Unblocked now: its only prerequisites are ADR-034 and ADR-035, both accepted.

Workbench opens a project by being pointed at its root or `ops/`, creates a new project and its
minimum valid `ops/` structure, manages tasks, inbox, team, reviews, workflow state and approvals,
validates and writes the project's records, and invokes AI through a configured adapter. It holds
**no homelab credential, no model registry and no tool implementation** (ADR-035 §2) — that line is
where ADR-031 §1's reason survives, and it is the one thing this phase may not compromise on.

**The synthetic project is one artifact doing five jobs**: the standalone quickstart, the end-to-end
acceptance test, the development fixture, the learning example, and the environment where refusals
are planted and proved. Its fourteen accepted steps are enumerated in the brief's §4.1.

**Only the deterministic fake adapter is fixed.** Which real adapter ships first is deliberately open
(ADR-035 §4). The fake comes first regardless, because an acceptance test that needs a live model is
not repeatable.

**This is the phase that discharges ADR-031 §4's outstanding criterion** — *"each public repository
needs a standalone quickstart. None currently has one."* The proof is the synthetic project running
end to end **with no homelab installed**.

Refusals to plant and prove, each against a positive control: an unapproved agent addition, an
unsupported backend capability, an approval-gated action waiting in the inbox, exhausted review
rounds, an exhausted budget, and an agent exceeding project or context scope. Plus the two structural
ones: **no direct agent write to `main`**, and **no merge whose human approval is not bound to the
exact reviewed revision**.

- Brief: [`docs/handovers/20.0-minimal-factory-workbench.md`](docs/handovers/20.0-minimal-factory-workbench.md)
  — committed before implementation per ADR-017, 2026-09-11.

**Its §6.1 is the decision that shapes the phase.** Reading Factory at `97ccb86` found the read half
already built — an 864-line **read-only** `dashboard/` that loads a project's `ops/` folder — and
found that a browser page cannot create a worktree, commit, run tests or open a pull request.

**Amended 2026-09-11**, the same day, on the owner's correction. Factory's own `roadmap.md` already
specifies the writable control plane (**V3**) and the CLI bridge (**V2**), and its V1.5 exit
criterion already named *"the CLI/server/webview bridge decision"*. The brief resolves that existing
decision rather than posing a new one, and **CLI-first — keeping the dashboard as a file exactly as
it is — is a first-class option** that the first draft underweighted. What exists in `factory` is an
**MVP, not a constraint**: reuse what works, rethink what does not. ADR-031 §9 superseded the
V-series as a *plan*; ADR-031 §7 keeps the design content, which is input here.

## Phase 21 — Brain Rename & Method Extraction

Rename the private `brain` repository to **`aleix-brain`**, where it becomes an archive, and extract
its ~32 method files with `git-filter-repo` into a **new public `brain`** (ADR-031 §5, §6).

**Deferred as a whole operation on 2026-09-10 (ADR-031 §6, as amended), the same day this phase was
added.** The number stays and the phase is not renumbered, per the roadmap rule above; what changed
is its sequencing, and the earlier statement of it is left in place rather than rewritten:

- When this phase was first written it was **independent of Phases 19, 20 and 22 and could run in any
  order relative to them**, with only *when content migrates* deferred.
- It is now **coupled to the knowledge work**: the new public `brain` is designed and built
  **together with the new ingestion pipeline and the RAG system** — Phase 10 and its sub-phases —
  not before them. The rename, the extraction and the content migration are one operation and it runs
  at that point.
- **The end state is unchanged** (ADR-031 §5). Only the timing changed. The reason: building the
  public repository first shapes it around the current layout, and the ingestion design then either
  accepts a structure chosen for it or reshapes a repository that already has history.

**Until this phase runs, the private `brain` stays as it is, under its current name, in active use.**
No rename, no extraction, no content migration in the meantime.

`aleix-brain`'s history is **not** rewritten and its visibility does **not** change. Extraction is
done with git operations, never by copying — the ADR-029 and ADR-030 §5 precedent.

**Accepted, not overlooked:** content written into the new `brain` after the switch has no version
history, mitigated only by `aleix-brain` retaining everything up to the switch.

**The rename hazard this phase carries, stated here because a deferred plan is a plan nobody is
reading.** Renaming leaves a GitHub redirect at the old name, and that redirect **dies the moment a
new repository claims the old name under the same owner** — after which a stale clone whose `origin`
still points at `.../brain.git` is aimed at the **public** repository, and one `git push` publishes
the private notes, with no undo. The hazard is **dormant only while nothing claims the old name**,
which is exactly what the deferral preserves and exactly what this phase ends. The preparation for
it — the rename/extract procedure and its mitigations — is the extraction plan of 2026-09-10 in
`projects/factory` (private), which remains valid and is where this phase starts.

**Gated the same way as the rest of the split:** the ADR-029 §5 boundary gate must be validated
against planted content before the new public repository is pushed, and nothing is cloned onto the
node until Phase 18 has decided ADR-015.

**Not part of the new public repository:** the restored `idea-logger`, `session-archiver`,
`task-tracker` and orchestrator-README files in `brain/.github/skills/`. They describe processes that
predate the new design and are replaced by it, so they are superseded legacy rather than method;
they stay private, and whether they are discarded or reprocessed is this phase's design work to
decide (ADR-031 §6.1).

## Phase 22 — Homelab Administration Dashboard

Build the **homelab administration dashboard**: models, providers, costs, tools, runtime health, and
the homelab-wide approval inbox.

**Rewritten 2026-09-11, on ADR-035 §6.** This phase used to be a *move*. It is not one. The statement
it replaces is preserved rather than deleted:

> ~~**Move the dashboard and control plane from Factory to homelab**, on the ADR-031 §1 boundary:
> Factory declares, homelab enforces and executes, so a control plane that acts belongs in homelab.~~
>
> ~~**This move was agreed but has never had an ADR.** Writing one is part of this phase, not a
> precondition assumed to exist. Until it is written there is no accepted decision to point at.~~

**There are two dashboards, not one that moved** (ADR-035 §6). The review found that this entry
conflated two products with different scopes and different owners:

| Factory Workbench — stays in `factory` | Homelab administration dashboard — this phase |
|---|---|
| One project at a time | The whole AI system |
| Project `ops/` and the project inbox | The homelab-wide approval inbox |
| Tasks, team, reviews, workflow | Models, providers, costs, tools, runtime health |
| Portable execution adapters | Authoritative homelab execution and configuration |

Moving Workbench into homelab would make it unavailable to exactly the standalone adopters ADR-031 §4
requires it to serve. **The ADR this phase was waiting for now exists** — ADR-035 §6 — so the
"no accepted decision to point at" gap is closed. What may still need its own decision is the hosted
deployment: Tailscale-only, with application authentication and secure sessions, and **public
exposure is out of scope** (ADR-035 §7).

**Depends on Phase 23** for the runtime state it displays, and on **Phase 20.0** for the project
record schema. Building against the pre-rewrite schema would be work done twice.

**Factory's `roadmap.md` plans the same deliverable itself** — V1.5, *"Read-Only Local Management
Dashboard"*, and V3, *"Local Dashboard Control Plane"*. **Both are superseded by this phase**
(ADR-031 §9, as amended 2026-09-10). Two live plans for one deliverable was flagged as an open
conflict when this phase was added earlier the same day, and it is closed the way the overlap itself
was closed: there is one plan, and it is homelab's. Retiring the V-series entries is Phase 20's work
(see above); this phase is where the deliverable actually lands.

## Phase 23 — Homelab AI Foundation

Build the **AI execution harness** — the thing that makes homelab more than a gateway with a router
in front of it.

**Added 2026-09-11. A new number rather than a renumbering**, per the roadmap rule above and the
Phase 18 precedent. **This is the one genuinely new structural entry in the post-ADR-034/035
reconciliation**; everything else was a rewrite of an existing phase. It exists because the design
review's dependency outline contains a block of work with no home on this roadmap, and leaving it
unplaced would leave Phase 20 and Phase 22 depending on something unnamed.

The owner's defining sentence for homelab's scope, recorded in the design review:

> **Homelab is an AI execution harness.** It performs the context selection, task decomposition,
> retrieval decisions, per-call model selection and controlled execution that a tool such as Codex or
> Claude Code normally performs *internally*.

That is the measure of what belongs here. When Claude Code decides which files to read, whether to
search the repository for a sub-question, how to break a request into steps, and which model serves
each one — those decisions are homelab's.

Scope, and **where each piece already has a home**, so this phase adds rather than duplicates:

| Piece | Home |
|---|---|
| Provider/gateway integration and the spend governor | **ADR-033**; Phase 15 |
| Model registry, eligibility, caps, fallback | **Phase 15.0** — already briefed |
| Deterministic routing, then AI-assisted, deterministic retained as fallback | **Phase 15** (amended above) |
| Retrieval and the Brain specialist's project-facing contract | **Phase 10**, whose ADR-032 gate still binds |
| **Task decomposition** | **here** — no existing phase |
| **Context assembly and cache-prefix discipline** | **here** — no existing phase |
| **Budgets, audit, approvals as runtime machinery** | **here** — no existing phase |

**The cache economics are engineered, not inherited.** The favourable numbers observed in the owner's
measured week are a property of *those harnesses'* stable-prefix discipline, not of the models they
call. A homelab harness earns them only by designing for them deliberately — recorded here because it
is the assumption most likely to be made silently and found false late.

**Budgets are two limits, not one** (design review): a monetary limit for metered providers and a
model-call limit for subscriptions and unknown-cost providers. The first limit reached stops
execution and raises a project-inbox request. Unknown cost stays `unknown` and is never replaced with
a confident estimate.

**This phase is where ADR-034 §13 takes effect** — a model's tool request becoming an untrusted
request checked by the runtime rather than something architecturally inert. Until then ADR-025 §10
stands as written and the Phase 09 canary check still applies. **It is the single largest security
change on this roadmap** and its validation list is ADR-034's, each item proved against a planted
positive control.

**Depends on Phase 20.0**, which produces the first real consumer. **Feeds Phase 19**, whose concrete
tools should follow the capability gaps this phase actually observes. **A brief must be written and
committed before implementation** (ADR-017); it does not exist yet, and this entry is a placement
decision rather than a design.

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

### Not finished by that split — ADR-031, 2026-09-10

The table above records what was true on the day of the split and is left as written. It is no longer
the target topology. ADR-031 found that the split drew visibility per *repository* where ADR-029 §2
had specified it per *artifact*, which left the knowledge base's method private by adjacency rather
than by decision. **`brain` as named above becomes the private archive `aleix-brain`, and a new
public `brain` holds the knowledge-base method** — that work is Phase 21.

**Deferred later the same day (ADR-031 §6, as amended).** That change is now coupled to the knowledge
work in Phase 10 rather than being near-term. `brain` keeps its current name and stays private and in
active use until then, so the table above is still an accurate description of the repositories that
exist today — it is the *target* it no longer describes.

## Sequencing note — 2026-09-11

**This section supersedes the Sequencing note of 2026-09-10 in full**, as that note required of
whatever replaced it: *"a later phase that changes the dependency graph should replace this section
rather than edit around it, and say which phase superseded it."* It was superseded by the Phase 19
design review and the ADRs that followed it — **ADR-034** and **ADR-035**, both accepted 2026-09-11.
The superseded note is preserved in git history; what it got wrong is stated below rather than
quietly dropped.

Like its predecessor, this is an assessment of **running order**, not a decision about scope. It
states what is true today and it is expected to be superseded the same way.

### What the previous note got wrong

1. **It put Phase 19 on the architecture critical path** as the single blocking item. Phase 19 was
   superseded before implementation, and the dependency runs the other way: concrete tools follow
   observed capability gaps.
2. **It had Phase 20 depending on Phase 19 and wanting Phase 15.0.** It needs neither.
3. **It had no entry for the homelab AI foundation**, which is now Phase 23 and is where most of the
   remaining engineering actually lives.

Its two-track observation was right and is kept.

### Two tracks, running in parallel

The pending work still splits on **who can do it**, not on subject matter.

| Track | Phases | Constraint |
|---|---|---|
| **Node** | 13, 14 | Requires the owner at the keyboard: privileged commands on a machine where no assistant holds the sudo password. Phase 18 is **complete**, so the worst of this is discharged — the node has a console, a verified backup and ADR-032 |
| **Architecture** | 20.0, 23, 20, 19, 22, 10+21, 15/15.0 | Repository work. Needs no node access and can proceed while the node track is idle |

Making either wait on the other idles the one that is free.

### The dependency shape

Taken from the design review's outline and reconciled against the roadmap's stable numbers:

```text
ADR-034 + ADR-035                                    ← done, 2026-09-11
    ↓
Phase 20.0 — minimal Factory Workbench + synthetic vertical slice
    ↓
Phase 23 — homelab AI foundation
    (provider/gateway · deterministic then AI routing · task decomposition ·
     context assembly and caching · budgets, audit, approvals · retrieval contract)
    ↓
real capability gaps observed
    ↓
Phase 19 — concrete homelab tools and mappings
    ↓
Phase 20 — intensive Workbench and catalogue migration
```

Phase 22 hangs off Phase 23 for runtime state and Phase 20.0 for record schema. Phases 15 and 15.0
feed Phase 23 and can run ahead of it. Phases 10 and 21 run together, still gated by ADR-032.

### Recommended order

1. **Phase 20.0 — minimal Factory Workbench.** Unblocked today, and the only pending item whose
   prerequisites are all satisfied. It is also what discharges ADR-031 §4's outstanding criterion,
   which has been outstanding since the layers were named.
2. **Phase 23 — homelab AI foundation.** The largest remaining block, and the one that makes the
   system stop being documentation.
3. **Phase 19 — concrete tools**, once Phase 23 has produced real gaps to fill.
4. **Phase 20 — intensive Workbench and catalogue migration.**
5. **Phases 10 and 21 together**, still gated by ADR-032's content gate.
6. **Phase 22 — administration dashboard**, once there is runtime state to show.

**Phases 15 and 15.0 can run at any point before Phase 23** and are the cheapest useful work
available: 15.0 is already briefed, costs nothing because it uses the two subscription CLIs that
already exist, and makes adding a metered provider a configuration change.

Then 13, 17, 12, 11, 14, 16 on their own merits.

### The bottleneck, stated plainly

**Phase 23 is where the effort is**, and it has moved. The previous note said Phase 20 was the
largest item, on the assumption that the work was converting ten thousand lines of prose. The review
split that phase: the executable slice is now Phase 20.0 and is small, while the conversion is
Phase 20 and runs late. What sits between them — building the harness that decides what to read, how
to decompose a request, and which model serves each step — is larger than 20.0, 19 and 22 combined.

**The owner is no longer the bottleneck they were.** Phase 18 is complete, so the node track is down
to 13 and 14 and nothing on the architecture track waits on the keyboard.

### What the first ten phases did and did not buy

Phases 00–09 are complete and they built a genuine substrate: a headless node reachable over
Tailscale, key-only SSH, Docker, and a read-only Telegram bot running unprivileged behind a
two-allowlist authorisation boundary with a model executor behind that. Phase 18 then gave it a
console, a verified backup and an explicit content gate.

They did **not** build the AI system. As of this note the node runs one read-only status bot, holds
zero repositories, and **no agent has ever executed anything**. Recording this distinction matters
more than it looks: eleven complete phases can read as "most of the way there", and the phases that
carry the system's actual purpose — 20.0, 23, 19, 20 — are all still ahead, with not one line of
Workbench or harness code written.
