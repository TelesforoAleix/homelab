# Phase 15.1 — The metered provider and the spend governor

> **Phase complete 2026-09-13.** The first credential on the node that spends money, and the
> governor that stands between it and the gateway's backstop. Twenty rows: 18 OBSERVED, row 18's
> non-allowlisted half PREDICTED, rows 19–20 in the close. Reconciled to the dashboard **to nine
> decimals**. Handover:
> [`docs/handovers/15.1-gateway-and-spend-governor-handover.md`](../../docs/handovers/15.1-gateway-and-spend-governor-handover.md).

Brief: [`docs/handovers/15.1-gateway-and-spend-governor.md`](../../docs/handovers/15.1-gateway-and-spend-governor.md).
Decisions: ADR-033 (the gateway; holding check re-run here), ADR-046 row 7 (the key), ADR-049 §4
(amended: a step that spends is OWNER-fired). Code: `services/model-helper/spend.py`,
`providers.py` (`GatewayProvider`), `helper.py`, `config.example.json`, `fixture-tests.py`;
`config/systemd/homelab-model-helper@.service.d/credential.conf`; `scripts/server/install-model-helper.sh`
(`credential`, `verify`); `services/telegram-bot/` (`/spend`). Runbooks as run:
[`s2-runbook.md`](s2-runbook.md) (+ [`s2-row10.sh`](s2-row10.sh)), [`s3-runbook.md`](s3-runbook.md)
(+ [`s3-ledger.py`](s3-ledger.py), [`s3-call4.sh`](s3-call4.sh)). Registry and routing themselves
are Phase 15.0's: [`guide/15-model-routing/`](../15-model-routing/README.md).

## What this phase is for, in one paragraph

Until now every model call ran on one of the owner's two subscriptions, capped by count. This
phase adds the first provider that bills per token — the Vercel AI Gateway, reached with a plain
HTTPS request and a key the helper reads through `LoadCredential=` — and, **in the same change**,
the thing ADR-033 §5 said must exist before any paid call: a governor that reserves money before a
request leaves, settles it from actual usage after, keeps attended and unattended budgets apart,
persists across processes, and **refuses when it cannot read its own ledger**. One route uses it
(`utility` → `gateway/luna`); the owner's `/ask` and the endpoint's `execution-agent` route stay on
the subscriptions, free. The phase spent **$0.0000422**.

## The governor — four things it must do, and the test that proved each

The ledger is `/var/lib/homelab-model-helper/spend.json` (`aleix:aleix 0600`), one JSON document,
`calls[]` a list of content-free records. Money is decimal strings, never floats: a float rounded
down admits a call the ceiling should refuse. Every call goes shape → route → eligibility → count
reservation (`limits.py`) → **money reservation** → call → settle or release.

| It must | How | Proved by |
|---|---|---|
| **Refuse before the request leaves** when any of eight windows would be exceeded | `reserve()` sums settled + reserved amounts inside each rolling window (hour/day/week/month × attended/unattended) and refuses if `used + amount > ceiling`, naming the window and the three figures | Fixture rows 1–2 (36/36, locally and on the node ×4). On the node for real: hour ceilings lowered to `$0.001` → `attended hour spend ceiling reached ($0 + $0.001310300 > $0.001000000)`, then the unattended twin; a synthetic `$1.00` day record → `attended day spend ceiling reached ($1.001320700 + $0.001304550 > $1.000000000)`; week and month shown over ceiling by `/spend`. Dashboard count unchanged by all of them |
| **Reserve at maximum, settle at actual** | Reservation = dearer input class × input bound (bytes + 256 envelope tokens) + `max_output_tokens` × output price. Settlement = the four token classes × the config's prices; `usage.cost` from the gateway is reconciliation data, not the settlement | Call 4: reserved `$0.001306300`, settled `$0.000031800` (21 in + 13 out + 10 reasoning); the local calculation reproduced the gateway's billed figure exactly. **Overshoot bound = one reservation (~$0.0013 at 1024 output tokens)** |
| **Keep attended and unattended independent** | `budget` on each record; separate ceilings; a refusal in one never touches the other | Row 3: with a synthetic unattended-hour record at `$0.10/$0.10`, the attended call succeeded; `/spend` showed both before and after |
| **Fail closed** | Ledger absent, unreadable, malformed, wrong schema, or any record malformed → `GovernorUnavailable` → `kind: governor_unavailable`, **before** any request; after a request whose outcome is uncertain (unclassified non-2xx, missing usage) → settled at the reserved maximum | Fixture row 4 (`chmod 000`, malformed, absent — fake gateway saw 0 requests). For real, twice: the S2 403 and the S3 400 each left a **fail-closed line at the reserved maximum** in the ledger — budget state, not billing |

