# Harness — the endpoint

The always-running, loopback-only service that accepts a request from any local client, attaches
where it came from, classifies it, forwards a `question` to the model helper and returns the answer
with a request id — layers 1, 2 and 9 of the target architecture. Phase 23.0.

It holds no credential, never names a model or provider, and keeps no content: results are the
client's to record, and the audit line is ids, labels, enums and lengths.

## Files

| File | Role |
|---|---|
| `harness.py` | Layer 1 (entry, validation, origin) and layer 9 (forwarding, audit, reply). `ThreadingHTTPServer` on `127.0.0.1:8766`, refused elsewhere in code |
| `classify.py` | Layer 2. The four-class taxonomy and its rules; the table in §3 is this file |
| `config.example.json` | Copy to `/etc/homelab-harness/config.json`. Bounds and paths; no secret |
| `fixture-tests.py` | Every refusal kind by attempt against a positive control; the helper's refusals surfaced; the audit file proved content-free. Drives the **real** `helper.py` behind a stub socket |

## 1. The request

`POST /v1/request`, body one JSON object, header `X-Homelab-Client: <label>`. Version 1. The field
set is **closed**: anything not in this table is refused by name.

| Field | Type | Who sets it | Required | Rule |
|---|---|---|---|---|
| `v` | int | client | yes | must be `1` |
| `kind` | `question` \| `task` \| `command` | client (a declaration) | no | absent means "classify from structure alone". `unclassifiable` cannot be declared — it is a verdict |
| `role` | string `^[a-z0-9][a-z0-9-]{0,31}$` | client | **yes** | the routing key, forwarded unchanged (ADR-034 §5). Required so the endpoint never defaults an agent's request onto the owner's route, which the helper would do for an absent role |
| `question` | string, non-empty, ≤ `max_question_chars` (500) | client | yes | the one thing that is asked. Over the limit is `too_large`, not truncated (the helper *would* truncate) |
| `context` | list of `{"text": str, "source": str\|null}`, ≤ 20 items, ≤ 2000 chars total | client | no | what the client **selected** (ADR-039 §2). `source` is the client's provenance (§3), carried as received. The endpoint adds nothing |
| `capabilities` | list of short names, ≤ 16 | client | no | carried for classification only (a request that names a capability is a `task`); **not** forwarded — the helper has no such field |
| `unattended` | bool | client | no, default `false` | forwarded; triggers the helper's eligibility filter and owner floor (ADR-026) |
| `summary` | string ≤ 200 | client | no | forwarded; the helper logs its length |
| `priority` | `low` \| `normal` \| `high` \| `critical` | client | no | hint. Forwarded, **never read** by the endpoint or the router |
| `severity` | `low` \| `medium` \| `high` \| `critical` | client | no | hint, as above |
| `complexity` | `low` \| `medium` \| `high` | client | no | hint, as above |

**Set by the runtime, never by the body** (ADR-034 §11): `request_id` (uuid4 hex, minted per
request), `ts` (UTC, ms), `client_declared` (the header's label — same grammar as `role`), `peer`
(peer credentials where the transport gives them; loopback TCP gives none → `null`). A body carrying
`client`, `user`, `user_id`, `origin`, `peer`, `identity`, `request_id` or `ts` is refused with kind
`identity_in_body` and the field named.

**`client` is a label, not an identity.** Nothing authenticates the header in 23.0; loopback is the
trust boundary and every local process is trusted equally (ADR-038 §2). The audit line calls the
field `client_declared` so nobody reads it as authenticated. Identity is 23.3's.

What reaches the helper (the 15.0 wire protocol), and only this:
`{"v":1,"op":"ask","user_id":"harness:<client_declared>","question":…,"context":<items rendered
to one string>,"role":…,"unattended":…,"summary":…,"priority":…,"severity":…,"complexity":…}`.
The context rendering is the one transform between the two protocols: each item's `text`,
preceded by `[source: …]` when a source was given, joined by blank lines. Nothing is added.

## 2. The response

Success:

```json
{"v": 1, "request_id": "…", "client_declared": "workbench", "ok": true,
 "class": "question", "text": "…", "provider": "…", "model": "…"}
```

`provider`/`model` are **what the helper reported**, echoed for the client's record (the adapter
fills `Result.model` from it). The endpoint did not choose them and has no field to.

