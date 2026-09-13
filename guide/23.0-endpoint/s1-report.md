# Phase 23.0 — S1 report: design, schema, local proof

- **Stage:** S1 of four (brief §7.1). No node change, no factory change.
- **Branch:** `phase/23.0-work` in the `homelab-p230` worktree; `main` at `9b6db12` + this stage's commits.
- **Written:** 2026-09-13, for the orchestrator's review before S2.
- **Claim discipline:** every claim below is tagged **OBSERVED** (run here, output seen) or
  **PREDICTED** (reasoned from code or documentation; to be observed on the node).

## 1. What was delivered, against the brief's list

| Brief item | Where | State |
|---|---|---|
| (a) request/response schema, closed set, version, refusal kinds with conditions | `services/homelab-harness/README.md` §1–2; `harness.py` `REQUEST_FIELDS`, `IDENTITY_FIELDS`, `ENDPOINT_KINDS`, `HELPER_KINDS` | done |
| (b) taxonomy table, ≥ 6 worked examples incl. one unclassifiable and one command | `README.md` §3 (ten examples); `classify.py` docstring is the same table | done; the fixture re-classifies all ten by hand (OBSERVED) |
| (c) audit line schema + the assertion that no content reaches it | `README.md` §4; `harness.py` `Audit.FIELDS`; `fixture-tests.py` final block | done; three assertions on the file (OBSERVED) |
| (d) `services/homelab-harness/` with fixture driven against a stub helper socket | `harness.py`, `classify.py`, `config.example.json`, `README.md`, `fixture-tests.py` | **64/64 OBSERVED** on the MacBook (Python 3.13.5) |
| (e) unit + `onfailure.conf`, helper `SocketGroup` change, `RuntimeMaxSec` drop-in, installer with verify and uninstall | `config/systemd/homelab-harness.service`, `…/homelab-harness.service.d/onfailure.conf`, `homelab-model-helper.socket`, `homelab-model-helper@.service.d/runtime.conf`, `scripts/server/install-homelab-harness.sh`, `install-model-helper.sh` (`group` subcommand), `homelab-notify.sh` (`harness)`) | written, not installed; `bash -n` clean (OBSERVED); `systemd-analyze verify` PREDICTED (no systemd here) |
| (f) ADR-048 | `docs/decisions/ADR-048-model-socket-consumers-group.md` + README row; number confirmed against `docs/decisions/README.md` (last was 047) | Proposed |
| (g) §6.1–6.10 resolutions | §3 below | done |
| (h) this report | this file | — |

Commits, in order: `df3358a` (service + fixture), `272296e` (units, installers, notifier),
`ed8fed8` (ADR-048), `40f6372` (brief corrections + README), and the report's own commit.

## 2. The fixture: what it proves and how (OBSERVED)

The stub is a real `AF_UNIX` listener that, per connection, spawns **the real `helper.py`** with the
connection as stdin/stdout — what systemd's `Accept=yes` does — against a fixture config derived
from `services/model-helper/config.example.json` (shape-asserted, 15.0 discipline) with a stub CLI.
So `unknown_role`, `ineligible` and `exhausted` below are the helper's own refusals, not imitations.
The endpoint runs in-process on an ephemeral loopback port from the same `harness.py` the unit runs.

