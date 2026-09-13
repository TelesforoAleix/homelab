# Phase 15.1 — S3 runbook (governor proof and reconciliation)

One owner session. Every command prints before it can wait. sudo -v is the first sudo operation; there is no piped sudo prompt. This runbook never prints, pastes, or passes the gateway credential. It changes only helper configuration and the local spend ledger, both backed up before mutation and restored at the end.

**Class:** ordinary user-space service/configuration work only: no network, remote-access, authentication, boot, firewall, admin-account, volume, reboot, or second-session change.

**Real-call budget:** at most **four** real endpoint attempts occur in S3: (1) attended-hour refusal, (2) unattended-hour refusal, (3) revoked-key 401, (4) new-key success. Calls 1 and 2 must be refused before a provider request; calls 3 and 4 can reach the provider. Call 4 deliberately runs with synthetic unattended exhaustion in place, so it also proves attended/unattended independence. All other exercises use the fake-gateway fixture, local config/ledger operations, or /spend; they make no provider request. Record every endpoint attempt below before continuing.

Terminals: **S1** = ssh homelab; **Phone** = Telegram; **Browser** = AI Gateway dashboard (observation plus owner key revoke/create only).

## 0 — Baseline, rollback, and call ledger (S1, Browser)

Browser: record dashboard request count and actual spend before S3. Do not paste a key, account/team identifier, token-bearing URL, or a screenshot containing personal data.

~~~bash
[ "$(hostname)" = homelab ] || { echo "STOP: not on the node"; false; }
echo "== refreshing sudo (password prompt follows) =="
sudo -v
echo "== baseline health =="
systemctl --failed
systemctl is-system-running
systemctl is-active homelab-model-helper.socket homelab-telegram-bot.service homelab-harness.service
S3STAMP=$(date +%F)-p151-s3
S3CFGBAK=/etc/homelab-model-helper/config.json.bak-$S3STAMP
S3LEDBAK=/var/lib/homelab-model-helper/spend.json.bak-$S3STAMP
echo "== refusing overwrite of S3 rollback copies =="
for p in "$S3CFGBAK" "$S3LEDBAK"; do
  if sudo test -e "$p"; then echo "STOP: already exists: $p"; false; fi
done
echo "== stop helper before consistent ledger copy; no request =="
sudo systemctl stop homelab-model-helper.socket
sudo systemctl is-active homelab-model-helper.socket && { echo "STOP: socket still active"; false; } || true
sudo cp -p /etc/homelab-model-helper/config.json "$S3CFGBAK"
sudo cp -p /var/lib/homelab-model-helper/spend.json "$S3LEDBAK"
sudo stat -c '%n %U:%G %a %s bytes' "$S3CFGBAK" "$S3LEDBAK"
echo "== restart helper after backup =="
sudo systemctl start homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket
echo "== PHONE NOW: send /spend; paste all eight figures and standing ceilings =="
~~~

Stop if any unit is failed, either backup cannot be made, or /spend does not show standing figures.

~~~text
S3 real endpoint calls (maximum 4)
1. attended-hour refusal: [time, result, dashboard unchanged]
2. unattended-hour refusal: [time, result, dashboard unchanged]
3. revoked homelab key: [time, 401/provider_error type+code, dashboard result]
4. new homelab key / attended independence: [time, ok, dashboard result]
~~~

## 1 — Fake proof for rows 1–8 (S1)

The installed fixture is the no-cost proof for reservation, release on 429 (row 7), persist/restart and stale release (row 5), malformed/unreadable ledger refusal, registry validation, and request pin/body restriction. It makes no external call.

~~~bash
echo "== node fake-gateway fixture; no external calls =="
sudo env SRC=/tmp/homelab-p151/helper \
  bash /tmp/homelab-p151/helper/install-model-helper.sh verify
~~~

Stop unless the verifier passes all its governor checks. It is the proof for row 5 and row 7 without consuming the real-call budget.

## 2 — Lower only hour ceilings via backed-up config (S1)

Show the fields first. In the editor, preserve providers, prices, routes, approved vendor list, and all day/week/month figures. Lower only attended-hour and unattended-hour monetary ceilings below already-accounted ledger spend; record old and temporary values.