Refusal:

```json
{"v": 1, "request_id": "…", "client_declared": "…", "ok": false,
 "kind": "<kind>", "message": "…", "stage": "endpoint" | "helper", "class": "…"}
```

`stage` says who refused. The kinds, the condition that produces each, and the HTTP status:

| Kind | Stage | Condition | HTTP |
|---|---|---|---|
| `bad_request` | endpoint | body not JSON; `v` ≠ 1; a field outside the table (named); a wrong type or enum value (named); missing `role` or `question`; missing or malformed `X-Homelab-Client`; wrong path; an internal error (journal has the trace, never the request) | 400 |
| `identity_in_body` | endpoint | any of `client`, `user`, `user_id`, `origin`, `peer`, `identity`, `request_id`, `ts` present in the body (named) | 400 |
| `too_large` | endpoint | body > `max_body_bytes` (before parsing); `question` > `max_question_chars`; too many or too long `context` items; too many `capabilities` | 413 |
| `needs_decomposition` | endpoint | class `task` (§3) — decomposition and tools are 23.1's | 422 |
| `not_a_request` | endpoint | class `command` (§3) — the bot owns operational verbs | 422 |
| `unclassifiable` | endpoint | class `unclassifiable` (§3) — declare `kind: question` if it is one | 422 |
| `helper_unavailable` | endpoint | the helper socket refused, is absent, timed out (280 s), closed without a reply, or answered out of protocol | 503 |
| `unknown_role` | helper | `role` is not in the helper's routes — the helper's message verbatim, no cap spent | 400 |
| `ineligible` | helper | `unattended: true` and no provider on the route may serve unattended calls | 422 |
| `exhausted` | helper | every provider on the route is capped or out of allowance; `detail` list carried verbatim | 429 |
| `error` | helper | the helper's own error (misconfigured, provider failure); message verbatim | 502 |

Endpoint-stage refusals never spawn a helper process — the fixture counts spawns.

`GET /health` answers `{"ok": true, "service": "homelab-harness", "v": 1}` without touching the
helper. `GET /health/helper` sends the helper `op: ping` (no model call) and reports
`reachable`/`unreachable` — the live proof that the harness account is in the socket's group.

## 3. The taxonomy (layer 2)

Four classes, exactly one per request, no model call. The rules run **in this order**; the first
match wins. Structural signals for `command` and `task` come **before** the declared `kind`, so a
client can resolve the ambiguous residue by declaring `question` but cannot relabel work as a
question.

