# Phase 15.1 — S3 runbook (governor proof and reconciliation), AGENT/OWNER form

Rewritten 2026-09-13 under ADR-049 before it runs. Two blocks, fixed vocabulary
(`guide/13.1-agent-operator-access/README.md`):

- **AGENT** — the executor, over `ssh homelab-agent` (BatchMode, no tty, no password ever). It runs
  the command, reads its own output, and reports it OBSERVED with the raw lines. The default.
- **OWNER** — aleix at the keyboard, only for: the ledger and the credential (aleix's file and the
  editor-opened secret), the Vercel dashboard (read figures; revoke/create the key), and Telegram
  `/spend`. The executor prints exactly what to do and stops until the paste arrives.

Anything not on `sudo -l -U homelab-agent` (pasted verbatim in the 13.1 guide) is an OWNER step; the
agent does not try it. This runbook never prints, pastes, or passes the gateway credential; it
changes only the helper's `config.json` and the spend ledger, both backed up and both restored.

**Class:** ordinary user-space service/configuration work — no network, remote-access,
authentication, boot, firewall, admin-account, volume, reboot, or second-session change.

## Names fixed by the grant and by the S2/13.1 state

| Name | Value | Who may touch it |
|---|---|---|
| Alias | `ssh homelab-agent` | AGENT |
| Staging dir | `/tmp/homelab-agent/` (cleared at boot; `mkdir -p` per session) | AGENT |
| Staged config | `/tmp/homelab-agent/model-helper-config.json` → `sudo -n install -m 644 -o root -g root … /etc/homelab-model-helper/config.json` | AGENT |
| Helper unit | `homelab-model-helper.socket` — `stop` / `start` / `restart` / `is-active`, one unit per call | AGENT |
| Agent ledger copy | `/var/lib/homelab-model-helper/spend.json.bak` (`sudo -n cp -p` there; `sudo -n mv` back consumes it) | AGENT |
| `S3LEDBAK` | `/var/lib/homelab-model-helper/spend.json.bak-2026-09-13-p151-s3` — `aleix:aleix 600`, 1017 bytes, mtime 14:26Z; the pristine post-S2 ledger (two lines), made by the owner at 16:32Z from the draft | OWNER (aleix owns it; no sudo) |
| `S3CFGBAK` | `/etc/homelab-model-helper/config.json.bak-2026-09-13-p151-s3` — `root:root 644`, 3056 bytes; byte-equal to the repo's `services/model-helper/config.example.json` (OBSERVED: the live file differs from the repo file only in the two hour ceilings) | AGENT restores by installing the repo file |
| Helper source on the node | `/tmp/homelab-p151/helper/` (S2 staging, still present) — used only by the OWNER credential step | OWNER |
| Endpoint | `http://127.0.0.1:8766/v1/request`, header `X-Homelab-Client` | AGENT (curl on the node) |
| Ledger reads | `spend.json` is `aleix:aleix 600`; the agent cannot read it — `/spend` and one OWNER python dump at §9 are the reads | OWNER |

**Ledger edits, how.** The orchestrator fixed: helper stopped (AGENT), edit as aleix with no sudo
(OWNER), agent verifies owner/mode after. The ledger is one compact JSON line; inserting a record
into it by hand in `nano` is the kind of slip that costs an attempt, so each OWNER edit below is
the equivalent `python3` heredoc **run as aleix, no sudo, writing the same file in place** (inode,
owner and mode unchanged). `nano /var/lib/homelab-model-helper/spend.json` remains available to
the owner for the same edit; the record to insert is the one in the heredoc.

## State found before this run (OBSERVED 2026-09-13, sudo and helper journals)

The draft of this runbook was run by the owner at 16:32–16:44Z, before 13.1 landed:

- §0 backups exist (`S3CFGBAK`, `S3LEDBAK` above).
- §1 `verify` ran four times (16:34:35Z, 16:44:14Z, 16:44:21Z, 16:44:27Z); the orchestrator holds
  rows 1–8 OBSERVED on the node (36/36) — **recorded, not repeated**.