Also proved: **persistence** (row 5: a reservation survived its process; a stale one past 270 s was
released and logged); **release on provider refusal** (row 7: fake 429 → `exhausted`, fake 401 →
`provider_error`, both released count and money); **the request body** (row 8: exactly `model`,
`messages`, `max_tokens`, `providerOptions.gateway.only=["openai"]`; `reasoning` omitted when
`none`; grep for hostname/paths/unit names → 0); **the registry validation** (row 6: a missing
price field or an unapproved vendor fails config load naming the model and the field).

The reservation-not-released debt from 23.0 is closed here for money and count both: a governor
refusal releases the count slot; a provider refusal releases both.

## The ceilings, and why

| Budget | hour | day | week | month |
|---|---|---|---|---|
| attended (`unattended: false`) | $0.25 | $1.00 | $4.00 | $8.00 |
| unattended (`unattended: true`) | $0.10 | $0.40 | $1.50 | $3.00 |

Brief §6.2, adopted unchanged. Month ≤ the gateway key's own **$10/week** budget with room; the
unattended month is under half the attended one because an unattended caller cannot notice its
own runaway. The key's $10/week is the backstop the governor cannot raise — and the one thing the
`homelab-agent` account cannot touch, which is why it must stay set (ADR-049 money path). A
`utility` call reserves ~$0.0013, so the attended hour admits ~190 of them; the real cost of one
was 1–3 hundredths of a cent.

## Reading `/spend` and the ledger

`/spend` (Telegram, owner allowlist, READ capability) asks the helper `op: spend`; nothing else
reads the ledger over the wire. Nine lines:

```text
Metered spend (USD, rolling windows):
attended:
  hour  $0.001337350 / $0.250000000      ← spent / ceiling, this rolling hour
  day   $0.002658050 / $1.000000000
  week  $0.002658050 / $4.000000000
  month $0.002658050 / $8.000000000
unattended:
  hour  $0.000000000 / $0.100000000
  ...
metered calls this week: 4              ← records with ts inside 7 days, any status
```

"Spent" is settled + still-reserved amounts, so it can include a fail-closed maximum. A window at
or above its ceiling refuses the next call of that budget. Windows are rolling from now, not
calendar — a record ages out of the hour after 60 minutes, out of the day after 24 hours.

The ledger record (content-free; the owner reads it as `aleix`, e.g. `s3-ledger.py dump`):

| Field | Meaning |
|---|---|
| `ts`, `completed_ts` | epoch seconds; the window key |
| `reservation_id`, `request_id` | the helper's id; the endpoint's 32-hex id — joins the audit line and the journal |
| `route`, `provider`, `model` | labels (`utility`, `gateway`, `luna`) |
| `budget` | `attended` or `unattended` |
| `reserved_usd`, `settled_usd`, `status` | `reserved` → `settled` or `released`; `settled_usd` is `0` when released |
| `usage` | `{input, output, cache_read, cache_write}` — reasoning tokens are counted in `output` |
| `settle_note` / `release_reason` | `call outcome or charge uncertain` marks a fail-closed line; `provider refusal: exhausted` a release |
| `window_totals_after` | the four totals for that budget at the moment of the write |

## Reconciling against the dashboard — weekly, five lines

1. Vercel dashboard → AI Gateway → the `homelab` key → requests for the period: note the **count**
   and the sum of `totalCost`.