| Refusal kind | Triggered by | Positive control | Helper spawned? |
|---|---|---|---|
| `identity_in_body` ×8 | `client`, `user`, `user_id`, `origin`, `request_id`, `peer`, `identity`, `ts` in the body — each **named** in the message | the same request without the field (test 3) | no (0 spawns) |
| `bad_request` (unknown field) ×5 | `model`, `provider`, `bin`, `path`, `route` — each named | test 3 | no |
| `bad_request` (shape) ×8 | no header; header outside grammar; no `role`; `v: 2`; not JSON; `kind: unclassifiable`; context item with `path`; `unattended: "yes"`; `priority: medium` | test 3 | no |
| `too_large` ×3 | question 501 chars; 21 context items; body 16385 bytes | question 500 chars → ok; 20 items → ok | no |
| `needs_decomposition` ×5 | T1 declared task; T2 capability named; T3 "Refactor …"; T4 numbered steps — all **despite `kind: question`** on T2–T4 | same text as question where applicable | no |
| `not_a_request` ×2 | C1 declared command; C2 `/restart ssh.service` | — | no |
| `unclassifiable` | "the weather in Berlin tomorrow", no kind | same text with `kind: question` → ok (Q0) | no |
| `unknown_role` (stage=helper) | `role: no-such-role` | routed role → ok | **yes**, helper journal `outcome=unknown_role`, no cap spent |
| `ineligible` (stage=helper) | `unattended: true` vs providers `unattended: false` | same vs `unattended: true` → ok | yes |
| `exhausted` (stage=helper) | `unattended: true` with reserve = caps (budget 0); `detail` list verbatim | same not unattended → ok from the reserve | yes |
| `helper_unavailable` ×2 | helper answers non-JSON; socket path absent (errno 2) | helper back → ok | no / no |

Positive control (test 3): `ok`, `text: STUB-ANSWER`, helper journal line
`ask user=harness:fixture-client route=fixture-role … outcome=ok`; audit line has the request id,
`question_len=35`, `context_items=1`, `output_len=11`, `cost=null`, `peer=null`. Test 4: hints
`priority=critical severity=critical complexity=high` appear in the helper journal, provider/model
identical to the plain request.

Audit file, 48 lines for 48 POSTs: every line has exactly `Audit.FIELDS` in order; every string
value matches its closed grammar (no free-text field exists); none of nine content strings appears.
`grep -iE 'claude|codex|haiku|gpt-|openai|anthropic'` over `harness.py`, `classify.py`,
`config.example.json` → 0 hits.

## 3. Resolutions of §6.1–6.10

