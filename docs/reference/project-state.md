# Current Project State

- **Project:** Home Lab
- **Governance:** Self-contained sequential phases; the repository is the sole authority (ADR-017)

## Current delivered state

The reference node runs the delivered Home Lab and Factory system. The concise operational source
of truth is [current architecture](../architecture/current-architecture.md); completed handovers
remain the evidence for each delivery.

- Factory Workbench runs on loopback under `aleix` and uses the Phase 23.0 harness endpoint. ADR-047
  deliberately retains this account because its systemd sandbox is the Workbench trust boundary; a
  dedicated Workbench account is neither accepted nor currently planned.
- The harness is a version-1, synchronous compatibility endpoint: it validates a closed schema,
  labels a declared client origin, deterministically classifies the request, forwards supported
  questions by role key, and keeps a content-free audit record. It does not own durable Home Lab
  Runs or generic planning/orchestration.
- Telegram remains a separate, direct model-helper client. It has not been migrated through the
  harness.
- The model-helper owns the delivered registry/role routing, Claude and Codex provider adapters,
  Vercel AI Gateway support, count caps and the persistent fail-closed spend governor. Provider
  credentials remain isolated there. Docker is installed, but is not the core runtime path and has
  no persistent containers.
- Persistent operational state exists: Factory project/workflow records, harness audit records,
  provider count/spend ledgers, and encrypted-volume project/Brain data. These records are not the
  generic durable Run lifecycle defined for the target.

## Accepted target and architecture governance

[ADR-050](../decisions/ADR-050-core-execution-contract.md) and
[ADR-051](../decisions/ADR-051-run-orchestration-state-boundary.md) are **Accepted** and govern
their scoped successor decisions. ADR-050 defines an agent-agnostic Home Lab target in which a canonical request
creates a durable Run; planner and orchestrator are distinct logical responsibilities; and an
implementation-neutral plan resolves through Home Lab runtime capabilities to eligible services.
Factory remains a client/domain system that owns its own workflow semantics and may retain an
independent requirement vocabulary.

ADR-051 completes the Run persistence-boundary architectural gate: one harness/orchestrator-owned
lifecycle uses content-minimized root-resident control state while richer/sensitive content remains
protected or domain-owned by reference. Root gains no volume-unlock capability; unlock or dependency
recovery requires revalidation rather than automatic resume. This is accepted target architecture,
not a deployed durable-Run implementation.

These are accepted target decisions, not claims that they are deployed. Existing role routing and
Phase 23.0's return-and-forget behavior remain compatibility mechanisms until later work replaces
them. [Target architecture](../architecture/target-architecture.md) is the living specification;
ADR-045 remains authoritative for phase allocation.

## Current planning status

The project is in documentation/design reconciliation; implementation of the ADR-050/ADR-051 architecture
is out of scope. The current sequence is:

```text
accepted ADR-050 + ADR-051
  -> reconciled target architecture
  -> reconciled current architecture
  -> current-state/reference reconciliation
  -> roadmap and phase replanning
  -> reconciled ADR-051 propagation into living planning/reference documents
  -> fresh Phase 23.1 brief
  -> implementation later
```

The fresh Phase 23.1 brief is the next required planning artifact; implementation has not begun.

Persistence technology, exact path/schema, retention duration, retry/idempotency, process topology,
trusted ingress/client attestation, a future request/wire correlation version, and any phase
reallocation remain unresolved design/planning matters. This reference does not select their
implementation or ordering; ADR-050, ADR-051, the living architecture documents and ROADMAP govern
the applicable decisions.

## Historical snapshots and phase records

The sections below preserve completed-phase evidence, dated decisions and prior planning context.
Their dated "next", gap and risk statements describe the point at which they were written; they do
not override the current summary above, ADR-050, the living architecture documents or future
roadmap reconciliation.

## Phase 01 status