~~~bash
echo "== show candidate ceiling fields; values only, no credential =="
sudo python3 -c '
import json
d=json.load(open("/etc/homelab-model-helper/config.json"))
def walk(x,p=""):
    if isinstance(x,dict):
        for k,v in x.items(): walk(v,p+"."+k if p else k)
    elif isinstance(x,list):
        for i,v in enumerate(x): walk(v,f"{p}[{i}]")
    elif any(w in p.lower() for w in ("ceiling","limit","hour","attended","unattended")):
        print(f"{p} = {x!r}")
walk(d)
'
echo "== editor opens next: lower attended-hour and unattended-hour only =="
sudoedit /etc/homelab-model-helper/config.json
echo "== parse edited config; no request =="
sudo python3 -m json.tool /etc/homelab-model-helper/config.json >/dev/null && echo "json syntax ok"
echo "== restart helper to load temporary hour ceilings =="
sudo systemctl restart homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket
echo "== PHONE NOW: send /spend; confirm temp hour values and unchanged day/week/month =="
~~~

Stop if /spend does not visibly confirm this exact scope.

## 3 — Two real hour refusals (S1, Phone, Browser)

Record dashboard count/spend before each. Each local endpoint attempt counts as a real call even though the expected governor refusal prevents a provider request. Do not retry either command.

~~~bash
echo "== REAL CALL 1 OF 4: attended hour; expect governor refusal, no provider request =="
curl -sS --max-time 300 \
  -H 'X-Homelab-Client: p151-s3-attended-hour' \
  -H 'Content-Type: application/json' \
  -d '{"v":1,"kind":"question","role":"utility","question":"Reply with exactly S3-HOUR-ATTENDED."}' \
  http://127.0.0.1:8766/v1/request
echo
echo "== STOP: record call 1, refresh dashboard once, then send /spend =="
~~~

Expected: refusal names attended hour and its figures; dashboard count/spend unchanged; no new provider cost.

~~~bash
echo "== REAL CALL 2 OF 4: unattended hour; expect governor refusal, no provider request =="
curl -sS --max-time 300 \
  -H 'X-Homelab-Client: p151-s3-unattended-hour' \
  -H 'Content-Type: application/json' \
  -d '{"v":1,"kind":"question","role":"utility-unattended","question":"Reply with exactly S3-HOUR-UNATTENDED."}' \
  http://127.0.0.1:8766/v1/request
echo
echo "== STOP: record call 2, refresh dashboard once, then send /spend =="
~~~

Expected: refusal names unattended hour figures, attended figures unchanged, dashboard unchanged. Stop on ok, any dashboard increment, or unexpected error.

## 4 — Day/week/month synthetic ledger refusals (S1)

These are **synthetic ledger tests, not real calls**. For each window separately, stop helper, restore the pristine S3 ledger backup, edit a prior **settled** total above that window's ceiling in the correct bucket and rolling time, label it p151-s3-synthetic-window, start helper, and prove refusal/raised-ceiling positive control with the fake fixture. Never carry synthetic entries forward.

~~~bash
echo "== SYNTHETIC DAY: helper stopped before ledger edit; no request =="
sudo systemctl stop homelab-model-helper.socket
sudo cp -p "$S3LEDBAK" /var/lib/homelab-model-helper/spend.json
echo "== editor opens: add only p151-s3-synthetic-day above day ceiling =="
sudoedit /var/lib/homelab-model-helper/spend.json
sudo chown aleix:aleix /var/lib/homelab-model-helper/spend.json
sudo chmod 0600 /var/lib/homelab-model-helper/spend.json
sudo systemctl start homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket
echo "== fake day refusal and raised-ceiling control; external calls 0 =="
sudo env SRC=/tmp/homelab-p151/helper bash /tmp/homelab-p151/helper/install-model-helper.sh verify

echo "== SYNTHETIC WEEK: stop, restore, edit only p151-s3-synthetic-week above week ceiling =="
sudo systemctl stop homelab-model-helper.socket
sudo cp -p "$S3LEDBAK" /var/lib/homelab-model-helper/spend.json
sudoedit /var/lib/homelab-model-helper/spend.json
sudo chown aleix:aleix /var/lib/homelab-model-helper/spend.json
sudo chmod 0600 /var/lib/homelab-model-helper/spend.json
sudo systemctl start homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket
echo "== fake week refusal and raised-ceiling control; external calls 0 =="
sudo env SRC=/tmp/homelab-p151/helper bash /tmp/homelab-p151/helper/install-model-helper.sh verify