2. On the node as `aleix`: `python3 s3-ledger.py dump` (or any reader) — sum `settled_usd` over the
   period, and separately the lines whose `settle_note` is `call outcome or charge uncertain`.
3. **Compare `dashboard total` with `ledger sum − fail-closed lines`.** They matched to nine
   decimals on 2026-09-13 (`$0.0000422` vs `$0.000042200`).
4. Compare counts: dashboard rows vs ledger `settled` lines with `usage` — the dashboard does not
   show a request refused before routing (the deleted-key 400 never appeared).
5. If the two totals differ by more than a rounding place, or the helper journal has a
   `WARNING spend price drift` line (local vs gateway cost > 10 %), **update the prices** in
   `config.json` from the model page and bump `price_observed` — price drift is a security
   concern, not only a budget one (brief §9).

## Adding a model

A model is a configuration line; a provider is code (ADR-026 §2). Under `providers.gateway.models`:

```json
"sol": {
  "id": "openai/gpt-5.6-sol",
  "reasoning": "high",
  "max_output_tokens": 1024,
  "price": { "input": "2.00", "output": "10.00", "cache_read": "0.20", "cache_write": "2.50" },
  "price_observed": "2026-09-13",
  "note": "…"
}
```

All four `price` fields, `price_observed` and `max_output_tokens` are **required** — the helper
refuses to load without them, naming the field. The vendor is the id's prefix (`openai`), and
`vercel-ai-gateway:<vendor>` must be in `providers_approved` — the owner-signed list, recorded
verbatim below — or the config is refused. Then route it: `"routes": {"utility": ["gateway/luna"]}`
is the only route that reaches the gateway today; a new route is a new key in `routes` and a
`role` the caller sends. Install via the agent's staging path
(`/tmp/homelab-agent/model-helper-config.json` → `sudo -n install -m 644 -o root -g root …`) and
`systemctl restart homelab-model-helper.socket`; the config is read per request, so nothing else
restarts. Use the model's **serving-provider** rates, not the creator's list price — Sol showed
several providers at several prices; the pin makes OpenAI's the right ones.

**Approved serving providers — OBSERVED 2026-09-13, owner approval recorded verbatim:**

`APPROVE providers_approved = ["anthropic-cli", "openai-cli", "vercel-ai-gateway:openai"]`

