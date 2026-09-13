# Phase 15.0 — Model registry and routing

**Status:** draft — §Design written in stage 1 (2026-09-13), before any code or node change. The
remaining sections are written as the phase runs. Brief:
[`docs/handovers/15.0-model-registry.md`](../../docs/handovers/15.0-model-registry.md).

## What we are trying to achieve

Today the model helper knows exactly two models, one per provider, both hardcoded in
`config.json` as `{"bin": ..., "model": ...}`. The bot cannot name a model — good — but nobody can
add one without a redesign, and nothing distinguishes a call the owner just asked for from a call
a scheduled job might make at 3 a.m. against the owner's own subscription.

This phase turns the two hardcoded entries into a **registry**: providers, models beneath them, and
a **routes** table that maps a *routing key* to an ordered list of `provider/model` pairs. It adds
one eligibility rule — `unattended` on the provider, refused before the call — and one budget rule
— a floor of calls reserved for the owner that unattended work cannot spend. It changes nothing the
owner sees from Telegram.

## Design

### The registry — `config.example.json`

```json
{
  "providers": {
    "claude": {
      "bin": "/home/aleix/.local/bin/claude",
      "unattended": true,
      "models": {
        "haiku": { "id": "haiku", "note": "cheapest tier on Claude Pro" }
      }
    },
    "codex": {
      "bin": "/home/aleix/.local/bin/codex",
      "unattended": true,
      "models": {
        "mini": { "id": "gpt-5.6-luna", "note": "the subscription's mini tier" }
      }
    }
  },

  "routes": {
    "owner-interactive": ["claude/haiku", "codex/mini"]
  },
  "default_route": "owner-interactive",

  "caps": {
    "per_hour": 6,
    "per_day": 30,
    "owner_reserve": { "per_hour": 3, "per_day": 15 }
  },

  "state_file": "/var/lib/homelab-model-helper/calls.json",
  "timeout_seconds": 120,
  "max_question_chars": 500,
  "max_answer_chars": 3000
}
```

Reading it top down:

| Level | Key | Meaning |
|---|---|---|
| provider | *(its name)* | Must be one of the implementations in `providers.py` (`BY_NAME`). Adding a provider is code; that is deliberate (ADR-026 §2) |
| provider | `bin` | Absolute path to the CLI. Root-owned config; never on the wire |
| provider | `unattended` | **Required**, boolean. Whether this provider may serve a call nobody asked for in person. Eligibility sits here, not on the model: a model has no terms of service, a subscription does |
| provider | `metered` | Optional, **unset today**. Reserved for 15.1. If set `true`, the helper refuses to load — the governor does not exist yet (ADR-033 §5) and a field that is silently ignored is a trap |
| provider | `credential` | Optional, **unset today**. Reserved for 15.1: a *name* resolved through `LoadCredential=`, never a path. If present, the helper refuses to load for the same reason |
| model | *(its key)* | The name routes use, e.g. `haiku`, `mini`. A registry-level alias |
| model | `id` | The string the CLI actually receives (`--model haiku`, `-m gpt-5.6-luna`). Only this level ever reaches argv, and only from here |
| model | `note` | Documentation; never read by code |
| routes | *(key)* | The **routing key**. Its value in the agent world is the agent's role (ADR-034 §5); today there is exactly one, the bot's |
| routes | value | Ordered `provider/model` pairs. The order is the fallback order — the same rule Phase 09's provider list expressed |
| `default_route` | | Which route a request with no key gets. Must name a route |
| `caps.owner_reserve` | | The floor (§6.6). Unattended calls may reach at most `per_x − owner_reserve.per_x` in each window, per provider; the remainder is the owner's |

Every route entry is validated at load: the provider exists, the model key exists under it. The
Phase 09 shape (`"providers": [...]`) is **refused** with a config error, not migrated silently —
the runbook migrates the file, with a `.bak-<date>`.

### The wire protocol — what changes in `ask`

The Phase 09 request still works unchanged:

```json
{"v": 1, "op": "ask", "user_id": 123, "question": "...", "context": "..."}
```

Six optional fields are added. Every one has a safe default, and every one is validated for shape
before anything else happens:

| Field | Type / allowed values | Default | What it does |
|---|---|---|---|
| `role` | string, `^[a-z0-9][a-z0-9-]{0,31}$` | absent → `default_route` | **The routing key.** The only field that selects anything. Unknown → refused |
| `unattended` | boolean | `false` | Declares the call was not initiated by a person. Opt-in to the *restricted* path |
| `summary` | string ≤ 200 chars | absent | ADR-034's bounded task summary. Logged as its **length**, never its text (the journal is not the place for the caller's prose — Phase 09's rule for the question) |
| `priority` | `low` `normal` `high` `critical` | absent | Hint. Logged. Never selects |
| `severity` | `low` `medium` `high` `critical` | absent | Hint. Logged. Never selects |
| `complexity` | `low` `medium` `high` | absent | Hint. Logged. Never selects |

**Any other top-level field is refused** — `{"ok": false, "kind": "error", "message": "unknown
field 'model'"}` — with the field named. Phase 09 ignored unknown fields; this phase rejects them,
because the wire protocol is exactly where the "caller cannot name a program" property would be
lost by accident, and a rejected field is louder than an ignored one (test 8).

A hint outside its enum is a bad request (`kind: "error"`, message naming the hint), not a value to
be coerced. The bot sends none of the six fields.

**The one function where the route is chosen** is `resolve_route(cfg, key)` in `helper.py`. It
receives the config and **the key alone** — a string or `None` — and returns the route name and its
ordered list. `unattended`, the hints and the summary are validated and logged in `handle_ask` and
never passed to it. A reviewer looking for "can a hint pick a model" reads that one signature.