echo "== SYNTHETIC MONTH: stop, restore, edit only p151-s3-synthetic-month above month ceiling =="
sudo systemctl stop homelab-model-helper.socket
sudo cp -p "$S3LEDBAK" /var/lib/homelab-model-helper/spend.json
sudoedit /var/lib/homelab-model-helper/spend.json
sudo chown aleix:aleix /var/lib/homelab-model-helper/spend.json
sudo chmod 0600 /var/lib/homelab-model-helper/spend.json
sudo systemctl start homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket
echo "== fake month refusal and raised-ceiling control; external calls 0 =="
sudo env SRC=/tmp/homelab-p151/helper bash /tmp/homelab-p151/helper/install-model-helper.sh verify
~~~

For each window record its synthetic label, total, ceiling, refusal, and positive control. Stop if the edit is unclear; synthetic local totals are never provider spend.

## 5 — Synthetic unattended exhaustion; rows 4 and 6 make no request (S1)

Restore the real backup, then create a labelled synthetic unattended-hour exhaustion only. Leave attended capacity and all other windows below standing ceilings; it will remain for call 4.

~~~bash
echo "== SYNTHETIC unattended exhaustion for independence; no request =="
sudo systemctl stop homelab-model-helper.socket
sudo cp -p "$S3LEDBAK" /var/lib/homelab-model-helper/spend.json
echo "== editor opens: add only p151-s3-synthetic-unattended-hour above unattended hour; leave attended capacity =="
sudoedit /var/lib/homelab-model-helper/spend.json
sudo chown aleix:aleix /var/lib/homelab-model-helper/spend.json
sudo chmod 0600 /var/lib/homelab-model-helper/spend.json
sudo systemctl start homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket

echo "== ROW 4: unreadable ledger; fake governor_unavailable proof; NO REQUEST =="
sudo chmod 000 /var/lib/homelab-model-helper/spend.json
sudo env SRC=/tmp/homelab-p151/helper bash /tmp/homelab-p151/helper/install-model-helper.sh verify
sudo chmod 0600 /var/lib/homelab-model-helper/spend.json
sudo chown aleix:aleix /var/lib/homelab-model-helper/spend.json
echo "== ROW 6: fake incomplete-price/unapproved-vendor config-load refusal; NO REQUEST =="
sudo env SRC=/tmp/homelab-p151/helper bash /tmp/homelab-p151/helper/install-model-helper.sh verify
~~~

Row 4 must show kind governor_unavailable and zero fake requests. Row 6 must name the model and missing price field (or vendor rejection). Neither may call the live endpoint or dashboard.

## 6 — Revocation rehearsal and key rotation (Browser, S1)

Browser, owner only: revoke **only** the homelab key. Confirm revocation and record dashboard count/spend.

~~~bash
echo "== REAL CALL 3 OF 4: revoked homelab key; expect 401 provider_error, no cost =="
curl -sS --max-time 300 \
  -H 'X-Homelab-Client: p151-s3-revoked-key' \
  -H 'Content-Type: application/json' \
  -d '{"v":1,"kind":"question","role":"utility","question":"Reply with exactly S3-REVOKED."}' \
  http://127.0.0.1:8766/v1/request
echo
echo "== STOP: record call 3; refresh dashboard once; retain only validated error type/code =="
~~~

Expected: HTTP 401 surfaced as kind provider_error with provider error type and code logged, no cost. Never log error message, param, question text, or key material. Record the dashboard observation; do not assume a 401 is invisible there.

Browser, owner only: create a replacement key called homelab, with the same **$10/week** budget. Verify scope/budget before installation. On S1, use the installer editor only:

~~~bash
echo "== editor opens: replace only revoked key with new homelab key =="
sudo env SRC=/tmp/homelab-p151/helper \
  bash /tmp/homelab-p151/helper/install-model-helper.sh credential
echo "== metadata only; no credential content =="
sudo stat -c '%n %U:%G %a %s bytes' /etc/homelab-model-helper/gateway-key
echo "== restart helper after rotation =="
sudo systemctl restart homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket
~~~

Stop unless credential remains root:root 600, non-zero bytes, and dashboard confirms $10/week for the new key.

## 7 — Post-rotation success and independence (S1, Browser, Phone)

Synthetic unattended exhaustion remains present; attended capacity remains available. This one success proves both row 13 replacement-key path and row 3 independence.