The helper derives `openai` from `openai/<model>`, requires `vercel-ai-gateway:openai` in the
root-owned list, and sends `providerOptions.gateway.only=["openai"]` on every request. Vercel
documents that requests are dynamically routed by default and that `only` is the request-level
provider allowlist ([provider options](https://vercel.com/docs/ai-gateway/models-and-providers/provider-options),
read 2026-09-13). The dashboard attributed all three real requests to `openai`. A team-wide
dashboard allowlist is not relied on — it lives outside git and can drift.

## Rotating the key (row 13, as a procedure)

OBSERVED 2026-09-13 end to end. OWNER throughout except the two reads.

1. **Browser:** delete the `homelab` key. Vercel has no separate "revoked" state; deletion is the
   revocation. From that moment the node's key is refused.
2. **What a call sees now:** the gateway answers **HTTP 400 `invalid_request_error`**, not the 401
   the brief predicted. The helper maps 401 → `provider_error` (released, $0) and 429 → `exhausted`;
   a 400 is an *unclassified* non-2xx after egress, so the governor **settles at the reserved
   maximum** (`$0.001305550` on the day) — deliberately: a 400 before inference is *probably* free,
   and probably is not what the ledger records. The dashboard showed no row for it. Mapping this
   case to a release is Phase 15 debt, by name, once the gateway's error codes are catalogued from
   observation.
3. **Browser:** create a new key named `homelab` with the **$10/week** budget. Confirm the budget on
   screen.
4. **Node, as `aleix`:** `sudo env SRC=/tmp/homelab-p151/helper bash …/install-model-helper.sh credential`
   (the installer copy; `scripts/server/install-model-helper.sh` in the repo). It opens `nano` on a
   root-owned temp file; paste the key; save; exit. The key never touches argv, stdin, an
   environment variable, the journal, git or the chat. The previous key is kept as
   `gateway-key.bak-<date>` (root-only) — **shred it once the new key is proved**.
5. **Agent:** `stat` → `root:root 600`, new mtime; `systemctl restart homelab-model-helper.socket`.
6. One attended `utility` call → `ok`. (Call 4 did this with the unattended budget exhausted, so it
   proved rows 13 and 3 together.)

The password manager holds the only other copy. ADR-046 row 7 records the key as revocable-in-one-click
and not TPM-sealed by decision.

## What the first real calls cost, exactly

| # | When (UTC) | What | Gateway billed | Ledger settled | Note |
|---|---|---|---|---|---|
| S2-1 | 13:49:35 | first attempt | **$0** (HTTP 403, no usage) | `$0.001310300` | fail-closed: no prepaid credit on the account |
| S2-2 | 14:26:15 | retry after $10 credit | **$0.0000104** (22 in / 5 out) | `$0.000010400` | the first metered answer: `4` |
| S3-3 | 17:50:05 | deleted key | **$0**, no dashboard row (HTTP 400) | `$0.001305550` | fail-closed |
| S3-4 | 18:01:12 | new key, unattended exhausted | **$0.0000318** (21 in / 13 out + 10 reasoning) | `$0.000031800` | `S3-ROTATED-OK`; 1.9 s |

**Phase total, dashboard: $0.0000422.** Ledger: `$0.002658050`, of which `$0.002615850` is the
two fail-closed lines; the remainder `$0.000042200` equals the dashboard. Both round to **$0.00**.
Latency 1.9–2.2 s per call through the endpoint. The owner also paid **$13.24** to load `$10.00`
of prepaid credit (`$3.24` VAT/processing) — balance and overhead, not usage; `costs.md` has both.
Luna is configured `reasoning: "none"` and the gateway still billed 10 reasoning tokens on call 4;
the helper counts them as output, which is what made the settlement exact.

## What went wrong, and what it taught (PROJECT.md §11)

- **HTTP 403 on the first call** (S2). Not authentication (401), not routing (no rule set): the
  account had no prepaid credit. Diagnosed by a no-inference change first — the helper now reads a
  bounded error body and journals **only** validated `type` and `code`, never `message` or `param`
  (either could echo the question); the fixture injects sentinels and fails if they leak. One
  authorized retry after the credit succeeded. The 403 line stays in the ledger as fail-closed.
- **A deleted key answers 400, not 401.** Row 13's shape was predicted from the docs; observation
  differed. Kept fail-closed (above).
- **The draft S3 runbook was run before its rewrite** with a wrong role name (`utility-unattended`
  → `unknown_role`; the right form is `role: utility` + `unattended: true`) and its hour-ceiling
  edit left in place. The rewrite found all of it in the sudo and helper journals before spending
  anything and accepted the two locally refused hour calls from the endpoint's audit lines rather
  than repeating them.
- **The executor cannot fire a paying call.** Claude Code's permission layer refused the call-4
  `curl` as a real-world transaction; nothing was worked around — the call became a staged script
  with its own one-attempt marker that the owner fired through the agent alias from the Mac. Now
  ADR-049 §4: *a step that spends money is OWNER-fired even when AGENT-runnable; the executor
  stages, the owner fires, the executor reads.*
- **Paste is an attempt hazard.** A heredoc ran on the wrong machine, another lost its `EOF` to
  indentation, a one-liner split mid-header in a wrapped terminal (an endpoint `bad_request`, no
  cost). Every remaining OWNER step became a staged script with a one-word invocation.
- **`X-Homelab-Client` is 32 characters at most.** The runbook's first call-4 label was 36.
- **Zero Data Retention shows disabled** on the dashboard. Accepted: ADR-039 §1 permits the owner's
  own material to leave for an approved provider under its standard terms; ZDR is an enterprise
  arrangement, not a repository-owned control. **Revisit at ADR-033 trigger 1**, before any
  third-party data is sent.
- **The close backup was first written with `main`'s `backup-node.sh`** (the owner ran it from the
  main checkout, not the worktree): it does not collect the helper's `credential.conf`, and the
  branch's verifier said `WRONG ABSENT`. Also: run with no argument, the verifier picks the
  lexically newest directory — `2026-09-13-p151-s2` over `2026-09-13` — and reported five stale
  mismatches against a two-stage-old archive; and `--force` overwrote 13.1's same-day snapshot.
  Fixed by renaming and re-running both scripts from the branch → PASS. **Until a phase is merged,
  its close backup runs from its worktree**, with the path given to the verifier explicitly.
