# Model helper

A one-request-per-connection service that makes model calls on the bot's behalf.

It exists for a single reason: **`homelab-bot` cannot read either AI credential,
and must not gain the ability.** That was proved by attempting it in Phase 07 and
it is still proved on every run of `verify-telegram-bot.sh`. So the model call
happens here, as `aleix`, who already holds the credentials, and the bot asks
over a UNIX socket.

## Files

| File | Role |
|---|---|
| `helper.py` | The socket handler. Three operations: `ping`, `ask`, `spend`. Not a shell. |
| `providers.py` | The provider abstraction plus Claude, Codex and AI Gateway implementations |
| `limits.py` | Per-hour and per-day call caps, file-backed, `flock`-protected; releasable reservations |
| `spend.py` | Four-window attended/unattended money governor and content-free ledger |
| `config.example.json` | The registry. Copy to `/etc/homelab-model-helper/config.json` |
| `fixture-tests.py` | Proves the refusals against a fixture and a stub CLI; no allowance spent (15.0) |

## Who may connect (ADR-048, Phase 23.0)

Access is the socket's group and mode, decided in
`config/systemd/homelab-model-helper.socket`, never in code. Since Phase 23.0
the socket is `aleix:homelab-model:0660` and the group **`homelab-model`** has
exactly one meaning: *may ask the helper*. Its members are the consumers:

| Consumer | Account | Since | Why it may ask |
|---|---|---|---|
| Telegram bot | `homelab-bot` | Phase 09 | the owner's `/ask`; the recovery path when the volume is locked |
| Harness (the endpoint) | `homelab-harness` | Phase 23.0 | forwards `question`-class requests from local clients; its own account per ADR-047 |

`getent group homelab-model` is the access list and is expected to read
`homelab-bot,homelab-harness`. The next consumer is a membership with a
`# WHY`, not a new mechanism (`install-model-helper.sh group` creates the
group; the harness installer adds its account). The per-provider caps are
shared by every consumer — the endpoint's calls count against the same
`per_hour`/`per_day` as the owner's `/ask`.

## The protocol

Request — one JSON object, one line, then EOF:

```json
{"v": 1, "op": "ask", "user_id": 123, "question": "...", "context": "..."}
```

Since Phase 15.0, `ask` also accepts — all optional, all validated —
`role` (the routing key; absent means the config's `default_route`),
`unattended` (default `false`), `summary` (≤ 200 chars, logged as a length),
the hints `priority`, `severity`, `complexity` (closed enums, logged, never
selecting), and a 32-hex `request_id` minted by the endpoint for correlation.
**Any other field is refused by name.**

Response — one JSON object, one line:

```json
{"ok": true,  "provider": "claude", "model": "haiku", "text": "..."}
{"ok": false, "kind": "exhausted",    "message": "...", "detail": ["..."]}
{"ok": false, "kind": "ineligible",   "message": "no provider on route '...' may serve unattended calls"}
{"ok": false, "kind": "unknown_role", "message": "no route for role '...'"}
{"ok": false, "kind": "error",        "message": "..."}
```

`op: "ping"` proves the socket works **without making a model call**, so the
install-time connectivity check costs no allowance.

`op: "spend"` reads the governor through the helper. It returns hour, day,
week and month totals and ceilings for both attended and unattended budgets,
plus the metered-call count for the rolling week. It makes no model call.

Note what the caller cannot say: it cannot name a provider, a model, a binary,
a file or a path. All of those come from the root-owned config file. The only
thing on the wire that selects anything is `role`, and it is a lookup key into
that file — `resolve_route()` in `helper.py` is the one place a route is chosen
and it receives the key alone.

## Cheapest models, and why these

| Provider | Model | Why |
|---|---|---|
| Claude | `haiku` | Cheapest tier. Works on Claude Pro; the alias is undocumented in `--help` but functional |
| Codex | `gpt-5.6-luna` | The subscription's mini tier. The binary's own catalogue records it as the replacement for **GPT-5.4 Mini** |
| Gateway | `openai/gpt-5.6-luna` | The only `utility` route; metered and governed before every call |

`openai/gpt-5.6-sol` is also registered, with a complete price entry, but no
route reaches it in Phase 15.1. Adding a registered model does not make it
callable; a route is the sole selector.

## Metered calls and the ledger

The order is shape → route → eligibility → count reservation → money
reservation → provider. A count refusal never touches money. A money refusal
releases its count reservation. HTTP 429 and 401 are provider refusals and
release both; an ambiguous transport failure settles at the reserved maximum
because the provider might have completed the billed work.

`spend.json` is created only by an explicit installer step. Missing, unreadable
or malformed state refuses with `kind: governor_unavailable`; the helper never
recreates it and silently resets a window. Each item in `calls` has this schema:

```text
ts, reservation_id, request_id, route, provider, model, budget,
usage.{input,output,cache_read,cache_write}, reserved_usd, settled_usd,
status, completed_ts, window_totals_after
```

Optional fields are `gateway_cost_usd`, `release_reason`, and `settle_note`.
There is no question, context, answer, credential, hostname, path or unit name.
Money is stored as decimal strings to nine places.

The maximum reservation charges the UTF-8 byte length of the exact message plus
a 256-token allowance for the provider-created chat envelope, at the dearer of
input/cache-read/cache-write rates, then adds all configured output tokens at
the output rate. Actual usage settles uncached input, output, cache read and
cache write independently. A response missing usage settles at the reserved
maximum and emits a warning.

`gpt-5.4-mini` is in the CLI's embedded model catalogue but is **rejected** on a
ChatGPT account: *"The 'gpt-5.4-mini' model is not supported when using Codex
with a ChatGPT account."* A model appearing in the catalogue does not mean the
subscription can use it.

## The model has no tools

Both CLIs are agents; unrestricted they read files and run commands as `aleix`.
Tool use is disabled at the CLI and each call is given a fresh empty working
directory. This was verified with a canary file rather than assumed — see
`providers.py` and the Phase 09 build log.
