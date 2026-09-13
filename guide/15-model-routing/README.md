# Phase 15.0 — Model registry and routing

**Status:** complete 2026-09-13. §Design was written in stage 1 before any code or node change;
the closing sections after the live tests. Brief:
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
| `caps.owner_reserve` | | The floor (§6.6). Unattended calls may reach at most `per_x − owner_reserve.per_x` in each window; the remainder is the owner's. **Keyed exactly as the caps are: per provider, one count each** — the reserve is not a second counting scheme, it is a lower ceiling on the same count |

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
old config shape, which proves the stub and the driver, not the control.
**OBSERVED 2026-09-13, stage 2, on the MacBook (Python 3.13.5), against the new code: 19 of 19
pass, four consecutive runs** (the race in test 7 included). On the node,
`install-model-helper.sh verify` runs the same file as `aleix` from `/opt` — PREDICTED to match
until the runbook is run.

### The decisions (brief §6)

| § | Decision | Note |
|---|---|---|
| 6.1 | **Accepted.** `routes` table in `config.json`; models under providers | Model key ≠ CLI id, so a route names a registry alias and only the registry knows the vendor string |
| 6.2 | **Accepted, extended.** Three distinguishable refusals, each with its own `kind` | The table above |
| 6.3 | **Accepted.** `unattended` defaults `false`; explicit opt-in | A field that must be set to become dangerous |
| 6.4 | **Accepted.** Fallback walks the route's own list only | No cross-route fallback; `Limiter` is unchanged in that respect |
| 6.5 | **Accepted.** The bot sends no key; `default_route` in root-owned config; hints accepted, validated, logged, ignored | Plus: unknown fields refused, not ignored (stricter than the brief; stated above) |
| 6.6 | **Accepted: a floor.** `caps.owner_reserve` = `3/hour, 15/day` of `6/30` — half | Accepted by the orchestrator after S1. It is config; the owner tunes it there |

Two decisions the brief did not ask for, recorded because they are choices:

- `metered: true` or a `credential` in a provider entry makes the helper **refuse to load**. The
  brief says the code "must not read" `credential`; it does not use the value, but it refuses its
  presence, because a field that appears to work and does nothing is how a paid call happens without
  a governor.
- `summary` is logged as a length, not as text — consistent with the question.

## Why eligibility sits on the provider

A model has no terms of service. A *subscription* does, and so does a metered account. Whether a
call nobody asked for in person is acceptable is a property of the thing being billed, not of the
model string passed to it — Claude `haiku` through the owner's Pro subscription and `haiku` through
a metered gateway are the same model under different terms. So `unattended` is a field on the
provider entry, and a route that mixes providers is filtered provider by provider.

Putting it there also makes ADR-026 §5's accepted risk **reversible one provider at a time**: if a
finding ever says one subscription must not serve unattended calls, the change is one boolean in
root-owned config and the refusal path is already proved. That is the whole reason the field
exists today, when both entries are `true` and nothing unattended calls yet.

Be clear about what it is not (brief §9): it is not a security boundary against the bot. The bot is
trusted to declare `unattended` honestly; nothing verifies the claim. It is a control against
*this project* building a scheduled caller in a later phase and forgetting what that implies — a
line the code makes it impossible to cross silently.

## How the refusal was proved

The check will permit every real call this project makes today, so its first refusal had to be
manufactured. `fixture-tests.py` does that without touching a CLI, a socket, the node's config or
anyone's allowance:

1. The fixture config is **`config.example.json` with three substitutions** — both binaries
   replaced by a stub that prints `STUB-ANSWER`, the state file moved to a temp directory, and
   `unattended` set to the value under test — and it is asserted to have the same recursive key
   set as the example. A hand-written fixture that drifts from the real format would refuse for
   the wrong reason and look identical to a finding; this one cannot drift.
2. `helper.py` is run the way systemd runs it: one JSON line on stdin. It has no socket code, so
   there is nothing to bypass; the real loader, router, eligibility check, `Limiter` and provider
   argv code all execute.
3. **Test 1**: `{"unattended": true}` against `unattended: false` → `kind: "ineligible"`, journal
   `outcome=ineligible providers=claude,codex`, counter `0 → 0`.
   **Test 2**, the positive control: the same request against `unattended: true` → `ok`,
   `claude/haiku`, `STUB-ANSWER`, counter `0 → 1`. Without test 2, test 1 would be a refusal of
   unknown cause.

OBSERVED 2026-09-13: 19/19 on the MacBook (four consecutive runs, the ten-process race included),
then 19/19 **on the node, as `aleix`, from the installed code in `/opt`**, inside
`install-model-helper.sh verify` — which now runs the fixture every time. The first version of the
fixture passed tests 8 and 11b on *any* error; that was caught by running it against the old code
first, where "helper misconfigured" satisfied them, and the tests now require the error to name the
field. The test of the control needed its own control.

The live half: `/ask what is the load on this machine?` from the phone answered `-- claude/haiku`
with the journal line `route=owner-interactive unattended=false summary_len=0 provider=claude
model=haiku … outcome=ok`; the same with the data volume locked (the helper lives on root,
ADR-046 §2). `id homelab-bot` byte-identical, seven listeners, score 3.8, unit file untouched.

What the swap on the node taught (all in the handover's lessons): the installer's own probe landed
in the code/config window and left one failed instance — the window the runbook said was real,
observed because the runbook caused it; and `verify` said `UNKNOWN` once because the fixture reads
`config.example.json` beside itself and the installer had not copied it — the correct failure,
fixed in the installer.

## What changes when a metered provider arrives

Nothing in the shape; four things in substance (handover, *To Phase 15.1*):

- **A provider class** in `providers.py` — adding a provider is code, adding a model is a line.
- **`metered: true` and `credential: "<name>"`** on its entry. Today the helper **refuses to
  load** a config that has either: the governor ADR-033 §5 requires does not exist, and a field
  that appears to work and does nothing is how a paid call happens without one. 15.1 removes that
  refusal in the same commit that ships the governor. `credential` is a name resolved through
  `LoadCredential=` — a unit change, measured against the baseline — never a path.
- **The governor** — four windows, attended/unattended split, fail-closed, persistent. It is the
  owner floor's idea over money; it sits beside `Limiter`, which stays a capacity control and was
  deliberately not taught about cost.
- **Routes gain a reason to order by price**, and cross-route fallback ("the cheap model is spent,
  use the good one") becomes a cost decision. It is refused today; 15.1 decides it with prices in
  hand.

Caps stay per provider, before the call, refused for free — the Phase 09 rule that every layer of
this phase repeats.
