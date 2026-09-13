# 23.0 — The endpoint

## Goal

An always-running, loopback-only service on the node — the **harness** — that accepts a normalised
request from any local client, attaches where it came from, classifies it, hands a question to the
model helper over the Phase 15.0 wire protocol, returns the answer with a request id, and writes one
content-free audit line. And the **second adapter**, `Workbench → homelab`, which is what finally
tested whether Phase 20.0's adapter interface was real.

Layers 1, 2 and 9 of [`target-architecture.md`](../../docs/architecture/target-architecture.md).
Brief: [`docs/handovers/23.0-endpoint.md`](../../docs/handovers/23.0-endpoint.md). Handover:
[`23.0-endpoint-handover.md`](../../docs/handovers/23.0-endpoint-handover.md).

## Why this matters

**What an endpoint is, and why the bot's router was never one.** The Telegram bot's
`Router.dispatch(user_id, text)` takes a *command* — a verb the bot already owns — from a user it
already trusts. An endpoint takes a *request* from a *process*, does not trust what the process says
about itself, and does not interpret the request beyond deciding what kind it is. Layer 1 attaches
identity; it never reads it from the body. Layer 2 says "question, task, command, or I cannot tell"
and executes nothing. Layer 9 returns the result and records that something happened — never what.
Mistake a command router for an endpoint and you get a service that trusts its callers' claims and
runs their verbs; that is why the bot stays a bot and the endpoint is a new thing.

**Why the endpoint holds no credential.** The model call happens in the helper, as `aleix`, behind a
UNIX socket. The harness is one more account allowed to knock on that socket. A compromised harness
can therefore do exactly two things: ask the helper for a routed question (capped, and the helper
still refuses everything the wire protocol refuses) and write its own audit file. What that costs in
unit-file terms is one directive — `RestrictAddressFamilies=` gains `AF_UNIX`, with a `# WHY` — and
one group membership (ADR-048).

**A taxonomy small enough to be deterministic.** Four classes, ten rules a reader can run by hand,
no model call. `unclassifiable` is a real answer, not a failure, and it refuses rather than guesses.

**How to prove an interface with a second implementation.** Run the same project through both
adapters and diff the records. If only the fields the adapter is *allowed* to fill differ, the
interface is real. If anything else moved, a backend concept leaked. It was run; the sentence is in
§ Validation.

**"Always running" is a property of the system.** The endpoint lives on the root filesystem, holds no
project content, and is `WantedBy=multi-user.target`. It came up on a locked boot while the
Workbench correctly stayed down.

## Reference-build choice