- §2 lowered **both** hour ceilings to `0.001` (`sudoedit` 16:35Z and 16:37Z); the live config is
  the repo `config.example.json` with only those two values changed.
- §3 made three endpoint attempts, all refused on the node, **none** left it:

| Prior attempt | Time (UTC) | Client label | Result |
|---|---|---|---|
| P1 | 16:39:48 | `p151-s3-attended-hour` | helper `outcome=spend_capped`; endpoint `outcome=exhausted stage=helper` |
| P2 | 16:41:28 | `p151-s3-unattended-hour` | `role=utility-unattended` → `outcome=unknown_role` (the draft's bad role; refused before any route or reservation) |
| P3 | 16:43:03 | `p151-s3-unattended-hour` | `role=utility` → `spend_capped` / `exhausted stage=helper`; whether `"unattended": true` was set is only in the endpoint's audit line (OWNER reads it in §0) |

- §4's three restore+`verify` cycles at 16:44Z left the ledger byte-identical to `S3LEDBAK`. No
  synthetic record is present. `calls.json` mtime 16:43Z (count reservations released).

**Consequence for the budget:** P1 is call 1 if its refusal names the attended hour; P3 is call 2 if
its audit line shows `"unattended": true` and the refusal names the unattended hour. Otherwise the
missing one is re-run **once**. Every attempt, prior or new, is in the table below.

## Attempt ledger (fill as you go)

Provider-reaching calls: **at most 4** — (1) attended-hour refusal, (2) unattended-hour refusal,
(3) revoked-key 401, (4) new-key success with synthetic unattended exhaustion present. (1), (2) and
3a are expected to be refused by the governor before any request leaves; they are counted anyway.
No fifth provider-reaching attempt for any reason.

~~~text
P1  16:39:48Z  attended hour       refused locally (spend_capped)            provider requests 0
P2  16:41:28Z  bad role            refused locally (unknown_role)            provider requests 0
P3  16:43:03Z  unattended hour(?)  refused locally (spend_capped)            provider requests 0
1   attended-hour refusal:      [time, detail line, dashboard count unchanged]   (= P1 if accepted)
2   unattended-hour refusal:    [time, detail line, dashboard count unchanged]   (= P3 if accepted)
3a  day refusal (synthetic):    [time, detail line, dashboard count unchanged]
3   revoked key:                [time, kind/provider_error, type+code, dashboard]
4   new key + independence:     [time, ok, cost, dashboard +1]
~~~

---

## 0 — Baseline, prior-attempt evidence, dashboard baseline

**AGENT**

~~~bash
ssh homelab-agent 'mkdir -p /tmp/homelab-agent
hostname; id
sudo -n systemctl is-system-running
sudo -n systemctl --failed
for u in homelab-model-helper.socket homelab-harness.service homelab-telegram-bot.service; do
  printf "%s " "$u"; sudo -n systemctl is-active "$u"; done
sudo -n stat -c "%n %U:%G %a %s bytes mtime=%y" \
  /etc/homelab-model-helper/config.json \
  /etc/homelab-model-helper/config.json.bak-2026-09-13-p151-s3 \
  /var/lib/homelab-model-helper/spend.json \
  /var/lib/homelab-model-helper/spend.json.bak-2026-09-13-p151-s3 \
  /etc/homelab-model-helper/gateway-key
sudo -n cat /etc/homelab-model-helper/config.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d[\"spend\"][\"budgets\"])); print(d[\"routes\"][\"utility\"])"
sudo -n journalctl -u "homelab-model-helper@*" --since "2026-09-13 16:30" --no-pager -o short-iso | grep "outcome="
sudo -n journalctl -u homelab-harness.service --since "2026-09-13 16:30" --no-pager -o short-iso | grep "client=p151-s3"'
~~~

Also, on the Mac: `ssh homelab-agent 'sudo -n cat /etc/homelab-model-helper/config.json' | diff - services/model-helper/config.example.json` → expected: exactly the two `hour` lines.

Stop if any unit is not `active`, the system is not `running`, or `S3LEDBAK`'s size/mtime differ
from `spend.json`'s.

**OWNER** (Browser, Phone, one `ssh homelab` as aleix)

1. Browser: the dashboard's request count and total spend as of now (S2 left: 2 requests,
   `$0.00001`). Paste both numbers; no key, account id, token-bearing URL, or screenshot.
2. Phone: `/spend`. Paste all nine lines.
3. Terminal, as aleix (one sudo, the harness audit file is not aleix's):
   ~~~bash
   sudo grep -E '"client_declared": ?"p151-s3-' /var/lib/homelab-harness/audit.jsonl
   ~~~
   Paste the three lines (they carry `unattended`, `outcome`, `request_id`; no question text).

## 1 — Rows 1–8: record only

OBSERVED on the node 2026-09-13 16:34Z and 16:44Z ×3, `install-model-helper.sh verify`, 36/36,
external calls 0 (S2 report + the sudo journal). Not repeated; the fixture command is not on the
agent's list and the orchestrator has recorded it.

## 2 — Hour ceilings are already lowered

OBSERVED in §0: `attended.hour = 0.001`, `unattended.hour = 0.001`, everything else standing. No
edit. Note what this proves: the reserve amount for one `utility` call is `$0.001310300` (dearer
input class + `max_output_tokens`), so with a `$0.001` ceiling the governor refuses at `$0` used —
`used + amount > ceiling` — which is the same comparison the standing ceilings use at the edge.

## 3 — Calls 1 and 2 (hour, attended then unattended), then standing config back

Decide from §0's audit lines:

- P1's line shows `"role": "utility"`, `"unattended": false`, `"outcome": "exhausted"` → **call 1 =
  P1**, OBSERVED. The refusal text lives in the helper's `spend_capped` line and the endpoint's
  `detail`; the endpoint body was not captured then. If the orchestrator wants the `detail` line
  verbatim, run the AGENT block for call 1 once — it is refused locally and reaches nothing.
- P3's line shows `"unattended": true` → **call 2 = P3**, OBSERVED, same caveat. If it shows
  `false`, P3 was a second attended refusal; run the call-2 AGENT block once.

**AGENT — call 1 (only if not accepted from P1)**

~~~bash
ssh homelab-agent 'M=/tmp/homelab-agent/p151-s3-call1.done; [ -e "$M" ] && { echo "STOP: call 1 already attempted this session"; exit 2; }
date -u +%FT%TZ | tee "$M"
curl -sS --max-time 300 -H "X-Homelab-Client: p151-s3-attended-hour" -H "Content-Type: application/json" \
  -d "{\"v\":1,\"kind\":\"question\",\"role\":\"utility\",\"question\":\"Reply with exactly S3-HOUR-ATTENDED.\"}" \
  http://127.0.0.1:8766/v1/request; echo
sudo -n journalctl -u "homelab-model-helper@*" -n 3 --no-pager -o short-iso | grep outcome='
~~~

Expected: `"ok": false, "kind": "exhausted", "stage": "helper"`, `detail` = `attended hour spend
ceiling reached ($… + $0.001310300 > $0.001000000)`; helper `outcome=spend_capped`.

**AGENT — call 2 (only if not accepted from P3)**

~~~bash
ssh homelab-agent 'M=/tmp/homelab-agent/p151-s3-call2.done; [ -e "$M" ] && { echo "STOP: call 2 already attempted this session"; exit 2; }
date -u +%FT%TZ | tee "$M"
curl -sS --max-time 300 -H "X-Homelab-Client: p151-s3-unattended-hour" -H "Content-Type: application/json" \
  -d "{\"v\":1,\"kind\":\"question\",\"role\":\"utility\",\"unattended\":true,\"question\":\"Reply with exactly S3-HOUR-UNATTENDED.\"}" \
  http://127.0.0.1:8766/v1/request; echo
sudo -n journalctl -u "homelab-model-helper@*" -n 3 --no-pager -o short-iso | grep outcome='
~~~

Expected: `detail` = `unattended hour spend ceiling reached ($0 + $0.001310300 > $0.001000000)`.

**OWNER** after each new call: Browser once — request count unchanged from §0. Paste the number.

**AGENT — standing config back** (rows 1–2's positive control on the node is the standing ceiling
admitting call 4 later; the day/week/month steps need the hour window open)

~~~bash
scp services/model-helper/config.example.json homelab-agent:/tmp/homelab-agent/model-helper-config.json
ssh homelab-agent 'sudo -n install -m 644 -o root -g root /tmp/homelab-agent/model-helper-config.json /etc/homelab-model-helper/config.json
sudo -n stat -c "%n %U:%G %a %s bytes" /etc/homelab-model-helper/config.json
sudo -n cat /etc/homelab-model-helper/config.json | sha256sum
sudo -n systemctl restart homelab-model-helper.socket; sudo -n systemctl is-active homelab-model-helper.socket'
sha256sum services/model-helper/config.example.json
~~~

Expected: `root:root 644 3056 bytes`, the two hashes equal, socket `active`.

**OWNER** Phone: `/spend` → ceilings `0.25 / 1.00 / 4.00 / 8.00` and `0.10 / 0.40 / 1.50 / 3.00`.
Paste.

## 4 — Day, week, month: synthetic ledger (attended)

Synthetic, labelled, never carried forward. Each record is `status: settled` in the **attended**
budget with `ts` placed **outside the hour window and inside the target window**, and
`settled_usd` equal to that window's ceiling, so the governor's first exceeded window is the
target one. Between windows the ledger goes back to `S3LEDBAK` (aleix's `cp -p`, no sudo).

**Day — proved two ways:** `/spend` shows the day window at/over its ceiling, AND one real
endpoint attempt (`role: utility`, attended) is refused naming the day window — **attempt 3a,
refused locally, no provider request, dashboard count unchanged.**

**AGENT** stop the helper:

~~~bash
ssh homelab-agent 'sudo -n systemctl stop homelab-model-helper.socket; sudo -n systemctl is-active homelab-model-helper.socket; echo rc=$?'
~~~

Expected `inactive`, `rc=3`.

**OWNER** as aleix, no sudo — restore the pristine ledger and add the day record:

~~~bash
cp -p /var/lib/homelab-model-helper/spend.json.bak-2026-09-13-p151-s3 /var/lib/homelab-model-helper/spend.json
python3 - <<'EOF'
import json, time
p = "/var/lib/homelab-model-helper/spend.json"
d = json.load(open(p)); now = time.time(); label = "p151-s3-synthetic-day"
d["calls"].append({"ts": now - 2*3600, "completed_ts": now - 2*3600,
  "reservation_id": label, "request_id": label, "route": "utility", "provider": "gateway",
  "model": "luna", "budget": "attended", "usage": None,
  "reserved_usd": "1.000000000", "settled_usd": "1.000000000", "status": "settled",
  "synthetic": label})
with open(p, "w") as fh: json.dump(d, fh, separators=(",", ":")); fh.write("\n")
print("calls:", len(d["calls"]), "last:", d["calls"][-1]["synthetic"])
EOF
~~~

Paste the `calls:` line.

**AGENT** verify owner/mode, start, then attempt 3a:

~~~bash
ssh homelab-agent 'sudo -n stat -c "%n %U:%G %a %s bytes" /var/lib/homelab-model-helper/spend.json
sudo -n systemctl start homelab-model-helper.socket; sudo -n systemctl is-active homelab-model-helper.socket'
~~~

**OWNER** Phone: `/spend` → `attended: day $1.001320700 / $1.000000000`, hour `$0…`. Paste.

**AGENT — attempt 3a**

~~~bash
ssh homelab-agent 'M=/tmp/homelab-agent/p151-s3-call3a.done; [ -e "$M" ] && { echo "STOP: 3a already attempted"; exit 2; }
date -u +%FT%TZ | tee "$M"
curl -sS --max-time 300 -H "X-Homelab-Client: p151-s3-synthetic-day" -H "Content-Type: application/json" \
  -d "{\"v\":1,\"kind\":\"question\",\"role\":\"utility\",\"question\":\"Reply with exactly S3-DAY.\"}" \
  http://127.0.0.1:8766/v1/request; echo
sudo -n journalctl -u "homelab-model-helper@*" -n 3 --no-pager -o short-iso | grep outcome='
~~~

Expected: `detail` = `attended day spend ceiling reached ($1.001320700 + $0.001310300 > $1.000000000)`.

**OWNER** Browser once: request count unchanged. Paste.

**Week and month — `/spend` display only, no attempt.** For each: AGENT stops the helper; OWNER
restores from `S3LEDBAK` and runs the heredoc above with these three substitutions; AGENT stats
and starts; OWNER pastes `/spend`.

| Window | `label` | `ts` / `completed_ts` | `reserved_usd` = `settled_usd` | `/spend` expected |
|---|---|---|---|---|
| week | `p151-s3-synthetic-week` | `now - 2*86400` | `"4.000000000"` | `attended: week $4.001320700 / $4.000000000`, day `$0.001320700` |
| month | `p151-s3-synthetic-month` | `now - 10*86400` | `"8.000000000"` | `attended: month $8.001320700 / $8.000000000`, week `$0.001320700` |

Then: AGENT stop → OWNER `cp -p` from `S3LEDBAK` (no edit) → AGENT stat + start. The ledger is
pristine again before §5.

## 5 — Synthetic unattended-hour exhaustion (stays until §8)

The record sits in the **unattended** budget at `ts = now`, `settled_usd` = the unattended hour
ceiling `0.10`. It exhausts the unattended hour only (`0.10 < 0.40` day). Call 4 (attended) must
run **within 60 minutes** of this edit or the record ages out of the hour window; §7 checks by
`/spend` and, if it aged out, this step is repeated (AGENT stop → OWNER heredoc → AGENT start).

**AGENT** stop (as in §4). **OWNER** as aleix:

~~~bash
python3 - <<'EOF'
import json, time
p = "/var/lib/homelab-model-helper/spend.json"
d = json.load(open(p)); now = time.time(); label = "p151-s3-synthetic-unattended-hour"
assert not any("synthetic" in c for c in d["calls"]), "a synthetic record is still present"
d["calls"].append({"ts": now, "completed_ts": now,
  "reservation_id": label, "request_id": label, "route": "utility", "provider": "gateway",
  "model": "luna", "budget": "unattended", "usage": None,
  "reserved_usd": "0.100000000", "settled_usd": "0.100000000", "status": "settled",
  "synthetic": label})
with open(p, "w") as fh: json.dump(d, fh, separators=(",", ":")); fh.write("\n")
print("calls:", len(d["calls"]), "synthetic ts:", int(now))
EOF
~~~

**AGENT** stat + start. **OWNER** Phone `/spend` → `unattended: hour $0.100000000 / $0.100000000`,
attended hour `$0.000000000 / $0.250000000`. Paste.

Rows 4 and 6 (unreadable ledger → `governor_unavailable`, no request; incomplete price /
unapproved vendor → config load fails naming the field) are OBSERVED on the node by the §1
fixture runs (36/36). A live `chmod 000` attempt is not on the orchestrator's attempt list and is
not made.

## 6 — Revocation rehearsal and rotation (row 13)

**OWNER** Browser: revoke **only** the `homelab` key. Confirm it shows revoked. Paste the request
count and spend as of now.

**AGENT — call 3**

~~~bash
ssh homelab-agent 'M=/tmp/homelab-agent/p151-s3-call3.done; [ -e "$M" ] && { echo "STOP: call 3 already attempted"; exit 2; }
date -u +%FT%TZ | tee "$M"
curl -sS --max-time 300 -H "X-Homelab-Client: p151-s3-revoked-key" -H "Content-Type: application/json" \
  -d "{\"v\":1,\"kind\":\"question\",\"role\":\"utility\",\"question\":\"Reply with exactly S3-REVOKED.\"}" \
  http://127.0.0.1:8766/v1/request; echo
sudo -n journalctl -u "homelab-model-helper@*" -n 4 --no-pager -o short-iso | grep -E "outcome=|spend"'
~~~

Expected: `"kind": "provider_error", "stage": "helper"`; helper journal `outcome=provider_error
gateway_error_type=… gateway_error_code=…` (type/code only — never message/param); the ledger
line for it is `released` (`provider refusal: provider_error`), `$0`. Do not retry.

**OWNER** Browser once: whether the 401 appears as a request (record either way; do not assume it
is invisible), total spend unchanged. Then create the replacement key named `homelab` with the
same **$10/week** budget; confirm the budget on screen.

**OWNER** Terminal as aleix — the installer's editor step, the only way the key enters the node
(never a command line, never stdin):

~~~bash
sudo env SRC=/tmp/homelab-p151/helper bash /tmp/homelab-p151/helper/install-model-helper.sh credential
~~~

Paste the key into the editor, save, exit. The installer keeps the revoked key at
`gateway-key.bak-2026-09-13` (root-only; revoked; delete at S4 close). Say "done".

**AGENT**

~~~bash
ssh homelab-agent 'sudo -n stat -c "%n %U:%G %a %s bytes mtime=%y" /etc/homelab-model-helper/gateway-key
sudo -n systemctl restart homelab-model-helper.socket; sudo -n systemctl is-active homelab-model-helper.socket'
~~~

Expected `root:root 600`, non-zero bytes, mtime now, `active`.

## 7 — Call 4: new key, attended, with unattended exhausted (rows 13 and 3)

**OWNER** Phone `/spend` first: `unattended: hour $0.100000000 / $0.100000000` must still show
(else repeat §5). Paste.

**AGENT — call 4**

~~~bash
ssh homelab-agent 'M=/tmp/homelab-agent/p151-s3-call4.done; [ -e "$M" ] && { echo "STOP: call 4 already attempted"; exit 2; }
date -u +%FT%TZ | tee "$M"
curl -sS --max-time 300 -H "X-Homelab-Client: p151-s3-new-key-attended-independence" -H "Content-Type: application/json" \
  -d "{\"v\":1,\"kind\":\"question\",\"role\":\"utility\",\"question\":\"Reply with exactly S3-ROTATED-OK.\"}" \
  http://127.0.0.1:8766/v1/request; echo
sudo -n journalctl -u "homelab-model-helper@*" -n 4 --no-pager -o short-iso | grep -E "outcome=|spend"'
~~~

Expected: `"ok": true`, `provider: gateway`, `model: openai/gpt-5.6-luna`, `cost` ≈ `0.0000104`;
helper `outcome=ok … attended reserved $0.001310300`. **No fifth attempt for any reason.**

**OWNER** Browser once: request count +1 from §6's figure, the new request's tokens and cost.
Phone `/spend`: attended hour shows the settled cost; unattended hour still `0.10 / 0.10`. Paste
both.

## 8 — Rows 14–18 and restoration

**AGENT** (rows 15, 16, 14's mode)

~~~bash
ssh homelab-agent 'sudo -n systemd-analyze security homelab-model-helper@probe.service --no-pager | grep -i "overall exposure"
systemctl show homelab-model-helper@probe.service -p Environment --value | grep -c AI_GATEWAY_API_KEY
sudo -n stat -c "%n %U:%G %a" /etc/homelab-model-helper/gateway-key
sudo -n cat /etc/homelab-model-helper/config.json | sha256sum'
~~~

Expected `≤ 3.8`, `0`, `root:root 600`, the repo file's hash (standing config already installed
at §3).

**OWNER** as aleix (row 14's two denials; two sudo):

~~~bash
sudo -u homelab-bot cat /etc/homelab-model-helper/gateway-key >/dev/null 2>&1 && echo "FAIL: bot read key" || echo "ok: bot denied"
sudo -u homelab-harness cat /etc/homelab-model-helper/gateway-key >/dev/null 2>&1 && echo "FAIL: harness read key" || echo "ok: harness denied"
~~~

**AGENT** stop the helper. **OWNER** as aleix — restore the ledger keeping the real S3 lines
(call 3's `released` line and call 4's `settled` line), the orchestrator's "copy out, cp, re-add":

~~~bash
python3 -c 'import json; d=json.load(open("/var/lib/homelab-model-helper/spend.json")); real=[c for c in d["calls"][2:] if "synthetic" not in c]; json.dump(real, open("/home/aleix/p151-s3-real-lines.json","w")); print("kept", len(real), "real S3 lines:", [c["status"] for c in real])'
cp -p /var/lib/homelab-model-helper/spend.json.bak-2026-09-13-p151-s3 /var/lib/homelab-model-helper/spend.json
python3 -c '
import json; p="/var/lib/homelab-model-helper/spend.json"; d=json.load(open(p))
d["calls"] += json.load(open("/home/aleix/p151-s3-real-lines.json"))
assert not any("synthetic" in c for c in d["calls"])
fh=open(p,"w"); json.dump(d, fh, separators=(",",":")); fh.write("\n"); fh.close()
print("ledger calls:", len(d["calls"]), [c["status"] for c in d["calls"]])'
~~~

Expected `ledger calls: 4 ['settled', 'settled', 'released', 'settled']`.

**AGENT** stat + start. **OWNER** Phone: final `/spend` — standing ceilings, attended totals = the
two S2 lines + call 4, unattended all `$0`. Paste. Row 17: send `/ask 2+2` once; **AGENT** then
`sudo -n stat -c "%y" /var/lib/homelab-model-helper/spend.json` — mtime unchanged by `/ask`.
Row 18: `/spend` from a non-allowlisted Telegram id if one is at hand (refused); else S2's
evidence stands and the row is PREDICTED from the bot's allowlist.

Both `.bak-2026-09-13-p151-s3` files and `/home/aleix/p151-s3-real-lines.json` stay until S4.

## 9 — Reconciliation and final health

**OWNER** as aleix (content-free fields; no question text, no credential):

~~~bash
python3 -c '
import json
d=json.load(open("/var/lib/homelab-model-helper/spend.json"))
for c in d["calls"]:
    print({k: c.get(k) for k in ("request_id","budget","status","reserved_usd","settled_usd","gateway_cost","settle_note","release_reason","usage")})'
~~~

Browser: the dashboard's final request count and total spend for the phase (all requests since
S2's first), and the per-request cost column.

**AGENT**

~~~bash
ssh homelab-agent 'sudo -n systemctl is-system-running; sudo -n systemctl --failed
for u in homelab-model-helper.socket homelab-harness.service homelab-telegram-bot.service; do printf "%s " "$u"; sudo -n systemctl is-active "$u"; done
sudo -n stat -c "%n %U:%G %a %s bytes" /var/lib/homelab-model-helper/spend.json /etc/homelab-model-helper/config.json
ls -l /tmp/homelab-agent/'
~~~

Row 12, stated as **dashboard total vs ledger-minus-fail-closed-entries**, both figures:

~~~text
provider-reaching attempts in S3: 2 (calls 3, 4); locally refused: P1 P2 P3 [1] [2] 3a
dashboard total actual spend (phase):            $…
ledger sum, all settled lines:                   $…
fail-closed entries excluded (S2 403 settlement): $0.001310300
ledger minus fail-closed entries:                $…
reconciliation:                                  $… vs $…  (rounding rule: dashboard shows 5 decimals; ledger 9)
synthetic records: none remain; provider spend from them: $0
standing ceilings after restore (/spend):        pasted
~~~

This runbook ends when §9's evidence is captured. S4 follows the orchestrator's review.