| # | Rule | Class |
|---|---|---|
| C1 | `kind` declared `command` | `command` |
| C2 | text starts with `/word` (the bot's command shape) | `command` |
| T1 | `kind` declared `task` | `task` |
| T2 | `capabilities` non-empty | `task` |
| T3 | first word is an imperative from the list: implement, refactor, fix, deploy, install, migrate, commit, push, merge, delete, remove, rename, create, build, edit, modify, configure, run, execute, write, add, update, rewrite | `task` |
| T4 | two or more lines that look like steps (`1.`, `2)`, `-`, `*`) | `task` |
| Q0 | `kind` declared `question` | `question` |
| Q1 | first word is a question word: what, why, how, when, where, who, whom, whose, which, is, are, was, were, does, do, did, can, could, should, would, will, explain, describe, summarise, summarize, compare, define, tell, list, translate | `question` |
| Q2 | text ends with `?` | `question` |
| U | nothing matched | `unclassifiable` |

Worked examples — classify by hand, then check the last column:

| Request (text · declared kind · capabilities) | Walk | Class → outcome |
|---|---|---|
| "What is a systemd socket unit?" · — · — | C1 no, C2 no, T1–T4 no, Q0 no, **Q1** "what" | `question` → served |
| "the weather in Berlin tomorrow" · `question` · — | C/T no, **Q0** declared | `question` → served |
| "the weather in Berlin tomorrow" · — · — | C/T no, Q0 no, Q1 "the" no, Q2 no `?` → **U** | `unclassifiable` → refused `unclassifiable` |
| "Refactor the parser to stream tokens." · `question` · — | C no, T1 no, T2 no, **T3** "refactor" — the declaration does not rescue it | `task` → refused `needs_decomposition` |
| "Compare the two adapters" · — · `repository-read` | C no, T1 no, **T2** a capability is named | `task` → refused `needs_decomposition` |
| "Please:\n1. open the file\n2. change the port" · — · — | C no, T1–T3 no, **T4** two step lines | `task` → refused `needs_decomposition` |
| "/restart ssh.service" · — · — | C1 no, **C2** slash-word | `command` → refused `not_a_request` |
| "What is X" · `command` · — | **C1** declared | `command` → refused `not_a_request` |
| "Berlin has a capital?" · — · — | C/T no, Q0 no, Q1 "berlin" no, **Q2** ends `?` | `question` → served |
| "Explain the volume-dependent contract" · `task` · — | C no, **T1** declared | `task` → refused `needs_decomposition` |

Known steerable edges, recorded rather than hidden: a task phrased as a question ("How would you
refactor the parser?") is a `question` (Q1) and reaches the model as text — it gets an answer, not
work, which is the safe direction; "Write a haiku about sockets" is a `task` (T3) although it wants
an answer — declare nothing and rephrase, or accept the refusal. The classifier is **not a security
control**; it refuses what 23.0 cannot serve and sanitises nothing.

## 4. The audit line (layer 9)

One JSON object per request, appended to `$STATE_DIRECTORY/audit.jsonl` (`/var/lib/homelab-harness/`,
on root, `0600`). The field set is fixed in `harness.py` `Audit.FIELDS`; `write()` refuses any other
key, so an edit that tries to log a text field fails at the first request in the fixture.

| Field | Type / grammar | Source |
|---|---|---|
| `v` | `1` | runtime |
| `request_id` | 32 hex | runtime |
| `ts` | `YYYY-MM-DDTHH:MM:SS.mmmZ` | runtime |
| `client_declared` | label `^[a-z0-9][a-z0-9-]{0,31}$` | header — **declared, not authenticated** |
| `peer` | `null` on loopback TCP (no peer credentials; recorded as null, never guessed) | transport |
| `kind_declared` | `question` \| `task` \| `command` \| `null` | body |
| `class` | `question` \| `task` \| `command` \| `unclassifiable` | classifier |
| `rule` | `C1` \| `C2` \| `T1`–`T4` \| `Q0`–`Q2` \| `U` | classifier — *why* that class, without quoting the request |
| `role` | label | body |
| `unattended` | bool | body |
| `priority`, `severity`, `complexity` | closed enums or `null` | body |
| `outcome` | `ok` or a refusal kind from §2 | endpoint |
| `stage` | `endpoint` \| `helper` \| `null` (on `ok`) | endpoint |
| `provider`, `model` | labels as the helper reported them, or `null` | helper |
| `cost` | always `null` — subscriptions report none; unknown stays unknown (ADR-033) | — |
| `duration_ms` | int | runtime |
| `question_len`, `context_len`, `summary_len`, `output_len` | int (chars) | lengths only |
| `context_items`, `capabilities_n` | int | counts only |

**Never present:** the question, any context text or source, the summary, the answer, or a refusal
*message* (messages can echo a client-chosen field name). `fixture-tests.py` proves it three ways on
the file it wrote: every line has exactly these keys; every string value matches its closed grammar
(so no free-text field exists); and none of the nine content strings the fixture sent — question,
context, source, summary, answer, two refusal-message fragments — appears anywhere in the file.

The journal (`journalctl -u homelab-harness`) carries one line per request with the same
non-content fields; it is not the audit record, `audit.jsonl` is.

## 5. Running the fixture

```bash
python3 services/homelab-harness/fixture-tests.py       # MacBook: finds ../model-helper/helper.py
HOMELAB_HELPER_DIR=/opt/homelab-model-helper python3 /opt/homelab-harness/fixture-tests.py   # node
```

No CLI is touched and no allowance is spent: the helper's providers are a stub script, and the
harness runs in-process on an ephemeral port. 64 checks; every refusal kind next to its control.
