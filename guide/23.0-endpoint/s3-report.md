# Phase 23.0 — S3 report: the second adapter

- **Stage:** S3 of four (brief §7.3). `factory` changed on branch `phase/23.0-adapter`; the node's
  clone checked out to it; nothing under `/etc` changed.
- **Run:** 2026-09-13, local half 11:20–11:35 UTC, node half 11:45–11:50 UTC.
- **Every claim OBSERVED** unless marked.

## 1. Factory commits (branch `phase/23.0-adapter`, from `main` @ `2e82f51`; pushed, not merged)

| Hash | What |
|---|---|
| `5622c30` | `workbench/adapters/homelab.py`; `adapters/select.py`; `project.py` (`adapter` key, default `fake`); `Engine.run` + `cli run <item>`; 14 tests (55 total) |
| `9986188` | `acceptance/second_adapter_check.py` — the §8.1.3 check |

`Request` and `Result` are unchanged. The absent-field test is unchanged and passes.

## 2. The §8.1.3 check — "the adapter interface is proved"

Run twice, same script, same objective, same agent (`execution-agent`), a fresh ticket
`TICKET-2026-9001` in each scratch copy of `factory-ops`:

| Where | Endpoint | Helper | Verdict | Evidence |
|---|---|---|---|---|
| MacBook | `dev-stub.py` — real `harness.py` on 8766 | real `helper.py`, stub CLIs | **proved** | `s3-8.1.3-local.txt` |
| Node | the live `homelab-harness.service` | real, one real call | **proved** | the owner's paste, §3 |

Differences, both runs, after normalising timestamps, hashes and the scratch root:
`ops/audit/audit.jsonl` — `detail.backend`, `detail.model` on the `activate_agent` and `execute`
entries; `ops/project.json` — `adapter`; `ops/runs/RUN-2026-0001.json` — `adapter`, `request_id`,
`model`, `output`. Residual after removing the fields the adapter may fill: **none**. Every other
byte — the ticket, the task, the roster, the 23 legacy tickets, the item's `run_ids` — identical.

## 3. Row 17 — the triple, node, request id `25342f79da894185bc98ddf63dca2280`

- **Run record** (`/tmp/second-adapter-v0ixuo1n/homelab/ops/runs/RUN-2026-0001.json`): `status
  succeeded`, `adapter homelab`, `model haiku`, `cost null`, `output` = a real 288-char answer
  ("A socket unit manages a socket … rather than running continuously."), `budget 1/1 used,
  cost_is_complete false`. The ticket's `run_ids` lists it.
- **Endpoint audit line** (`/var/lib/homelab-harness/audit.jsonl`): `client_declared workbench`,
  `kind_declared question`, `class question`, `rule Q0`, `role execution-agent`, `priority normal`
  (mapped from the ticket's `medium`), `complexity medium`, `outcome ok`, `provider claude`, `model
  haiku`, `duration_ms 6614`, `question_len 115`, `output_len 288`. Question grep → 0.
- **Helper journal**: `ask user=harness:workbench route=execution-agent unattended=false
  priority=normal complexity=medium summary_len=0 provider=claude model=haiku qlen=115 took=6.5s
  outcome=ok claude: 6/6 this hour`.
- Workbench audit `execute` entry: `backend homelab`, `model haiku`, budget — **no request id**
  (finding 1); the join is endpoint audit line ↔ run record.
- Rows 15 (tests on both adapters, node: `Ran 55 tests … OK`), 16 (the diff) and 17: OBSERVED.
- Node state: Workbench restarted on the branch (`active`, dashboard 200); `--failed` empty; `running`.

**Costs:** one real call (Claude answered; it was the hour's last Claude slot). 0 €.

## 4. Findings — decided by the orchestrator, recorded here for the handover

1. **`Result` has no correlation field** — the ADR-035 §4 finding. `adapter.last_request_id` is the
   leak in disguise: a backend-specific concept reached the Workbench through a side door instead of
   the interface. No ADR in this phase (`Request`/`Result` did not change, so ADR-035 §4 stands as
   written). **To 23.3 by name:** correlation is audit machinery, and the interface will need one
   field for it — decided there, with the ADR-035 amendment. Not added here.
2. **Two Workbench defects against legacy `factory-ops` records** — items on the open 18.2 finding:
   (a) `update` on a slug-suffixed legacy file (`TICKET-2026-0002-core-agent-specs.yaml`) writes
   `TICKET-2026-0002.yaml` beside it (`records.path_for` derives the path from the id alone) and
   `find` returns the legacy file — the update is silently invisible; (b) `ids.next_id` matches
   stems against `^PREFIX-YEAR-SEQ$`, so legacy stems are invisible and it re-allocates
   `TICKET-2026-0001`. Workaround used by the check: a fresh ticket with an explicit id
   (`TICKET-2026-9001`). Not fixed.
3. **No JSON agent manifests in Factory** — roles are prose; `run` uses the roster name as the role
   key. **The Workbench audits absolute paths** (`detail.path`). To 19 and 23.1; no action.
4. **The `homelab` adapter advertises no capabilities.** A roster-name agent has none, so activation
   passes; any agent declaring one is refused at activation. `Request.capabilities` reaches the
   endpoint and is used only to refuse (`T2`). To 19.
5. **Context is empty from `run`.** Nothing on a ticket is *selected content*; the endpoint's
   `context_items 0`. To 23.2.
6. **Runbook:** one wrong expectation (the question is on the ticket, the answer on the run —
   grep on the run record for the question is correctly 0). Corrected.

## 5. State for S4

- Node: harness live; factory clone on `phase/23.0-adapter` @ `9986188`; Workbench running from it.
  Scratch copies under `/tmp/second-adapter-v0ixuo1n` (clear at boot; `rm -rf` when done).
- Claude cap at 6/6 for the hour of 11:47 UTC; nothing else to spend in S4 (closing check makes no call).
- ADR-048: rows 10, 14, 18 OBSERVED → Accepted at S4.
- The old Phase 23 brief's header gains its one line; `current-architecture.md` socket table → eight.