- The S2 backup-search paste failed on the Mac (`rg` absent; a leading `# T` line eaten by zsh) —
  the runbook now falls back to `grep -nE` and starts with a command.

## Security notes

- **The first credential on the node that spends money.** `/etc/homelab-model-helper/gateway-key`,
  `root:root 0600`, presented to each helper instance as `0400` under `$CREDENTIALS_DIRECTORY`
  (`credential.conf` drop-in; score **3.8** before and after). `homelab-bot` and `homelab-harness`
  are permission-denied on it (OBSERVED S2 and S3); `homelab-agent` is denied by name in sudoers;
  `AI_GATEWAY_API_KEY` appears in no unit environment. Blast radius if it leaks: the key's $10/week,
  until one click revokes it.
- **The governor is the only thing between unattended work and that backstop**, and it is proved
  by breaking it (row 4), not by reading it. The `homelab-agent` account can replace `config.json`
  and so raise a ceiling — stated in ADR-049; the gateway budget is why that is acceptable.
- **Nothing new leaves.** The request body is the two strings the CLIs get, plus the vendor pin.
  The destination is wider by one vendor, which is why the approved list is owner-signed.
- **The key never touches a command line, stdin, an environment, the journal, git or the chat.**
  Rows 16 and 20; the S2/S3 journals carry `gateway_error_type=…` and nothing more.
- **`/spend` reads, never acts.** Owner allowlist; no promotion.
- **Fail-closed lines are budget, not billing.** They make the attended windows look ~$0.0026
  fuller than the dashboard for a month. That is the intended direction of error.
- User-space only: no sshd, firewall, Tailscale, boot or volume change in any stage.

## Status by row

| Row | Status | Evidence |
|---|---|---|
| 1–2 | OBSERVED | fixture 36/36 local (S1) and on the node ×4 (S2 16:34Z, S3 16:44Z ×3); on the real path P1/P3 with `$0.001` ceilings |
| 3 | OBSERVED | call 4 `ok` with unattended hour `0.10/0.10` |
| 4–8 | OBSERVED | fixture, node; row 8 body captured verbatim in S1 |
| 9 | OBSERVED | 15.0's 19 inside the 36; endpoint 64/64 on the node |
| 10 | OBSERVED | 14:26:15Z, `4`, 22/5, `$0.0000104` |
| 11 | OBSERVED | 16:39:48Z `spend_capped`, dashboard 2 before and after |
| 12 | OBSERVED | `$0.0000422` vs `$0.000042200` |
| 13 | OBSERVED, shape differs | 400 not 401; rotation via editor; call 4 `ok` |
| 14 | OBSERVED | bot and harness denied; `root:root 600` |
| 15 | OBSERVED | `3.8 OK` after the drop-in |
| 16 | OBSERVED | no `AI_GATEWAY_API_KEY`; journal type/code only |
| 17 | OBSERVED | `/ask` → `claude/haiku`, ledger mtime unchanged; endpoint `execution-agent` free (S2) |
| 18 | OBSERVED / PREDICTED | owner `/spend` ×9; non-allowlisted refusal PREDICTED from the allowlist gate |
| 19 | OBSERVED | close: `running`, 0 failed, 8 listeners, helper 3.8 / harness 1.3; `backup-node.sh` from **this branch** + `verify-node-backup.sh` → PASS against the live node, `gateway-key`, `spend.json` and the helper's `credential.conf` present, control fires |
| 20 | OBSERVED | `git grep` for the key prefix in both repos → 0 |