| § | Recommendation | Resolution | Reason |
|---|---|---|---|
| 6.1 | (c) `homelab-model` group, ADR-048 | **Accepted.** | Minimal; keeps ADR-025's mechanism; `getent group` is the access list. Alternatives 3–5 in the ADR. **One addition (OBSERVED in the nature of Unix, PREDICTED on the node):** the bot must be restarted after the `usermod` — supplementary groups are fixed at `exec`. `install-model-helper.sh group` does both restarts; the brief's §7.2 was corrected (`40f6372`). |
| 6.2 | `homelab-harness` account, `ThreadingHTTPServer`, `127.0.0.1:8766`, `StateDirectory`, `AF_UNIX` with `# WHY`, no `LoadCredential=` | **Accepted as written.** | Unit at `config/systemd/homelab-harness.service`. Score PREDICTED 1.3 (the Workbench's set + `AF_UNIX`, which the analyser does not penalise alone). `After=network.target homelab-model-helper.socket` added as ordering only, never a requirement — the endpoint answers `helper_unavailable` when the socket is down. |
| 6.3 | state on root = `audit.jsonl` only; results are the client's | **Accepted.** | `Audit.FIELDS` is the whole of what is persisted; content cannot be added without failing the fixture. `RequiresMountsFor=` holds only `/var/lib/homelab-harness` (root) — the installer asserts nothing under `/srv/homelab` after `daemon-reload`. |
| 6.4 | four classes, declared kind + structural rules, no model call | **Accepted, with one design choice made explicit:** structural `command`/`task` signals are checked *before* the declared kind. | The declaration can lift `unclassifiable` to `question` but cannot relabel work as a question — ADR-034 §11's "an agent's statement about its work is data". Cost: a Workbench item whose instructions begin with an imperative (`Refactor …`) is refused `needs_decomposition` even though the adapter declares `question`. That is the honest 23.0 answer (the request *is* work) and it is what the §8.1.3 item's instructions must be written around — open question 3. |
| 6.5 | the audit field list | **Accepted, extended by five non-content fields:** `rule` (which classifier rule fired), `stage` (who refused), `context_len`, `summary_len`, `capabilities_n`. | All closed grammars or integers; the fixture's grammar assertion covers them. Refusal *messages* are excluded on purpose — they can echo a client-chosen field name. |
| 6.6 | adapter mapping, one `adapter` key, `run <item>` CLI, no dashboard button | **Accepted for S3, with two corrections to "hints through" (brief edited, `40f6372`):** `Request.priority` default `"medium"` ∉ helper enum → adapter maps `medium → normal`; the helper truncates `question` at 500 silently → the endpoint refuses `too_large` at the same limit, and the adapter must surface that as `Result(refused=True, reason=…)`. | OBSERVED in `factory/workbench/adapters/__init__.py` and `helper.py`. Neither requires a change to `Request`/`Result`. |
| 6.7 | defer the Telegram client | **Accepted.** | Unchanged reasoning; `/ask` is the recovery path with the volume locked, and ADR-048 makes the caps a shared budget — one more reason not to put the owner's path behind the new consumer. |
| 6.8 | one route per exercised role; no wildcard | **Accepted.** The fixture adds exactly one route (`fixture-role`) after the shape check, to the same list as `owner-interactive`. | S2 adds the role(s) the §8.1.3 item uses to the node's `config.json` with `.bak-<date>`. Open question 2 asks which. |
| 6.9 | `RuntimeMaxSec=270`, client timeout 280 | **Accepted.** | `homelab-model-helper@.service.d/runtime.conf` with `# WHY`; `helper_timeout_seconds: 280` in the endpoint's config. Proved by the 15.0 fixture staying 19/19 (S2), not a real double timeout. |
| 6.10 | no identity fields in the schema; `client` from a header as a label | **Accepted.** | Eight identity names refused with their own kind; header `X-Homelab-Client`, recorded as `client_declared`, grammar `KEY_RE`. README §1 says in plain words it is a label. |

## 4. Findings (not fixes) — for the handover and, where marked, for the orchestrator

1. **`Request.priority` default is outside the helper's enum** (OBSERVED, code). `"medium"` vs
   `low|normal|high|critical`. The adapter maps; `Request` is not changed. Whether the mismatch is a
   *finding about ADR-035 §4* (a backend enum leaking into the interface's defaults) or merely an
   adapter concern is the orchestrator's call — I read it as the latter: the interface carries a
   hint in its own vocabulary and the adapter translates, which is what adapters are for.
2. **The helper truncates `question` silently at `max_question_chars`** (OBSERVED, `helper.py`
   `handle_ask`: `question.strip()[:max_q]`). A Workbench item's `task_summary + instructions` over
   500 chars would be cut without notice. The endpoint refuses instead; the two limits must be kept
   equal by hand (both configs say so). **Orchestrator:** raise both to a larger value in S2's
   config change (the helper's is a root-owned config edit with `.bak`), or accept 500 for 23.0?
3. **`context` is a string in the helper, a list of `{text, source}` items at the endpoint.** The
   endpoint renders items to one string (the *only* transform; nothing added). The helper caps
   `context` at 2000 chars by truncation too (`context[:2000]`) — the endpoint's `max_context_chars`
   matches. Factory's `Request.context` is `tuple[str, ...]` with **no provenance**, so today every
   item will arrive with `source: null`. Recorded for 23.2.
4. **`user_id` on the wire is now a string** (`harness:<client_declared>`). The helper logs it and
   never validates it (OBSERVED, `handle_ask`); the bot sends an int. Harmless, and it makes the
   helper's journal say which consumer asked. Noted so nobody later reads `user=` as a Telegram id.
5. **`install-model-helper.sh verify` had to change** (`check_socket_permissions`,
   `check_bot_groups_unchanged`, new `check_model_group`) — the Phase 09 "unchanged" item is
   superseded by ADR-048's "exactly these two". The old expectation is kept as a *named* failure
   ("Phase 09 state — run `group`") so a half-applied S2 is diagnosed, not mis-read.
6. **`Request.capabilities` reaches the endpoint and is used for one thing:** a non-empty list is a
   `task`. It is not forwarded (the helper would refuse the field). This is the "carried and
   ignored" the brief §16 predicts for Phase 19; the honest wording is "carried and used only to
   refuse".
7. **The bot's `check_bot_can_reach_socket` probe runs under `systemd-run --uid=homelab-bot`.**
   PREDICTED: systemd initialises supplementary groups from NSS for `User=`, so the probe will
   connect after the group change. If S2 shows `errno=13` there, the fix is `--property=SupplementaryGroups=homelab-model` on the probe, not a change to the boundary.

## 5. What S2 will observe (from this stage's PREDICTED list)

- `systemd-analyze verify` accepts `homelab-harness.service` and the two drop-ins.
- `systemd-analyze security homelab-harness.service` ≤ 2.0 (PREDICTED 1.3).
- `systemctl show -p RequiresMountsFor --value homelab-harness.service` → empty. **Wrong: OBSERVED `/var/lib/homelab-harness`** — `StateDirectory=` always adds its own path; what matters is that nothing under `/srv/homelab` appears. The installer's check was corrected in S2.
- `systemctl show -p RuntimeMaxUSec homelab-model-helper@probe.service` → `4min 30s`.
- After `install-model-helper.sh group`: socket `aleix:homelab-model:660`; `id homelab-bot` →
  `homelab-bot homelab-model`; `/ask` works; 15.0 fixture 19/19 as `aleix`.
- After `install-homelab-harness.sh install`: `GET /health/helper` → `reachable` (the group
  membership, live, as the harness inside its sandbox); `sudo -u nobody` probe → `errno=13`; the
  23.0 fixture 64/64 as `homelab-harness`; `ss -tlnp` shows eight.
- Locked-volume behaviour (row 12): the unit has no volume directive at all, so PREDICTED it starts
  on a locked boot and answers; the Workbench stays inactive on its Condition.

## 6. Open questions for the orchestrator

1. **`role` is required** at the endpoint (refused `bad_request` if absent) so an agent's request is
   never defaulted onto `owner-interactive`. The helper would default it. Agree, or should the
   endpoint pass an absent role through and let the helper's `default_route` apply?
2. **Which role(s) get a route in S2's `config.json`?** The §8.1.3 item needs one Factory role from
   `factory/agents/roles/`; I propose the one the scratch project already assigns (S3 reads it) and
   nothing else, per §6.8. If the item has no assigned agent, name one now so S2 and S3 agree.
3. **The classifier refuses imperative instructions even when the adapter declares `question`**
   (§6.4 resolution). For the §8.1.3 check the item's instructions must therefore read as a question
   ("What would a streaming parser for X look like?"), not as work. Accept that the first real
   `run` is a question-shaped item, or soften T3 to apply only when no kind is declared? I recommend
   accepting — softening makes `kind: question` a way to get work past layer 2.
4. **Question length** (finding 2): raise `max_question_chars` on both sides in S2, and to what?
   `Request.instructions` in a real item is unlikely to fit 500 chars.
5. **`GET /health/helper` spawns a helper process per call** (it is `op: ping`, no model call, no
   cap). `verify` uses it once. Acceptable as a permanent path, or restrict it after S2?
6. **HTTP status for `unknown_role`** is 400 (the client named a role that is not routed — its
   mistake). Alternative: 422 like the other classification-type refusals. Cosmetic; the adapter
   reads `kind`.
7. **The stage report as a committed file** (`guide/23.0-endpoint/s1-report.md`) rather than chat
   only — S4's guide will absorb it. Object if the guide directory should stay empty until S4.

## 7. Nothing touched

sshd, the firewall, Tailscale, the volume, `factory`, the node. `Request`/`Result` unchanged.
No secret in any file. Costs: 0 (no CLI was invoked; the stub answered every call).