| Item | State |
|---|---|
| Phase 01 brief | **Ratified** by Project Planning 2026-09-08 with six amendments, all reconciled (`docs/handovers/01-ubuntu-server.md` §0.1) |
| Guide | ✅ Complete (`guide/01-ubuntu-server/README.md`), including reference-build experience and tested versions — filled in by performing the install, which corrected it five times |
| Scripts | Written and syntax-checked; USB writer safety guards tested |
| ADR-014 / 015 / 016 | **Accepted**, all amended 2026-09-08 per ratification |
| Phase 00 hardware prerequisite | ✅ **Closed** 2026-09-08 — identification and physical validation both complete |
| Installation on hardware | ✅ **Complete** 2026-09-08 |
| Validation | ✅ **Passed**, including unattended power-loss recovery |
| Handover | ✅ [`01-ubuntu-server-handover.md`](../handovers/01-ubuntu-server-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-08 — `77476eb` |

### Phase 00 closure

Phase 00's documentation and governance work was complete at bootstrap. Its remaining
hardware-verification checks were executed as **Phase 01 Part A**, as Project Planning ruled in
amendment 2 — no separate hardware implementation phase or working context was needed.

The agreed closure condition was that the Part A checklist be recorded in
`docs/reference/hardware.md`, with this file and `ROADMAP.md` updated to say so. That has been done.

**Status 2026-09-08: CLOSED.** Both halves of Part A are complete. Identification recorded RAM
layout, storage, wireless adapter and CPU; physical validation confirmed USB ports, video output and
acceptable fan noise. **Phase 00 is finished** — see `ROADMAP.md`.

## Workspace reorganisation, 2026-09-10 (ADR-030)

**Done on the development machine and on GitHub. The node was deliberately not touched.**

| Layer | Repository | Visibility | Change |
|---|---|---|---|
| Infrastructure | `homelab` | public | unchanged |
| Execution | `factory` | public | unchanged; its duplicate copy inside the knowledge base was deleted |
| Projects | `projects/oncla` | **new**, private | 159 files, 89 commits, extracted from the knowledge base with history |
| Projects | `projects/factory` (`factory-ops`) | **new**, private | 156 ops records, 26 commits, extracted with history |
| Knowledge | `brain` | private | 896 tracked files → 497; holds knowledge and its own operating layer, nothing else |

What was resolved:

- **The method layer existed twice.** Factory was extracted and published on 2026-09-10 but never
  removed from its source, leaving 90 files in both places — every one already differing, because
  Factory's copies were anonymised. Deleted from the knowledge base, gated on a counterpart existing
  at the mapped path (90/90 matched), with the check validated in both directions against planted
  controls first.
- **The knowledge base held a product and an ops record.** Both are now their own private
  repositories under `projects/`.
- **`brain` had two branches.** `project/ONCLA` was 10 commits ahead of `main` and 97 behind;
  merged and retired, so the knowledge base has one history.
- **A stash from 2026-06-02** was found and checked rather than discarded: 87 of its 90 added lines
  were already on `main`, and the remaining two were a date string and a rewritten log heading. Fully
  superseded. It survives in the backup bundle.

What was deliberately **not** done: no repository was cloned onto the reference node. The node still
has an unencrypted root filesystem and no backup, and putting private repositories on it is the
event ADR-015 exists to be revisited before. Phase 18 owns that decision. *(True when written.
Phase 18 delivered the backup; ADR-037 executes the encryption, into a volume separate from root.)*

Links: 50 in live documents were rewritten; ~300 in session notes and the append-only log were left
pointing at old paths, with a translation table in the knowledge base's `05-logs/README.md`. Records
say what was true when written (`PROJECT.md` §11).

### Superseded as a target later the same day (ADR-031)

**The table above is a record of the operation and is left as written.** It still describes the
repositories that exist today; what it no longer describes is the target.

ADR-031 found that the split drew visibility **per repository** where ADR-029 §2 had specified it
**per artifact**, which left the knowledge base's method private by adjacency rather than by
decision. The target topology is therefore three public *method* repositories — `homelab`, `factory`
and a **new public `brain`** that does not yet exist — plus N private *content* repositories, one of
which is the existing knowledge base as an archive.

**That change is deferred as a whole operation** (ADR-031 §6, as amended 2026-09-10) and coupled to
the Phase 10 knowledge work: the new public `brain` is designed and built together with the ingestion
pipeline and the RAG system, not before them. **Until then the existing private `brain` stays as it
is, under its current name, in active use** — no rename, no method extraction, no content migration.
That work is Phase 21.

## Historical high-level decisions (2026-09-11 snapshot)

This snapshot records the accepted direction at that point. It does not override the current
summary, later accepted ADRs or the living architecture documents. See `docs/decisions/` for the
full records.

- used budget hardware as the reference platform;
- M700 as orchestration/infrastructure node;
- Ubuntu Server LTS as the hard requirement; 26.04.1 LTS as the *tested* reference build, with its
  ISO and checksum pinned for reproducibility rather than as a constraint (ADR-014);
- whole-disk LVM without full-disk encryption, chosen for unattended headless boot — a
  reference-build trade-off rather than a universal recommendation (ADR-015);
- Wi-Fi as the reference node's *initial* network link, with Ethernet preferred where practical, a
  documented installer fallback path, and reliability to be validated (ADR-016);
- MacBook-driven remote development;
- SSH keys + Tailscale + VS Code Remote SSH;
- model-agnostic architecture;
- explicit router/executor layers before agent frameworks;
- subscription-backed Claude Code/Codex first where officially supported;
- Telegram as first remote interface;
- knowledge storage separate from agents;
- unprivileged user-facing services;
- progressive automation;
- Docker as the container runtime baseline, rootful with non-root containers and explicit-interface
  port publishing (ADR-022);
- known-working `main` branch;
- **metered multi-provider model access as the target substrate**, vendor deliberately unnamed, with
  models as configuration and per-provider unattended eligibility enforced by the router (ADR-026);
- **agents declare a need, never a model**; Factory declares and homelab enforces (ADR-027,
  **superseded in full by ADR-034** on 2026-09-11). Under ADR-034: **Factory agents declare portable
  capabilities and execution backends provide concrete tools**, so homelab is one advanced backend
  rather than a prerequisite; `capabilities` and `tools` are separate manifest fields and
  `model_policy` is **removed**, because an agent's *role* is its declaration of need — **ADR-026 §4
  survives intact**; incompatibility fails **before activation**, naming every missing requirement;
  one scalar capability level becomes independent **effect / approval / availability / target scope**
  properties; and **ADR-027's human ceiling is reversed for service specialists**, which may hold
  narrow independent authority and run unattended — safe only because delegation does not transfer
  access and the *receiving* agent validates every agent-to-agent request. **ADR-034 §13 changes
  ADR-025 §10** when tool-using agents are implemented, and not before. **Later qualification:**
  ADR-050 supersedes or qualifies this snapshot's generic Home Lab agent, role-routing and
  capability-ownership assumptions. The current target separates client actor/persona from
  inference purpose/task requirements and policy-selected provider/model routes; Factory's domain
  requirements and activation rules remain Factory concerns;
- **Factory Workbench executes Factory project operations; the configured backend executes AI and
  concrete tools** (ADR-035, 2026-09-11, refining ADR-031 §1 — nine of its eleven sections are
  untouched). Workbench lives in Factory, holds **no homelab credential, model registry or tool
  implementation**, and reaches AI through one of several adapters, of which only the deterministic
  fake is fixed. **Two dashboards, not one that moved**: Workbench owns project views; Phase 22
  becomes the homelab administration dashboard. **ADR-031 §7's tool-vocabulary prerequisite is
  void**, so the Factory rewrite is unblocked;
- **The Factory is stateless method; each project carries its own state** and references Factory
  definitions rather than copying them (ADR-028);
- **method is public, output is private** (ADR-029 §2), with the unit of that decision the
  **artifact, not the repository** — which supersedes ADR-029 §1's and ADR-030 §1's four-repository
  visibility tables (ADR-031 §3). The target is three public *method* repositories — `homelab`,
  `factory` and a **new public `brain`**, which does not exist yet — plus N private *content*
  repositories: the existing knowledge base as an archive, and one per project. **Today `brain` is
  still the single private knowledge base under its current name**; the change is deferred and
  coupled to Phase 10 (ADR-031 §6, as amended);
- **each public layer must be independently adoptable** — someone must be able to take `factory` plus
  a knowledge base without `homelab`, or `homelab` alone, and each public repository needs a
  standalone quickstart. **Narrowed 2026-09-11 by ADR-042**: this applies to `factory`, which
  discharged it in Phase 20.0 by running from a clean clone. `homelab` is **public and readable, not
  packaged** — configuration is the seam, examples published and values not (ADR-031 §4, ADR-042);
- **a tool is what the runtime can refuse; a skill is what can only be followed** (ADR-031 §2) — and
  under ADR-035 §3 a **capability** is a third thing, the portable *request* for a refusable outcome,
  with the refusal still happening in the backend that owns the tool. **Agent manifests are JSON**
  (ADR-031 §11), which ADR-034 did not reopen;
- **one internal system: homelab.** One `ROADMAP.md` and one progress record govern this project's
  own development; Factory's `roadmap.md` and the Locked Decisions in its `progress.md` are
  superseded, and retiring them is Phase 20's work (ADR-031 §9, as amended). This does not narrow
  adoptability: what a public repository ships is the method, the contracts and the definitions —
  never this project's roadmap. An adopter writes their own plan;
- **four workspace layers** — infrastructure, execution, projects and knowledge — with `projects/` a
  plain directory holding one private repository per project, and **every project carrying its own
  `ops/`** beside the product rather than inside it. Closes the question ADR-029 §6 left open, by
  making the Factory's own self-hosting records just another project's ops (ADR-030).

## Recently resolved (Phase 01 Part A, 2026-09-08)

- ✅ **M700 RAM module layout** — **1 × 8 GB, one of two slots occupied.** Open since project
  bootstrap. Upgrade path is now 8+8 = 16 GB, with 8+16 = 24 GB optional. **No upgrade is required
  before or during Phase 01.**
- ✅ **Wireless adapter model** — **Intel Dual Band Wireless-AC 8260 (802.11ac).** Uses the in-tree
  `iwlwifi` driver with `iwlwifi-8000C` firmware, which ships in Ubuntu's `linux-firmware` package.
  The ADR-016 risk that the installer cannot see the card is **substantially reduced**; the fallback
  path is retained but is now unlikely to be needed.

## Known unknowns

- Exact versions of tools to be installed in future phases. Docker/Compose/containerd and both Phase
  06 AI CLIs are now recorded.
- ~~Exact Claude/ChatGPT subscription costs to record in the ledger.~~ **Closed 2026-09-09** —
  23.00 EUR/month for the ChatGPT subscription used by Codex and 22.50 EUR/month for Claude Pro.
- ~~Public repository license.~~ ✅ **Closed 2026-09-09** by Phase 04 — MIT for code, CC BY-SA 4.0
  for documentation (ADR-021).
- ~~Final GitHub repository owner/name if different from `homelab`.~~ ✅ **Closed 2026-09-09** —
  `TelesforoAleix/homelab`, public.
- ~~Whether 2FA is enabled on the GitHub account.~~ ✅ **Closed 2026-09-09** — verified enabled
  (`two_factor: true`) after adding the two read-only scopes needed to ask. Primary email is
  **private**, and all commits use the GitHub noreply address.

## Phase 07 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`07-telegram.md`](../handovers/07-telegram.md), committed as `54a33d2` before implementation |
| Service | ✅ `homelab-telegram-bot.service` — native systemd, enabled, running |
| Account | ✅ `homelab-bot` uid 999, `nologin`, no home, **no privileged group** |
| Hardening | ✅ `systemd-analyze security` → **1.3 OK** |
| Exposure | ✅ **No listening socket.** Long polling, outbound HTTPS only; `ss -tln` unchanged |
| Isolation | ✅ Proved by attempted access — cannot read `/home/aleix`, either AI credential, the Docker socket, or its own token |
| Reboot test | ✅ Started 7s after boot, **0 restarts**; recovered from a DNS-not-ready window unaided in 56s |
| ADR-023 | ✅ **Accepted** |
| Guide | ✅ [`guide/07-telegram/`](../../guide/07-telegram/README.md) |
| Verifier | ✅ 0 failures, 0 warnings |
| Handover | ✅ [`07-telegram-handover.md`](../handovers/07-telegram-handover.md) |

**Read-only by design, with no escalation built.** Phase 08 owns the executor pattern; widening the
service account is its decision to make deliberately, not to inherit.

## Phase 08 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`08-router-executors.md`](../handovers/08-router-executors.md), committed as `0d2ff86` |
| Router | ✅ Registry-based, in-process; authorisation check in one function |
| Executors | ✅ Six, at three capability levels; `/help` generated from the registry |
| Authorisation | ✅ Two allowlists; privileged enforced as a **subset** at startup |
| Escalation | ✅ polkit, scoped to **one user, one unit, one verb**; **zero sudoers entries** |
| Second gate | ✅ Unit allowlist inside the bot, independent of polkit |
| Account | ✅ `id homelab-bot` **byte-identical to Phase 07** |
| Denied | ✅ `ssh`, `tailscaled`, `systemd-networkd` — asserted on the reason, not just failure |
| Audit | ✅ Two independent records (bot + systemd PID 1). **polkit logs denials only** |
| Model executor | ✅ Registered, **deliberately unwired** — Phase 09 connected it (ADR-025) |
| Exposure | ✅ Still **1.3 OK**; listeners still 6 |
| Reboot test | ✅ 24.4s; service and grant both survived, proved end-to-end |
| ADR-024 | ✅ **Accepted** |
| Handover | ✅ [`08-router-executors-handover.md`](../handovers/08-router-executors-handover.md) |

**Two Phase 07 properties were traded deliberately:** the bot now forks (`/restart` execs
`systemctl`), and `AF_UNIX` is permitted (needed to reach PID 1). Neither opens the Docker socket,
which is `root:docker 0660` to an account in no group but its own.

## Phase 23.0 status

**Complete 2026-09-13.** Brief committed before implementation (`9b6db12`), corrected in S1 (§6.6,
§7.2) and S2 (§8 row 12) with the observations in the commits. Five real calls, 0 €.

| Item | State |
|---|---|
| Endpoint | ✅ `homelab-harness.service`, `User=homelab-harness` (uid 995), `127.0.0.1:8766`, `StateDirectory` on root, `WantedBy=multi-user.target`; score **1.3**; eighth socket; `OnFailure=homelab-notify@harness.service` |
| Layer 1 | ✅ closed schema, `v: 1`; `client`/`user`/`user_id`/`origin`/`peer`/`identity`/`request_id`/`ts` in the body → `identity_in_body`, named; `role` required; `X-Homelab-Client` recorded as `client_declared` — a label |
| Layer 2 | ✅ four classes, ten rules, no model call; `question` served, `task` → `needs_decomposition`, `command` → `not_a_request`, `unclassifiable` refused; structural signals beat the declared kind |
| Layer 9 | ✅ `request_id` returned; `audit.jsonl` one line per request, ids/labels/enums/lengths only — proved on the file (exact key set, closed grammars, content strings absent); question grep on the node → 0 |
| ADR-048 | ✅ **Accepted** — socket `aleix:homelab-model:0660`; `getent group` = `homelab-bot,homelab-harness`; `nobody` → `EACCES`; `/ask` unchanged across the change and a locked reboot |
| `RuntimeMaxSec` | ✅ 270 on the helper instance (drop-in); endpoint client timeout 280 |
| Second adapter | ✅ `factory` `9986188`: `homelab.py`, `adapter` key, `cli run`; 55 tests on both machines; **"the adapter interface is proved"** locally and on the node; row 17 triple by `request_id 25342f79…` |
| Locked boot | ✅ harness `active`, Workbench `inactive` (Condition), 0 failed, `running`; unlock → Workbench active |
| Canary | ✅ model returned `/restart ssh.service` as text; `NRestarts 0 → 0` |
| Deferred, by name | Telegram as a client (§6.7); the correlation field on `Result` (23.3); a `task` served (23.1); context assembly (23.2); the reservation-not-released cap behaviour (15.1) |

## Phase 15.0 status

**Complete 2026-09-13.** Brief committed before implementation (`7c2fc3b`), one §9 bullet amended
during S1 with the reason. Nothing metered, no cost.

| Item | State |
|---|---|
| Registry | ✅ `/etc/homelab-model-helper/config.json`: `providers{claude, codex} → models`, `routes{owner-interactive}`, `default_route`. The Phase 09 shape is refused, not migrated; `.bak-2026-09-13` beside it |
| Routing | ✅ `role` on the wire → `resolve_route()` — the one function, receives the key alone. Bot sends none → `owner-interactive`. Unknown → `unknown_role`, no cap |
| Eligibility | ✅ `unattended` per provider, checked before the cap reservation. **Refusal proved** (test 1) against a positive control (test 2), zero cap (test 3) — MacBook 19/19 ×4, node 19/19 as `aleix` |
| Owner floor | ✅ `caps.owner_reserve = {3/h, 15/d}` of `{6, 30}`, per provider on the same count. Tests 5 and 7 observed |
| Hints | ✅ `priority`, `severity`, `complexity`, `summary` accepted, validated, logged; same `provider/model` with and without (test 11). Unknown fields refused by name (test 8) |
| `/ask` | ✅ Unchanged; two live replies `-- claude/haiku`, one with the volume locked (test 14) |
| Boundary | ✅ `id homelab-bot` byte-identical; seven listeners; score **3.8**, unit file untouched; `verify` all nine checks |
| `metered` / `credential` | Reserved for 15.1; **presence refused** until the governor ships (handover, *To 15.1*, item 1) |

## Phase 09 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017 (`351f825`).

| Item | State |
|---|---|
| Brief | ✅ [`09-model-executor.md`](../handovers/09-model-executor.md), committed as `351f825` |
| Credential boundary | ✅ `homelab-bot` **still cannot read either OAuth file** — tested by attempting it |
| How the call is made | ✅ `homelab-model-helper`, runs as `aleix`, socket-activated, one process per connection |
| Access control | ✅ The socket's group and mode (`aleix:homelab-bot:660`), enforced by the kernel — **not** a check in Python |
| Account | ✅ `id homelab-bot` **byte-identical**; no group, no sudoers entry, no `/home/aleix` access |
| Listeners | ✅ `ss -tln` still **6** — a UNIX socket adds none |
| Providers | ✅ Two, independent limits, automatic fallback. **Only exhaustion falls back; a hard error does not** |
| Models | ✅ Cheapest by default: `haiku`, `gpt-5.6-luna` (`gpt-5.4-mini` is rejected on a ChatGPT account) |
| Tool suppression | ✅ Verified with a canary file inside the working directory, against a positive control |
| Model output | ✅ Never dispatched — proved by asking the model to emit `/restart ssh.service`, which it did, with no effect |
| What is sent | ✅ Question + the five `/status` figures only; prompt printed verbatim |
| Caps | ✅ 6/hour, 30/day per provider, enforced **before** the call; lock proved with 10 racing processes |
| Fallback | ✅ Proved against a **genuinely exhausted** Claude, not a mock |
| Exposure | ✅ Bot still **1.3 OK** |
| ADR-025 | ✅ **Accepted** |
| Handover | ✅ [`09-model-executor-handover.md`](../handovers/09-model-executor-handover.md) |

**A second service now runs as the human's account.** It is the only one, and it is the concession
that keeps the credential out of the bot. Three hardening directives are deliberately absent, with
reasons in the unit: `MemoryDenyWriteExecute` (both CLIs ship a JIT), `RestrictNamespaces` (Codex's
sandbox is built from namespaces) and `SystemCallFilter` (unmeasured surface).

**A Phase 07 defect was found and fixed here:** `StartLimitIntervalSec` was in `[Service]`, where
systemd ignores it. The effective window was 10s against `RestartSec=10`, so the restart limit was
**unreachable** for two phases. `install-telegram-bot.sh` now runs `systemd-analyze verify` on
every install.

## Phase 18.2 status

**Complete 2026-09-12.** Brief committed before implementation per ADR-017 (`ba366be`); executed on
branch `phase/18.2-work` in a separate worktree. Every row of brief §8 OBSERVED by the owner on the
node on 2026-09-12.

| Item | State |
|---|---|
| Brief | ✅ [`18.2-migration-to-the-server.md`](../handovers/18.2-migration-to-the-server.md) — corrected during S1 (§6.3, §6.4, §6.6, §8 row 7, §16) with the observations in the commit |
| Handover | ✅ [`18.2-migration-to-the-server-handover.md`](../handovers/18.2-migration-to-the-server-handover.md) |
| Guide | ✅ [`guide/18.2-migration-to-the-server/`](../../guide/18.2-migration-to-the-server/README.md) |
| Standard | ✅ [`docs/standards/volume-dependent-services.md`](../standards/volume-dependent-services.md) — four directives, the `WorkingDirectory=` trap, the canary, the negative clause |
| Clones | ✅ Five, at `/srv/homelab`, `aleix:aleix`, SSH remotes, at each remote's HEAD; `brain` proved private by anonymous `ls-remote`; 12 s total |
| Node key | ✅ `~aleix/.ssh/id_ed25519_github`, owner-account key titled `homelab node — 2026-09-12`; `ssh -T` authenticated; excluded from `backup-node.sh` |
| Workbench | ✅ `homelab-workbench.service` enabled via `homelab-data.target`, `1.3 OK`, `127.0.0.1:8765` only; acceptance run on the node `PASSED` 14/7 in 0.4 s |
| Refusal + control | ✅ Locked: `start` rc 0, `inactive`, `skipped, unmet condition check`, **no alert**; unlock → `active` without a manual start — twice |
| Tunnel | ✅ Tailnet `curl` → `(7) Failed to connect`; through `ssh homelab-workbench` → HTML; one real `POST /api/status` on a `release_ready` ticket → `ok: true`, file changed, no commit |
| Sockets | ✅ 7, each named: 2× sshd, 2× resolved, 2× tailscaled, 1× python3 loopback |
| Locked boot | ✅ `sudo reboot` → Telegram `clean reboot. Data volume: LOCKED` at 19:42 UTC; no failed units; Workbench `inactive` → `active` on unlock |
| Crash loop | ✅ `failed` on kill 5 (start limit counts the unlock's start); 5 alerts; `stop` → no alert |
| Probe | ✅ Removed from node, `config/systemd/`, both backup lists |
| Backups | ✅ 130 files verified; both new units in coverage; key absent |
| ADRs | None required (brief §13); §6's recommendations taken |
| Cost | 0 DKK |
| Residual | `ops/` writes and `audit.jsonl` uncommitted until the owner commits (Phase 14); `factory-ops` records: 93 legacy statuses, `<ID>-slug` filenames duplicate on update; `verify-node-backup.sh` silent sudo pause; `RootDirectory=`/`StateDirectory=` predicted not observed; Tailscale drop mid-action untested |

## Phase 12 status

**Complete 2026-09-12.** Brief merged to `main` before implementation per ADR-017 (`ab093ef`);
executed on branch `phase/12-work` in a separate worktree.

| Item | State |
|---|---|
| Brief | ✅ [`12-scheduling-monitoring-notifications.md`](../handovers/12-scheduling-monitoring-notifications.md) |
| Handover | ✅ [`12-scheduling-monitoring-notifications-handover.md`](../handovers/12-scheduling-monitoring-notifications-handover.md) |
| Guide | ✅ [`guide/12-scheduling-monitoring-notifications/`](../../guide/12-scheduling-monitoring-notifications/README.md) |
| Boot notice | ✅ `homelab-watchdog.timer` enabled; fired once per boot on three boots 2026-09-12 (17:20:22 enable, 17:25:13 clean reboot, 17:34:51 power cut), `NRestarts=0`, every message reached Telegram |
| Classification | ✅ Journal-based, PID 1 only. Clean reboot → `clean reboot` (marker present); power cut → `unplanned reboot` (marker absent). `last -x` is not available on this node and was not installed |
| Lock state | ✅ `unlocked` and `LOCKED -- ssh homelab && sudo data-volume.sh unlock` both observed live; "not configured" not producible on this node by design |
| Failure alert | ✅ Fires on a real crash (`Home Lab alert: homelab-telegram-bot.service failed.` + journal lines), not on a clean `stop`; recursion guard verified empty |
| Model-helper boundary | ✅ `RestrictAddressFamilies=AF_INET AF_INET6` — `OSError: [Errno 97]` at socket creation; positive control is the bot's own connection |
| Regression | ✅ `id homelab-bot` byte-identical, `ss -tln` 6 listeners, bot `1.3 OK`, `--failed` empty, `is-system-running` → `running`, after the kill run and after both reboots |
| Backup lists | ✅ All seven deployed files in `NODE_PATHS` and `CRITICAL`, same commit (the brief named three; widened during execution) |
| ADRs | None required (brief §13) |
| Cost | 0 DKK |
| Residual | `homelab-notify@.service`'s own failure is unwatched (recursion guard, by decision); multi-recipient delivery untested (one owner); ~~`systemctl poweroff` path untested (only `reboot` was)~~ — **observed 2026-09-14 (Phase 00.1): `clean reboot. Down ~41m`**, the marker is written on a power-off too |

## Historical risk register

The following is the accumulated risk record from completed phases. It preserves the original
findings and closures; current architectural status is summarized above and in
[`current-architecture.md`](../architecture/current-architecture.md).

> **The repository is now public.** Everything below is publicly documented. That is intentional for
> a reference implementation, and the controls are real — SSH is key-only with `PermitRootLogin no`
> — but the cost of leaving a known weakness open has risen, and a *new* secret committed from here
> on is a disclosure, not a mistake that can be quietly amended.


- ~~SSH password authentication~~ — ✅ **closed 2026-09-09** by Phase 03 (ADR-018). The server
  advertises `publickey` only.
- ~~**Single SSH key.**~~ **Closed 2026-09-12 by Phase 13 (S2).** A second Ed25519 pair: public
  half in `authorized_keys` (two lines now), private half `age`-encrypted on the backup card next to
  the LUKS header, tested from the MacBook without the agent (rc 0), plaintext destroyed. With the
  console (ADR-041) and the restored backup (Phase 18) that is the third leg. The history: Phase 03
  left one key; Phase 02 made lockout-class changes recoverable, which is a different thing.
- ~~**The reference node still has no backup of any kind.**~~ **Closed 2026-09-11 by Phase 18.** A
  weekly, manual-by-design backup exists (`scripts/macos/backup-node.sh`) with a verifier that plants
  a positive control, proved by **restoring**: 182 entries, 312 KB of node state, 20 MB of repository
  mirrors. `/var/lib/tailscale` and `/etc/ssh/ssh_host_*` are deliberately excluded, with reasons.
  **The backup is secret material** — it contains the credentials named below — and the card is
  treated accordingly.
- ~~**The volume group has no free extents.**~~ **Closed 2026-09-12 by Phase 18.1.** The root LV was
  shrunk to 64 GiB (ADR-037 §1); the volume group now holds **11,116 free extents = 43.42 GiB**,
  deliberately unallocated so either side can grow online later without repeating the shrink.
- **Docker consumes the root LV.** Logs are bounded by `/etc/docker/daemon.json`, and Phase 05
  finished with Docker inventory at zero, but images, containers, volumes and build cache all land on
  the root filesystem.
- **`aleix` is in the `docker` group.** This is root-equivalent access without a password prompt.
  Accepted for the sole administrator in ADR-022; must never be granted to service accounts.
- **Personal AI OAuth credentials now exist in `/home/aleix`.** Both files are mode `0600`, but a
  process running as `aleix` can read them and the root filesystem is not encrypted. Phase 07 did
  not inherit them and Phase 09 did not either — but Phase 09 **did** add a service running as
  `aleix`, so a process that can read them now starts on demand (ADR-025). Whether personal
  subscription credentials are
  supported or appropriate for unattended execution.
- **Subscription inference is capacity-limited, not an availability SLA.** Claude reached its
  five-hour session limit during Phase 06 despite valid authentication. User-facing services need
  an explicit failure policy rather than an assumed always-available executor.
- **Claude Code automatically updates on its stable channel.** Tested versions remain recorded, but
  client behavior can drift between phases. Re-run the constrained fixture and record the new
  version after a material update.
- **Rootful Docker without user-namespace remapping.** Container root maps to host root; mitigated by
  non-root container defaults and Compose hardening. **Phase 13 declined (2026-09-12):** inventory is
  zero and the decision has nothing to protect yet; the first phase that ships a container decides,
  and says so in its brief.
- ~~No firewall.~~ **Closed 2026-09-10, out of phase**, because the shared-network finding made it
  the highest-value control available. `ufw` denies inbound by default and permits only `tailscale0`
  plus Tailscale's UDP port. Applied with a timed self-revert and verified in both directions.
  **Phase 13 (2026-09-12) took the rest:** `fail2ban` declined (no passwords, inbound only from
  `tailscale0` — nothing for it to count); node key expiry stays disabled (declined, revisit if the
  machine leaves the home); **Tailscale ACL applied** — members → node tcp/22 only, `config/tailscale/acl.hujson`;
  rootless Docker declined, above.
- ~~**Docker and Tailscale now both own packet-filtering chains.**~~ **Narrowed 2026-09-12 by Phase
  13.** Docker still publishes with DNAT before `INPUT`, and `DOCKER-FORWARD` accepts before ufw's
  forward chains — so ufw never sees a published port. The `DOCKER-USER` chain (ufw
  `after{,6}.rules`, `scripts/server/apply-docker-user-rules.sh`) now drops anything arriving from
  `wlp1s0`/`eno1` and returns for `tailscale0`, `lo`, Docker bridges and established flows. Rule
  presence OBSERVED; the live published-port proof is S3's first step. **`apply-firewall.sh` resets
  ufw and erases this block — run the DOCKER-USER script after it, always** (baseline standard §6).
- ~~**IPv4/IPv6 forwarding policy is asymmetric.**~~ **Was already closed on 2026-09-10** by ufw's
  `deny (routed)` default; OBSERVED by Phase 13 S1 (`ip6tables -S FORWARD` → `-P FORWARD DROP`).
  This bullet was stale from the moment ufw was enabled.
- **Node key expiry deliberately disabled** on the Tailscale node (ADR-019). **Revisited by Phase 13
  (2026-09-12) and kept disabled, by decision:** the console exists but the owner is not always
  home, and a lapsed key silently removes the remote path; device approval covers re-authentication.
  Revisit trigger: the machine leaves the home. The ACL now sits in front of sshd as the device-level
  control.
- ~~**The Telegram allowlist is per-deployment state on the node... whether it is inside the backup
  has not been verified.**~~ **Verified.** All three allowlist files (`allowlist`,
  `privileged-allowlist`, `restart-allowlist`) resolve under `/etc/homelab-telegram-bot`, which
  `backup-node.sh:93` collects recursively, and `verify-node-backup.sh`'s coverage check names all
  three inside the restored tar (Phase 18). The model helper has no allowlist.
- **Telegram is a third party.** Every bot message transits and is stored on their infrastructure.
  Acceptable for uptime and disk figures; a reason not to extend the bot toward anything sensitive
  without revisiting. Phases 08 and 10.
- **One thing can now change the system.** `/restart chrony`, scoped two ways and proved. Phase 07's
  property that a compromise could leak information but not act **no longer holds** (ADR-024).
- **The licensing question is still unresolved, and is now an *accepted risk* rather than an avoided
  one.** ADR-008 covers interactive use only, and nothing since has established whether automating a
  personal subscription falls within either provider's terms. Phase 09 avoided the question with a
  constraint — owner-initiated calls only (ADR-025 §9). **On 2026-09-10 the owner decided to accept
  the risk for the interim** and ADR-026 superseded §9: subscription providers may serve unattended
  calls, with eligibility now a per-provider field the router enforces. **ADR-040 then retired §9 in
  full on 2026-09-11**: autonomous calls are normal, budget replaces attribution as the control, and
  the licensing position is recorded as an accepted judgement rather than a resolved question. The
  disagreement is recorded
  in ADR-026 §5 rather than smoothed over — rate limiting bounds *capacity*, not terms, and the
  residual exposure is account action or throttling. **The control that makes this reversible is the
  `unattended` field, which must not be removed** just because every current entry is `true`.
  **Phase 15.0 (2026-09-13): the control now exists and has been proved** — a fixture provider set
  `unattended: false` is refused before any cap is spent, against a positive control, on the node;
  reversing the accepted risk for one provider is one boolean in root-owned config.
- **Data now leaves the machine on every `/ask`** — the owner's question plus the five `/status`
  figures, to Anthropic or OpenAI. Bounded deliberately: no logs, no file contents, no journal.
  Widening that context needs its own ADR, because anything able to write a log line could
  otherwise choose what gets sent (prompt injection). The backup and encryption decisions
  (ADR-015) must account for this.
- **The subscription allowance is a shared resource, and the bot spends it.** Not money — capacity.
  Both subscriptions hit their limits during Phase 09 itself. Capped at 6/hour and 30/day per
  provider, enforced before the call, but the bot and the owner draw from the same bucket.
- **A service now runs as `aleix`.** `homelab-model-helper` is the only one, and it exists so the
  credential stays out of `homelab-bot`. `aleix` can `sudo` and is in the `docker` group, so this
  process is a more valuable target than the bot; `NoNewPrivileges=yes` is retained and three
  further directives are deliberately absent with reasons recorded in the unit.
- **No alerting on the bot.** If it dies at 3am, nothing says so — and bounded logging means a quiet
  journal does not mean a healthy service.
- Wi-Fi is a single point of failure for *both* access routes. `eno1` is present and unused.
- **The LAN is not a home network, and must be treated as hostile.** Corrected 2026-09-10: the
  node sits on a shared building network — a flat `192.168.0.0/21`, 2046 usable addresses, occupied
  by many other tenants' devices — whose edge is administered by a third party and can be neither
  audited nor reconfigured by this project. Confidentiality between residents on a shared WPA2
  passphrase is effectively nil. **Treat the link as open Wi-Fi.** No port is forwarded to the node
  — proved by SSH host-key comparison — and no auto-forwarding protocol is available.
- No encryption at rest on **root** (ADR-015), which compounds with the cleartext Wi-Fi passphrase
  (ADR-016). Phase 13 should treat these together.
  **Built 2026-09-12 by Phase 18.1:** a separate 128 GiB LUKS2 volume (`ubuntu-vg/data`) now holds
  knowledge and project content, unlocked over SSH after boot — proved to open with the passphrase,
  refuse without it, and survive a real power cut locked and unattended. **Root stays unencrypted**,
  so the credentials named above remain at rest in the clear; **ADR-046 (Accepted)** decides that
  deliberately rather than leaving it implied — each is revocable in minutes and none can open the
  volume.
- ~~**Phase 10 must not silently inherit ADR-015.**~~ **Resolved.** The decision was taken rather than
  inherited: ADR-032 made the premise an explicit gate, and ADR-037 discharges it for an encrypted
  volume. Phase 10 stores real data **in that volume**, not on root.

## Phase 02 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`02-linux-fundamentals.md`](../handovers/02-linux-fundamentals.md), committed before implementation |
| Standard | ✅ [`safe-changes-headless.md`](../standards/safe-changes-headless.md), referenced from `AGENTS.md` |
| ADR-020 | **Superseded** by ADR-041 (2026-09-11) — its console-less premise was false |
| Guide | ✅ [`guide/02-linux-fundamentals/`](../../guide/02-linux-fundamentals/README.md) |
| Command reference | ✅ [`linux-command-reference.md`](linux-command-reference.md) |
| Scripts | ✅ `scripts/macos/preflight.sh`, `scripts/server/lab-sandbox.sh` — both run on the real machine |
| Tooling | ✅ `tree` 2.3.1-1, `ncdu` 1.22-1build1, `ripgrep` 15.1.0-1ubuntu1 |
| Validation | ✅ All checks passed with captured output; sandbox created, exercised and removed |
| Handover | ✅ [`02-linux-fundamentals-handover.md`](../handovers/02-linux-fundamentals-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-09 — `0e26859` |

**What Phase 02 deliberately did not teach**, so no later phase assumes it: no networking changes
were practised, no `sudoers` editing, no firewalling, no backup or restore, and no LVM growth. Those
were classified Tier 3 — studied by reading, not by changing — because the node had no console *as
Phase 02 understood it* and Phase 13 will have a better safety net. **That premise was corrected in
2026-09-11 (ADR-041): a console is available on demand.** The caution was still right; its severity
was overstated.

## Phase 04 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`04-git-github.md`](../handovers/04-git-github.md), committed before implementation |
| Pre-publication audit | ✅ Two independent scanners over all 220 blobs; **no secrets found, none removed** |
| Scanner validation | ✅ 6/6 planted secrets detected — after a bug that left the private-key class dead |
| ADR-021 | ✅ **Accepted** — publication, visibility and the licence split |
| Licences | ✅ `LICENSE` (MIT), `LICENSE-docs` (CC BY-SA 4.0) |
| Publication | ✅ `github.com/TelesforoAleix/homelab`, **public**, all 4 merge commits intact |
| Pull request | ✅ [#1](https://github.com/TelesforoAleix/homelab/pull/1), merged with `--merge` |
| Guide | ✅ [`guide/04-git-github/`](../../guide/04-git-github/README.md) |
| Workflow reference | ✅ [`git-workflow.md`](git-workflow.md) |
| Scripts | ✅ `scripts/macos/scan-history.sh` |
| Validation | ✅ All 16 checks passed with captured output |
| Handover | ✅ [`04-git-github-handover.md`](../handovers/04-git-github-handover.md) |

**Deliberately not adopted**, so no later phase assumes otherwise: no branch protection on `main`, no
commit signing, no CI/GitHub Actions, no clone of the repository on the reference node. Reasoning in
[`git-workflow.md`](git-workflow.md).

## Phase 05 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`05-docker.md`](../handovers/05-docker.md), committed before implementation |
| Implementation | ✅ Docker Engine 29.8.0, Compose v5.5.1, containerd 2.3.5 from Docker's official apt repository |
| ADR-022 | ✅ **Accepted** — Docker runtime and container conventions |
| Host configuration | ✅ `/etc/docker/daemon.json` log rotation, `vm.swappiness = 10`, `aleix` in `docker` group |
| Guide | ✅ [`guide/05-docker/`](../../guide/05-docker/README.md) |
| Reference | ✅ [`docker-reference.md`](docker-reference.md) |
| Scripts | ✅ `install-docker.sh`, `capture-network-state.sh`, `configure-docker-host.sh` |
| Validation | ✅ Learning exercises passed; no persistent containers/images/volumes/build cache remain |
| Handover | ✅ [`05-docker-handover.md`](../handovers/05-docker-handover.md) |

**Important evidence gap:** the pre-Docker network/firewall capture did not run, so the intended
before/after ruleset diff is unrecoverable. Phase 05 recorded this as a failure. Current chain
attribution is clean — Docker chains and Tailscale chains only — and final reachability checks
passed, but that is weaker than the diff the brief required.

**Conventions established:** rootful Docker; containers default to non-root; Compose services should
drop capabilities, use `no-new-privileges`, and use read-only filesystems where practical; every
published port names an interface; never grant the `docker` group to service accounts.

## Phase 06 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | [`06-ai-cli-access.md`](../handovers/06-ai-cli-access.md), committed before implementation |
| Implementation | Claude Code `2.1.236` stable and Codex CLI `0.153.4`, native user-scoped installs |
| Authentication | Claude Pro subscription OAuth and Codex Sign in with ChatGPT; no API keys |
| Linux sandbox | Ubuntu `bubblewrap` `0.11.1-1ubuntu0.1`; AppArmor restriction left enabled |
| MacBook Codex | Broken npm `0.118.0` package removed; standalone `0.153.4` active |
| Guide | [`guide/06-ai-cli-access/`](../../guide/06-ai-cli-access/README.md) |
| Reference | [`ai-cli-reference.md`](ai-cli-reference.md) |
| Scripts | `install-ai-clis.sh`, `verify-ai-cli-access.sh` |
| Host impact | No daemon, unit, listener, container, Node.js runtime, or API billing path added |
| Handover | [`06-ai-cli-access-handover.md`](../handovers/06-ai-cli-access-handover.md) |

**Boundary established:** these are interactive tools belonging to the administrator. Phase 07's
Telegram process must run under a separate unprivileged identity with no access to `/home/aleix`,
the Docker group, or either OAuth file. Connecting providers to unattended executors remains Phase
08 work.

## Phase 03 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`03-remote-access.md`](../handovers/03-remote-access.md), committed before implementation |
| Implementation | ✅ Key-only SSH, Tailscale 1.102.3, VS Code Remote SSH, console removed |
| Validation | ✅ All checks passed, re-run after a headless cold boot |
| ADR-018 / ADR-019 | ✅ **Accepted** |
| Guide | ✅ [`guide/03-remote-access/`](../../guide/03-remote-access/README.md) |
| Handover | ✅ [`03-remote-access-handover.md`](../handovers/03-remote-access-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-09 — `5804da6` |

**Sequencing:** the owner chose on 2026-09-09 to run Phase 03 ahead of Phase 02. Phase 01 named SSH
password authentication as its principal open risk, and Phase 02 is a long documentation-heavy phase
that would have left that risk open throughout. Phase 03 also gives Phase 02 a better environment to
be carried out in: key-based login, a stable `ssh homelab` alias, VS Code Remote SSH, and no attached
console. **Phase 02 is deferred, not skipped, and keeps its number.**

## Superseded planning note

The block below was written when Phase 01 closed, before the sequencing decision above. It is kept
rather than rewritten (`PROJECT.md` §11).

**Its instruction has since been discharged.** Phase 02 ran on 2026-09-09 and wrote its brief first,
committing `docs/handovers/02-linux-fundamentals.md` as `6ddf2a5` before any implementation existed.
The block is retained as the record of what was expected, not as an outstanding action.

**Phase 01 is complete and merged. Phase 02 has not started.**

1. **The Phase 02 context writes its own brief** at `docs/handovers/02-linux-fundamentals.md`, using
   `docs/templates/phase-brief-template.md`, and **commits it before implementation begins**
   (ADR-017).

   > Phase 01 began with no brief at all and the phase context had to draft one mid-flight. Under
   > the new model nobody else will write it, so this is now the phase's own first task rather than
   > something to wait for.

2. ~~Review Phase 01's recommended roadmap changes.~~ **Actioned 2026-09-08**, since ADR-017 left
   them with no recipient:
   - system-health assertion added to the Definition of Done in `PROJECT.md` and
     `docs/standards/definition-of-done.md`;
   - the Tailscale documentation warning written into the Phase 03 roadmap entry;
   - the ADR-015 revisit requirement written into the Phase 10 roadmap entry.

3. Sequencing is the owner's call. Phase 02 (Linux Fundamentals) is next by number; Phase 03 (Remote
   Access) closes Phase 01's principal open risk — SSH password authentication.

## Historical deployment snapshot (through Phase 23.0)

Re-verified 2026-09-09 at the close of **Phase 09**; the socket, harness and services rows were
updated at the close of **Phase 23.0** (2026-09-13). This snapshot is retained as evidence for that
point in time. It predates Phase 15.1's delivered gateway/governor state and is not the current
topology reference; use [`current-architecture.md`](../architecture/current-architecture.md) for
current deployed state.

| Fact | Value |
|---|---|
| Host | `homelab`, Lenovo M700 Tiny |
| OS | Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic |
| Primary access | `ssh homelab` → MagicDNS over Tailscale |
| Fallback access | `ssh homelab-lan` → `192.168.1.57` on the LAN |
| Authentication | **Public key only.** No passwords, no keyboard-interactive, no root login |
| Tailnet | `100.71.62.71`; node key expiry disabled |
| Admin user | `aleix`, sudo-capable; **`sudo` requires a password — no `NOPASSWD`** |
| Docker access | `aleix` is in `docker` group `983`; this is root-equivalent (ADR-022) |
| Storage | LVM. Root shrunk to **64 GiB** ext4 (62.4 G, 8.9 G used, 50.7 G available), **unencrypted by decision (ADR-046)**. A **128 GiB LUKS2 volume** (`ubuntu-vg/data` → mapper `homelab-data` → ext4, 126 G usable, 120 G available) mounted at `/srv/homelab`, unlocked over SSH (`data-volume.sh unlock`), `--allow-discards`. **11,116 extents (43.42 GiB) free** in the VG, deliberately unallocated (Phase 18.1, 2026-09-12) |
| Health | `systemctl is-system-running` → `running`, no failed units |
| Tooling | `tmux` 3.6, `htop`, `jq`, `git`, `vim`, `nano`, `less`, `lsof`, `tree`, `ncdu`, `ripgrep`, Docker 29.8.0, Compose v5.5.1, containerd 2.3.5, Claude Code 2.1.236, Codex CLI 0.153.4, `bubblewrap` 0.11.1 |
| AI authentication | Claude `claude.ai` / first-party / Pro; Codex `Logged in using ChatGPT`; relevant API-key variables unset |
| AI credential files | `/home/aleix/.claude/.credentials.json` and `/home/aleix/.codex/auth.json`, both mode `0600`, owner `aleix:aleix`; contents never captured |
| AI processes/services | None; both CLIs are interactive operator commands |
| Docker inventory | 0 images, 0 containers, 0 local volumes, 0 build cache |
| **Services** | **`homelab-telegram-bot.service`** — active, enabled, **0 restarts**. **`homelab-model-helper.socket`** — active, enabled; templated service instantiated per connection. **`homelab-watchdog.timer`** — active, enabled, once per boot (Phase 12, 2026-09-12); `OnFailure=` drop-ins on the bot, the model helper and the Workbench → `homelab-notify@<alias>.service`. **`homelab-workbench.service`** — active, enabled via `homelab-data.target` (Phase 18.2, 2026-09-12); `User=aleix`, `1.3 OK`; skipped while the volume is locked, started by unlock |
| **Volume contents** | `/srv/homelab` `aleix:aleix 0750`: `homelab/`, `factory/`, `brain/`, `projects/oncla/`, `projects/factory/` — clones, SSH remotes, 47 M (Phase 18.2). Node GitHub key at `~aleix/.ssh/id_ed25519_github` |
| Model helper socket | `/run/homelab-model-helper.sock`, `aleix:homelab-model`, mode `660` (ADR-048, Phase 23.0); members `homelab-bot,homelab-harness` |
| **Harness** | `homelab-harness.service` active, enabled, `127.0.0.1:8766`, `User=homelab-harness` (uid 995); routes `owner-interactive`, `execution-agent`; `max_question_chars 4000` (Phase 23.0) |
| Model access | `/ask` works. Registry: Claude `haiku`, Codex `gpt-5.6-luna` (Phase 15.0); route `owner-interactive`; caps 6/hour, 30/day per provider, owner reserve 3/15; `unattended` eligibility proved |
| Restart limit | **`StartLimitIntervalUSec=5min`** on the running unit — was silently 10s until Phase 09 fixed it |
| Service account | `homelab-bot` uid 999; groups: `homelab-bot` only. Not `sudo`, not `docker`, not `adm` |
| Service hardening | `systemd-analyze security` → **1.3 OK** |
| Listening | **7 sockets** — the 6 below plus **`127.0.0.1:8765` (python3, `aleix`, the Workbench; loopback only, proved unreachable over the tailnet)** since Phase 18.2, 2026-09-12. **`:22` is FILTERED on the shared Wi-Fi.** `ufw` is active and enabled at boot: default deny inbound, allow on `tailscale0`, plus UDP 41641 on `wlp1s0` for Tailscale direct connections. sshd still *binds* `0.0.0.0:22`; ufw drops the packets before they reach it. **Proved 2026-09-10** — LAN SSH times out while ICMP to the same address succeeds |
| **RAM** | **32 GB** — 2 × 16 GB Kingston `KVR26S19D8/16` (DDR4-2666, running at the CPU's 2133 MT/s), ChannelA-DIMM0 + ChannelB-DIMM0, dual-channel (Phase 00.1, 2026-09-14). `free` 30 GiB, `MemTotal 31701556 kB`. Was 1 × 8 GB Samsung `M471A1K43BB0-CPB`; that module is kept as a spare. Stability: `memtester 20G 1` all `ok`; no MCE/EDAC |
| Swap | `/swap.img` 4 GB, never used; `vm.swappiness = 10`. Left at 4 GB against 32 GB by decision (hardware.md §Swap) |
| Boot | **31.3s** on the first boot with the new modules (2026-09-14): firmware **17.0s** (memory training; the boot before was 5.7s), loader 3.9s, kernel 0.9s, initrd 3.1s, userspace 6.4s. Earlier: 27.9s (was 24.4s); firmware POST rose 10.97s → 13.81s when the fTPM was enabled |
| **Console** | **Attached and login-tested 2026-09-11 (Phase 18).** A display is connected on `card1-DP-1`, `getty@tty1` is active. **It is Phase 18's chosen "second way in"**, over a second SSH key, because it survives network, firewall, SSH and Tailscale failure alike. Session 29 (the Phase 18 login test) was **closed deliberately 2026-09-12** at Phase 18.1's step B1, per the rule it established: log out before walking away. No console session was left open at Phase 18.1's close; monitor and keyboard were detached again after its power-cut test |
| **TPM** | **2.0** since 2026-09-10 (Intel PTT / Firmware TPM; was discrete 1.2). `/dev/tpmrm0` present. **Removed from the encryption design by ADR-037 §3** — the data volume unlocks over SSH, not the TPM, which would only have bound to the weaker SHA-1 PCR bank. Handed to Phase 13 as `systemd-creds`'s cheapest narrowing of ADR-046's accepted risk, not adopted |

Reproduce with `scripts/server/verify-install.sh` (Phase 01 base) and
`scripts/server/verify-remote-access.sh` (Phase 03 posture; run under `sudo` for a complete report).

> **The console is detached, not gone** — available on demand, connectors present, login tested
> (Phase 18, ADR-041). This is a written standard rather than a warning:
> [`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md), adopted as
> ADR-020 and referenced from `AGENTS.md`. Apply it before any change touching network, remote
> access, authentication, boot, or the admin account. `scripts/macos/preflight.sh` checks the parts
> a machine can check.