### Order of checks — refusals before reservations

`handle_ask` runs in this order; each step can refuse, and a refusal at steps 1–3 costs nothing
because the cap reservation is step 4:

1. **Shape.** Question present, context a string, no unknown fields, hints in their enums.
2. **Route.** `resolve_route(cfg, role)`. Unknown key → refused.
3. **Eligibility.** If `unattended`, drop every entry whose provider is `unattended: false`. If
   nothing is left → refused. (If some are left, the ineligible ones are logged and skipped.)
4. **Cap reservation** (`Limiter.check_and_reserve(provider, unattended=…)`), then the call, then
   fallback along the route's remaining entries — the Phase 09 loop.

The three refusals are distinguishable on the wire and in the journal:

| Situation | Wire | Journal (`stderr`) |
|---|---|---|
| Unknown key | `{"ok": false, "kind": "unknown_role", "message": "no route for role 'x'"}` | `ask user=U key=x outcome=unknown_role` |
| No eligible provider | `{"ok": false, "kind": "ineligible", "message": "no provider on route 'owner-interactive' may serve unattended calls"}` | `ask user=U route=owner-interactive unattended=true outcome=ineligible providers=claude,codex` |
| All eligible providers capped/exhausted | `{"ok": false, "kind": "exhausted", "message": "no provider could answer", "detail": [...]}` — unchanged; each `detail` line says whether it was the hourly cap, the daily cap, the **owner reserve**, or the CLI's own limit | `… outcome=capped` per provider, as today |

The successful line gains the route and the hints:

```text
ask user=U route=owner-interactive unattended=false priority=critical complexity=high summary_len=9 provider=claude model=haiku qlen=16 took=1.2s outcome=ok claude: 1/6 this hour
```

Test 11 is: that line with the hints and the same line without them name the same
`provider=… model=…`.

### The unattended budget — a floor, not a lower cap

`Limiter` keeps its file, its lock and its stamp format (a list of timestamps per provider — no
state migration). It gains one argument: `unattended`. When set, the ceiling in each window is
`per_x − owner_reserve.per_x` instead of `per_x`; the count is the same shared count. So with
`30/day, reserve 15`: unattended work stops at 20 calls in the day *however they were spent*, and
the owner always has at least 15 unless they spent them. A refusal says which limit it hit
(`claude: unattended daily budget reached (15/15, 15 reserved for the owner)`), so the owner can
tell a stuck scheduler from their own afternoon.

### The fixture — how the refusal is proved

`services/model-helper/fixture-tests.py`. It does not touch a CLI, a socket or the node:

- the two binaries are a **stub** shell script that prints `STUB-ANSWER` (and honours codex's
  `-o FILE`), so the "call" goes through the real `ClaudeProvider`/`CodexProvider` argv-building and
  answer-reading code;
- the fixture config is **`config.example.json` with three substitutions** — the binaries, the
  state file and the `unattended` value — and is asserted to have the same recursive key set as the
  example. A hand-written fixture that drifts from the real format fails loudly;
- `helper.py` is driven exactly as systemd drives it: one JSON line on stdin, one on stdout, the
  journal on stderr. There is no socket code in the helper, so nothing is bypassed by this.

What it drives, locally, before anything touches the node: tests 1, 2, 3, 5, 6, 7, 8, 11, 12 and
the old-format refusal. Test 8 and the hint-validation test require the error message to **name the
offending field** — a generic error (a broken config, say) fails them. Test 3 is asserted only when
test 1 refused on the reason; a counter at zero because the helper crashed is not a passed test.

**OBSERVED 2026-09-13, stage 1, against the unchanged Phase 09 code:** 18 of 19 checks fail, the
one pass being the fixture-shape assertion; the Phase 09 helper answers `STUB-ANSWER` through the
old config shape, which proves the stub and the driver, not the control. After stage 2 the same run
is **PREDICTED** to pass 19 of 19; on the node, `install-model-helper.sh verify` will run the same
file as `aleix`.

### The decisions (brief §6)

| § | Decision | Note |
|---|---|---|
| 6.1 | **Accepted.** `routes` table in `config.json`; models under providers | Model key ≠ CLI id, so a route names a registry alias and only the registry knows the vendor string |
| 6.2 | **Accepted, extended.** Three distinguishable refusals, each with its own `kind` | The table above |
| 6.3 | **Accepted.** `unattended` defaults `false`; explicit opt-in | A field that must be set to become dangerous |
| 6.4 | **Accepted.** Fallback walks the route's own list only | No cross-route fallback; `Limiter` is unchanged in that respect |
| 6.5 | **Accepted.** The bot sends no key; `default_route` in root-owned config; hints accepted, validated, logged, ignored | Plus: unknown fields refused, not ignored (stricter than the brief; stated above) |
| 6.6 | **Accepted: a floor.** `caps.owner_reserve`, proposed `3/hour, 15/day` of `6/30` | Numbers are an open question for the orchestrator |

Two decisions the brief did not ask for, recorded because they are choices:

- `metered: true` or a `credential` in a provider entry makes the helper **refuse to load**. The
  brief says the code "must not read" `credential`; it does not use the value, but it refuses its
  presence, because a field that appears to work and does nothing is how a paid call happens without
  a governor.
- `summary` is logged as a length, not as text — consistent with the question.

## Why eligibility sits on the provider

*(to be written at close)*

## How the refusal was proved

*(to be written at close, from the observed runs)*

## What changes when a metered provider arrives

*(to be written at close, addressed to 15.1)*