~~~bash
echo "== REAL CALL 4 OF 4: new key attended route; expect ok and one provider request =="
curl -sS --max-time 300 \
  -H 'X-Homelab-Client: p151-s3-new-key-attended-independence' \
  -H 'Content-Type: application/json' \
  -d '{"v":1,"kind":"question","role":"utility","question":"Reply with exactly S3-ROTATED-OK."}' \
  http://127.0.0.1:8766/v1/request
echo
echo "== STOP: record call 4, refresh dashboard once, then send /spend =="
~~~

Expected: ok; dashboard increments exactly once from its call-4 baseline; /spend settles the call. No fifth real call is authorized for any reason.

## 8 — Rows 14–18 and restoration (S1, Phone)

These make no gateway request. For row 17, retain the S2 observed proof that Telegram /ask and endpoint execution-agent were free and ledger-unchanged; do not repeat them after exhausting the S3 four-call allowance.

~~~bash
echo "== row 14: credential boundary, content suppressed =="
sudo -u homelab-bot cat /etc/homelab-model-helper/gateway-key >/dev/null 2>&1 && { echo "FAIL: bot read key"; false; } || echo "ok: bot denied"
sudo -u homelab-harness cat /etc/homelab-model-helper/gateway-key >/dev/null 2>&1 && { echo "FAIL: harness read key"; false; } || echo "ok: harness denied"
sudo stat -c '%n %U:%G %a' /etc/homelab-model-helper/gateway-key
echo "== row 15: security score, expect <= 3.8 =="
sudo systemd-analyze security 'homelab-model-helper@probe.service' --no-pager | grep -i 'overall exposure'
echo "== row 16: no forbidden environment variable =="
systemctl show 'homelab-model-helper@probe.service' -p Environment --value | grep -q 'AI_GATEWAY_API_KEY' && { echo "FAIL: forbidden variable"; false; } || echo "ok: no forbidden variable"
echo "== PHONE NOW: owner sends /spend; record eight figures; test non-allowlisted refusal without forwarding =="
echo "== stop helper and restore standing config =="
sudo systemctl stop homelab-model-helper.socket
sudo cp -p "$S3CFGBAK" /etc/homelab-model-helper/config.json
echo "== restore real ledger source, then editor opens: retain only real settled call-4 record; delete every synthetic row =="
sudo cp -p "$S3LEDBAK" /var/lib/homelab-model-helper/spend.json
sudoedit /var/lib/homelab-model-helper/spend.json
sudo chown aleix:aleix /var/lib/homelab-model-helper/spend.json
sudo chmod 0600 /var/lib/homelab-model-helper/spend.json
sudo systemctl start homelab-model-helper.socket
systemctl is-active homelab-model-helper.socket
echo "== PHONE NOW: final /spend; standing ceilings must be restored =="
~~~

Stop if final /spend does not show standing ceilings. The final ledger contains only real S2/S3 accounting; preserve both .bak files until S4.

## 9 — Reconciliation and paste-back (Browser, S1)

Reconcile explicitly as **dashboard total vs ledger-minus-fail-closed-entries**. Fail-closed/uncertain local settlements are conservative budget state, not claimed provider charges; show their value separately. Compare to cents and state unrounded figures and rounding rule.

~~~bash
echo "== final health =="
systemctl --failed
systemctl is-system-running
systemctl is-active homelab-model-helper.socket homelab-telegram-bot.service homelab-harness.service
echo "== final ledger metadata only =="
sudo stat -c '%n %U:%G %a %s bytes' /var/lib/homelab-model-helper/spend.json
echo "== reconciliation fields only: ids/status/totals, never question or credential =="
sudo python3 -c '
import json
d=json.load(open("/var/lib/homelab-model-helper/spend.json"))
for c in d.get("calls",[]):
 print({k:c.get(k) for k in ("request_id","status","reserved","settled","gateway_cost","cost","synthetic")})
'
~~~

~~~text
S3 real endpoint calls: 4 (calls 1–4; no others)
dashboard total actual spend: $...
ledger total: $...
fail-closed/uncertain ledger entries excluded: $...
ledger minus fail-closed entries: $...
reconciliation (dashboard total vs ledger-minus-fail-closed-entries): $... vs $...
difference and rounding rule: ...
synthetic day/week/month/unattended tests: removed before final state; no provider spend
standing ceilings after restore (/spend): ...
~~~

Do not proceed to S4 here. This runbook ends after the evidence is captured.