| Decision | Choice | Why |
|---|---|---|
| Account | `homelab-harness`, system, nologin, no home, groups: own + `homelab-model` | Baseline §3, ADR-047: the first service that *accepts requests from another process* gets its own boundary. Never `aleix` (sudo, docker, OAuth files); never `homelab-bot` (the watchdog's reuse was for a unit that *sends*) |
| Listener | `127.0.0.1:8766`, refused elsewhere in code, the eighth socket | ADR-038 §2 — every client is local |
| Reaching the helper | group `homelab-model` owns the socket; members `homelab-bot`, `homelab-harness` | **ADR-048.** Not a `usermod` into the bot's group (a group meaning two things), not a second socket, not `SupplementaryGroups=` (then `getent group` would not be the access list) |
| State | `StateDirectory=homelab-harness` on **root**, holding `audit.jsonl` and nothing else | Brief §6.3, ADR-046 §2: up with the volume locked; results are the client's to record; no volume-dependent contract |
| Classifier | deterministic, four classes, structural rules before the declared kind | No governor yet to bound a model call; a client can lift `unclassifiable` to `question` by declaring, but cannot relabel work as a question |
| `client` | a label in a header, recorded as `client_declared` | No credentials in 23.0; loopback is the trust boundary. **Not an identity** — 23.3's |
| Adapter selection | one key, `ops/project.json` `"adapter": "fake" \| "homelab"`, default `fake` | URL fixed in the adapter; loopback is not a per-project choice |
| Telegram as a client | **deferred** | `/ask` is the recovery path when the volume is locked; the shared caps are one more reason not to put it behind the new consumer |
| `RuntimeMaxSec` | 270 on the helper instance (drop-in); endpoint's client timeout 280 | The 15.0 debt: two providers × 120 s outlived the old 180. The harness outlives the helper and reports the helper's failure |
| Question limit | 4000 chars, both sides | The helper *truncates* silently past its limit; the endpoint *refuses* `too_large`. Keep equal. A size bound, not a security control |

## Alternatives

Considered and not taken, each with the reason in the brief or ADR-048: running the harness as
`homelab-bot`; a per-client token for `client` (a credential in 23.0); a model-assisted classifier
(the smallest spend, but no governor to bound it); a second helper socket for the harness; routing
`/ask` through the endpoint now; a dashboard button instead of the CLI `run`.

## Prerequisites

Phase 15.0's helper (the wire protocol, `role` as the routing key), Phase 13's baseline, Phase 18.2's
Workbench on the node, Phase 20.0's adapter interface. The node facts at the start are in the brief §2.

## Implementation

### The pieces

| Piece | Where |
|---|---|
| The endpoint | [`services/homelab-harness/`](../../services/homelab-harness/) — `harness.py` (layers 1, 9), `classify.py` (layer 2), `config.example.json`, `fixture-tests.py`, `dev-stub.py`, and a `README.md` with the schema, the taxonomy table and the audit schema |
| Its unit | [`config/systemd/homelab-harness.service`](../../config/systemd/homelab-harness.service) + `homelab-harness.service.d/onfailure.conf` |
| The helper's changes | `homelab-model-helper.socket` (`SocketGroup=homelab-model`), `homelab-model-helper@.service.d/runtime.conf` (`RuntimeMaxSec=270`) |
| Installers | `scripts/server/install-model-helper.sh group` (ADR-048, runs first), `scripts/server/install-homelab-harness.sh install\|verify\|uninstall` |
| Notifier | `homelab-notify.sh` — `harness)` alias |
| The adapter | `factory` @ `9986188`: `workbench/adapters/homelab.py`, `adapters/select.py`, the `adapter` key, `Engine.run` + `cli run <item>`, `acceptance/second_adapter_check.py` |
| Runbooks | [`s2-runbook.md`](s2-runbook.md) (+ `s2-step6.sh`), [`s3-runbook.md`](s3-runbook.md), [`s4-runbook.md`](s4-runbook.md) |

### The request, in one screen

`POST /v1/request`, header `X-Homelab-Client: <label>`, body: `v` (1), `kind` (declared: `question` |
`task` | `command`, optional), `role` (**required** — never defaulted onto the owner's route),
`question`, `context` (list of `{text, source}`), `capabilities`, `unattended`, `summary`, and the
hints `priority` / `severity` / `complexity`. Closed set; anything else refused by name. **Set by
the runtime, refused if the body tries:** `client`, `user`, `user_id`, `origin`, `peer`, `identity`,
`request_id`, `ts` → `identity_in_body`. The full table, who sets each field, the eleven refusal kinds
with the condition that produces each, and what reaches the helper are in
[`services/homelab-harness/README.md`](../../services/homelab-harness/README.md) §1–2.

### The taxonomy — classify by hand

Rules in order, first match wins (`classify.py`):

| # | Rule | Class |
|---|---|---|
| C1 | `kind` declared `command` | `command` |
| C2 | text starts with `/word` | `command` |
| T1 | `kind` declared `task` | `task` |
| T2 | `capabilities` non-empty | `task` |
| T3 | first word is an imperative (implement, refactor, fix, deploy, install, migrate, commit, push, merge, delete, remove, rename, create, build, edit, modify, configure, run, execute, write, add, update, rewrite) | `task` |
| T4 | two or more step-shaped lines | `task` |
| Q0 | `kind` declared `question` | `question` |
| Q1 | first word is a question word (what, why, how, …, explain, describe, summarise, compare, define, tell, list, translate) | `question` |
| Q2 | ends with `?` | `question` |
| U | nothing matched | `unclassifiable` |

| Request | Class → outcome |
|---|---|
| "What is a systemd socket unit?" · no kind | Q1 → served |
| "the weather in Berlin tomorrow" · `question` | Q0 → served |
| "the weather in Berlin tomorrow" · no kind | **U → refused `unclassifiable`** |
| "Refactor the parser to stream tokens." · `question` | T3 → refused `needs_decomposition` (the declaration does not rescue work) |
| "Compare the two adapters" · `repository-read` capability | T2 → refused `needs_decomposition` |
| "Please:\n1. open the file\n2. change the port" | T4 → refused `needs_decomposition` |
| "/restart ssh.service" | **C2 → refused `not_a_request`** (the bot owns verbs) |
| "Berlin has a capital?" | Q2 → served |

Only `question` is served in 23.0. `task` is the seam for 23.1: work-shaped instructions are refused
until decomposition exists. The classifier is **not a security control** — it sanitises nothing; a
question containing a tool-shaped string reaches the model as text and comes back as text (the canary
in § Validation). Its rules are a short list a determined client can steer around; recorded as an
open risk.

### The audit line — and what it omits

One JSON line per request in `/var/lib/homelab-harness/audit.jsonl` (root, `0600`): `request_id`,
`ts`, `client_declared`, `peer` (`null` on loopback TCP — no peer credentials; recorded as null,
never guessed), `kind_declared`, `class`, `rule`, `role`, `unattended`, the three hints, `outcome`
(`ok` or a refusal kind), `stage` (`endpoint` | `helper`), `provider`, `model`, `cost` (always `null`
— unknown stays unknown, ADR-033), `duration_ms`, and **lengths only** for question, context,
summary, output. **Never** the question, context, summary, answer, or a refusal *message* (messages
echo client-chosen field names). The field set is fixed in `harness.py` `Audit.FIELDS`; `write()`
refuses any other key. The fixture proves it three ways on the file it wrote: exact key set, a closed
grammar for every string value (so no free-text field exists), and nine content strings absent.

**Read `client_declared` as a label.** Nothing authenticates it in 23.0. Identity, approvals and
budgets attach here in 23.3.

### The account/group boundary in plain language (ADR-048)

Before: the helper's socket was `aleix:homelab-bot 0660` — the bot's own group, so only the bot
could knock. Adding a second caller by putting it *in the bot's group* would make that group mean
two things and let the harness read the bot's files. So the socket got a group of its own,
`homelab-model`, whose single meaning is "may ask the helper". `getent group homelab-model` **is**
the access list: `homelab-bot,homelab-harness`. The next consumer is one membership and one `# WHY`.
Test 18 proves the boundary: `nobody` gets `EACCES`. The bot **had to be restarted** after the
`usermod` — a running process's groups are fixed at `exec` — and `install-model-helper.sh group` does
that; the brief's first S2 order missed it and was corrected.

### The adapter, and how it was proved (§8.1.3)

`workbench/adapters/homelab.py` is the same shape as the fake: `name`, `capabilities()` (none — the
endpoint executes nothing), `tools()` (none), `execute(Request) → Result`. It posts the `Request`
with `role = agent_role`, `question = task_summary + instructions`, `context` items with `source:
null` (Factory's context is plain strings), and maps Factory's priority vocabulary (`medium → normal`,
`urgent → critical`) to the endpoint's — the one translation. Every endpoint refusal kind becomes
`Result(refused=True, reason="<kind>: <message> [stage]")`; an unreachable endpoint becomes
`endpoint_unreachable`. `python3 -m workbench.cli run <TICKET>` is the smallest action that calls the
configured adapter: one call under `Budget(max_calls=1)`, a `run` record (existing type, existing
statuses `succeeded` | `refused` — no 94th status) holding the `Result`, linked from the item.

The check (`acceptance/second_adapter_check.py`): two scratch copies of `factory-ops`, one on `fake`,
one on `homelab`, the same fresh ticket (`TICKET-2026-9001`, agent `execution-agent`, a
question-shaped objective), `run` in both, every file under `ops/` and `agents/` compared with
timestamps, hashes and the scratch root normalised. **Allowed to differ:** the `Result` fields
(`output`, `model`, `cost`, `tokens`, `refused`, `reason`), the adapter's name, the `request_id`, and
the project's `adapter` key. **Residual after removing those: none** — locally against the stub and
on the node against the real helper. The diff is in the handover.

### Locked-volume behaviour

Locked: Workbench `inactive`, harness `active`; `/health`, `/health/helper` and a request all answer.
Locked **reboot**: harness `active` (pid 1381 — it came up before anything on the volume could),
Workbench `inactive` on its Condition (not `failed`), `--failed` empty, `is-system-running` →
`running`, the socket back as `aleix:homelab-model:660` from a fresh `/run`. Unlock → Workbench
`active`. The bot's `/status` does **not** report the volume (it never did — the brief's row 12
expected it and was corrected); the watchdog's boot notice does: `Data volume: LOCKED`.

### Rollback per stage

- **S2, ADR-048 alone:** previous socket unit (`…socket.bak-2026-09-13`) + `daemon-reload` + socket
  restart; `gpasswd -d homelab-bot homelab-model` + bot restart. `runtime.conf` is one `rm`.
  `config.json.bak-2026-09-13-p230`. `homelab-notify.sh.bak-2026-09-13`.
- **S2, the harness:** `install-homelab-harness.sh uninstall` — stops, disables, removes unit,
  drop-in, code, config, account; leaves `/var/lib/homelab-harness`.
- **S3:** `adapter` key back to `fake` (the scratch copies are throwaway anyway);
  `git -C /srv/homelab/factory checkout main` + Workbench restart.
- Nothing touched sshd, the firewall, Tailscale, the volume's encryption or the Workbench unit.

## Validation

Every row of the brief's §8 **OBSERVED** on 2026-09-13 except 19 (S4's backup, run at close). The
evidence lines, verbatim from the node, are in the handover; the shape:

| # | Row | Result |
|---|---|---|
| 1 | fixture | MacBook 64/64; **node 64/64 as `homelab-harness`**, stub CLIs, no spend |
| 2 | identity in body | `identity_in_body`, field named; helper journal empty |
| 3 | question, routed role | `ok`; audit line ids/lengths only; question grep → 0/0 |
| 4 | hints | same provider/model; hints in the helper's journal, selecting nothing |
| 5 | unknown role | `unknown_role [helper]`, message verbatim, no cap spent |
| 6, 7 | task; command; **canary** | `needs_decomposition`; `not_a_request`; the model returned exactly `/restart ssh.service` as text, `NRestarts 0 → 0` — ADR-025 §10 re-proved, not changed |
| 8, 9 | sockets; from the MacBook | **eight**, `127.0.0.1:8766` as uid 995; `curl` from the MacBook → timeout (ACL), from the node → refused (loopback) |
| 10, 18 | account; third account | `homelab-harness,homelab-model` only; `getent group` = `homelab-bot,homelab-harness`; `nobody` → `EACCES` |
| 11 | scores | harness **1.3** (the Workbench's findings + `~AF_UNIX 0.1`, with `# WHY`); helper 3.8 unchanged; `RuntimeMaxUSec 4min 30s` |
| 12 | locked; locked reboot | see above |
| 13 | start limit | six kills → seven alerts naming `homelab-harness.service` (one per crash + one for the refused restart), `Result=signal`, `NRestarts=6`; `reset-failed` recovers |
| 14 | `/ask` | before, after the group change, after the reboot — all answered; 15.0 fixture 19/19 on the node |
| 15, 16, 17 | factory | 55 tests on both adapters (MacBook and node); **"the adapter interface is proved"** locally and on the node; row 17's triple joined by `request_id 25342f79…` — run record, endpoint audit line, helper journal |
| 20 | `# WHY` | service 5, socket 2, drop-in 1 |

**Costs: five real model calls, 0 €** (four in S2, one in S3; subscriptions under the helper's caps).

## Security notes

- **The endpoint is the first service that accepts requests from another process.** Its account is
  the boundary; the blast radius of a compromise is "ask the helper as one capped consumer; write
  `audit.jsonl`". Score 1.3; `AF_UNIX` is the one waiver and it carries its `# WHY`.
- **`client` is a label.** Loopback is the trust boundary and every local process is trusted equally
  (ADR-038 §2). Do not read `client_declared` as authenticated.
- **Nothing new leaves the machine.** The endpoint forwards `question` and the client-selected
  `context` to the helper, which sends them to the same two CLIs as before. The audit file and the
  journal were grepped for the question and the answer: 0.
- **The `SocketGroup` change widened the helper's consumers by one account**, and made its caps a
  shared budget — the endpoint's calls count against the same `per_hour`/`per_day` as `/ask`.
  Observed in S2: with Claude's subscription limit reached, every call fell back to Codex and each
  refused Claude attempt still consumed a cap slot (the reservation is not released on `exhausted`).
- **The classifier is not a security control.** It refuses classes 23.0 cannot serve; the canary
  proves a tool-shaped answer is text.
- **`OnFailure=` pages once per crash**, so a crash loop is up to seven alerts in ~45 s before the
  start limit stops it. Recorded, not changed (a notifier concern).
- **No secret in either repository.** The endpoint has none to hold.

## Reference-build experience

What went wrong, in order, with what was learned (PROJECT.md §11):

1. **The brief said "hints through"; the code said otherwise.** Factory's `Request.priority` default
   `"medium"` is not in the helper's `priority` enum; without a mapping every default `Request` is
   refused. Found by reading `helper.py` against `adapters/__init__.py` in S1; the adapter maps. And
   the helper truncates `question` silently at its limit — the endpoint refuses instead, and the
   limit went to 4000 on both sides.
2. **The bot had to be restarted after the `usermod`.** Supplementary groups are fixed at `exec`;
   the brief's S2 order restarted only the socket. Corrected before S2 ran.
3. **Same-day `.bak` collision.** Phase 15.0's S2 had run the same morning; `config.json.bak-2026-09-13`
   existed and the edit refused, correctly, changing nothing. The date-only convention assumes one
   phase per day; a suffix (`-p230`) was used.
4. **`StateDirectory=` always adds `RequiresMountsFor=/var/lib/<name>`** — a root path. The installer
   asserted "empty" and failed on first run; the assertion is now "nothing under `/srv/homelab`".
5. **Five kills did not hit the start limit** — `StartLimitBurst=5` allows five *restarts*; the sixth
   is refused. Six kills did.
6. **Paste-wrapping and wrong-host pastes cost three retries** — a heredoc that never terminated
   because the terminator was indented; long `curl -d` lines split into two commands; two blocks
   pasted into the MacBook shell after the SSH session dropped with the reboot. No call was spent by
   any of them. Lessons now in the runbooks: anything wider than a terminal ships as a file
   (`s2-step6.sh`); every block after a reconnect starts with a hostname guard; edits are `python3 -c`,
   not heredocs.
7. **Two Workbench defects against legacy `factory-ops` records** blocked the §8.1.3 check twice:
   `update` on a slug-suffixed legacy file writes a second file with the same id (known since 18.2,
   item 5) and — new — `ids.next_id` ignores slug-suffixed stems and re-allocates a legacy id. Both
   make an update silently invisible. Worked around with a fresh ticket and an explicit id; not fixed;
   on the 18.2 finding.
8. **`Result` has no correlation field.** The endpoint's `request_id` reaches the Workbench's run
   record through `adapter.last_request_id` — a side door. That *is* the ADR-035 §4 finding the brief
   anticipated; the interface was not extended here (see the handover, to 23.3).
9. **The bot's `/status` has no volume line.** The brief expected one; corrected. The watchdog's
   boot notice is the LOCKED signal.
10. **Claude's subscription limit was reached mid-S2** — every call fell back to Codex, and row 4's
    "same provider/model" held through the fallback path. Correct behaviour, and the reason the
    reservation-not-released observation exists (to 15.1).

Timings: S1 design and local proof, one sitting; S2 on the node ~35 minutes including the reboot;
S3 local ~15 minutes, node ~5 minutes.

## Tested versions

Ubuntu Server 26.04.1, systemd 259, Python 3.14.4 on the node (3.13.5 on the MacBook), Claude Code
2.1.236, Codex CLI 0.153.4 (through the helper, unchanged), `factory` `9986188`, `factory-ops`
`66283c2` (read, never written — the check copies it).
