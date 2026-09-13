# Phase 15.1 — S2 runbook (node install and first metered call)

One owner session. Every command prints before it can wait. `sudo -v` is the first sudo operation;
there is no piped sudo prompt. The gateway credential is entered only in the editor opened by the
installer. It is never supplied to a shell command, script stdin, environment value, journal, git,
or this report.

**Class:** ordinary under `safe-changes-headless.md` and brief §7.4. This changes existing
user-space helper, harness, and bot code, plus a helper service drop-in. It does not change
networking, remote access, authentication, boot dependencies, the admin account, firewall, or the
data volume. No reboot and no second session are required. Rollback is staged before mutation.

**Call accounting:** the fake fixtures make no external calls. The regression checks make two
subscription calls: one Telegram `/ask`, one endpoint `execution-agent`. Row 10 makes exactly one
metered gateway request. A single-use marker prevents an accidental second row-10 attempt. Do not
retry row 10 even if its response is missing or unsuccessful: the request may still have been billed.

Terminals:

- **T** — MacBook, `/Users/home/Code/homelab-p151`.
- **S1** — `ssh homelab`.
- **Phone** — Telegram.
- **Browser** — Vercel AI Gateway dashboard, used only to observe request count/spend.

## 0 — Local proof and staging (T)

```bash
echo "== branch and commits (expect phase/15.1-work; 3289b5b above 55caa4f) =="
git status --short --branch
git log -2 --oneline

echo "== local fake-gateway fixture: expect All 36 checks passed, external calls 0 =="
python3 services/model-helper/fixture-tests.py
echo "== local endpoint regression: expect All 64 checks passed =="
python3 services/homelab-harness/fixture-tests.py

echo "== stage S2 files on the node; no credential is in this transfer =="
ssh homelab 'mkdir -p /tmp/homelab-p151/helper /tmp/homelab-p151/bot /tmp/p151-rollback'
scp services/model-helper/helper.py services/model-helper/providers.py \
    services/model-helper/limits.py services/model-helper/spend.py \
    services/model-helper/socket-probe.py services/model-helper/fixture-tests.py \
    services/model-helper/config.example.json scripts/server/install-model-helper.sh \
    config/systemd/homelab-model-helper.socket \
    config/systemd/homelab-model-helper@.service \
    config/systemd/homelab-model-helper@.service.d/credential.conf \
    homelab:/tmp/homelab-p151/helper/
scp services/telegram-bot/bot.py services/telegram-bot/router.py \
    services/telegram-bot/executors.py services/telegram-bot/model_client.py \
    scripts/server/verify-telegram-bot.sh homelab:/tmp/homelab-p151/bot/
ssh homelab 'mkdir -p /tmp/homelab-p151/harness'
scp services/homelab-harness/harness.py services/homelab-harness/classify.py \
    services/homelab-harness/fixture-tests.py services/homelab-harness/config.example.json \
    scripts/server/install-homelab-harness.sh \
    config/systemd/homelab-harness.service \
    config/systemd/homelab-harness.service.d/onfailure.conf \
    homelab:/tmp/homelab-p151/harness/
scp guide/15.1-gateway-and-spend-governor/s2-row10.sh homelab:/tmp/homelab-p151/
ssh homelab 'ls -l /tmp/homelab-p151/helper /tmp/homelab-p151/bot /tmp/homelab-p151/harness /tmp/homelab-p151/p151-s2-row10.sh'
```

Stop if either local suite fails.

## 1 — Baseline and rollback (S1)

```bash
[ "$(hostname)" = homelab ] || { echo "STOP: not on the node"; false; }
echo "== refreshing sudo (password prompt follows) =="
sudo -v

echo "== baseline health =="
systemctl --failed
systemctl is-system-running
echo "== helper score BEFORE credential drop-in =="
sudo systemd-analyze security 'homelab-model-helper@probe.service' --no-pager \
    | grep -i 'overall exposure' | tee /tmp/p151-score-before
echo "== existing service state =="
systemctl is-active homelab-model-helper.socket homelab-telegram-bot.service homelab-harness.service

echo "== S2 must start without its three new live files =="
for p in /etc/homelab-model-helper/gateway-key \
         /var/lib/homelab-model-helper/spend.json \
         /etc/systemd/system/homelab-model-helper@.service.d/credential.conf; do
  if sudo test -e "$p"; then echo "STOP: unexpected pre-existing $p"; false; else echo "absent as expected: $p"; fi
done

echo "== stage rollback copies before mutation =="
sudo install -d -o root -g root -m 0700 \
  /tmp/p151-rollback/helper /tmp/p151-rollback/bot /tmp/p151-rollback/harness
for f in helper.py providers.py limits.py fixture-tests.py config.example.json socket-probe.py; do
  sudo cp -p "/opt/homelab-model-helper/$f" "/tmp/p151-rollback/helper/$f"
done
for f in bot.py router.py executors.py model_client.py; do
  sudo cp -p "/opt/homelab-telegram-bot/$f" "/tmp/p151-rollback/bot/$f"
done
for f in harness.py classify.py fixture-tests.py config.example.json; do
  sudo cp -p "/opt/homelab-harness/$f" "/tmp/p151-rollback/harness/$f"
done
sudo cp -p /etc/homelab-model-helper/config.json /tmp/p151-rollback/config.json
sudo ls -l /tmp/p151-rollback/helper /tmp/p151-rollback/bot \
  /tmp/p151-rollback/harness /tmp/p151-rollback/config.json
```

If any supposedly new file already exists, stop and paste the finding; do not overwrite unknown
state.

## 2 — Credential through an editor only (S1)

```bash
echo "== editor opens next: paste the gateway key there, save, exit =="
sudo env SRC=/tmp/homelab-p151/helper \
    bash /tmp/homelab-p151/helper/install-model-helper.sh credential
echo "== credential metadata only; content is never printed =="
sudo stat -c '%n %U:%G %a %s bytes' /etc/homelab-model-helper/gateway-key
```

Expected: `root:root 600`, non-zero bytes. Do not run `cat`, `head`, shell substitution, or an
environment assignment against this file.

## 3 — Prepare and validate the new config (S1)

```bash
echo "== write config.json.new from the committed Phase 15.1 example =="
sudo install -o root -g root -m 0644 \
    /tmp/homelab-p151/helper/config.example.json \
    /etc/homelab-model-helper/config.json.new

echo "== compare inherited subscription behavior before the swap =="
sudo python3 -c '
import json
old=json.load(open("/etc/homelab-model-helper/config.json"))
new=json.load(open("/etc/homelab-model-helper/config.json.new"))
for p,k in (("claude","haiku"),("codex","mini")):
    assert old["providers"][p]["bin"] == new["providers"][p]["bin"], p+" bin changed"
    assert old["providers"][p]["models"][k]["id"] == new["providers"][p]["models"][k]["id"], p+" model changed"
for route in ("owner-interactive","execution-agent"):
    assert old["routes"][route] == new["routes"][route], route+" changed"
assert new["routes"]["utility"] == ["gateway/luna"]
assert new["providers_approved"] == ["anthropic-cli","openai-cli","vercel-ai-gateway:openai"]
print("subscription providers/routes unchanged; utility=gateway/luna; approved list exact")
'

echo "== staged new code loads staged config using ping: no model call =="
echo '{"v":1,"op":"ping"}' | \
  HOMELAB_MODEL_HELPER_CONFIG=/etc/homelab-model-helper/config.json.new \
  python3 /tmp/homelab-p151/helper/helper.py

BAK=/etc/homelab-model-helper/config.json.bak-$(date +%F)-p151
echo "== durable config rollback: $BAK; refusing overwrite =="
if sudo test -e "$BAK"; then
  echo "STOP: $BAK already exists"
  false
else
  sudo cp -p /etc/homelab-model-helper/config.json "$BAK"
  sudo ls -l "$BAK"
fi
```

The pipe above contains only a public ping object. `sudo -v` already ran; no credential or sudo
prompt crosses a pipe.

## 4 — Atomic code/config swap, helper install, node fake-gateway proof (S1)

```bash
echo "== install compatible code, then atomically activate config; no network call =="
sudo bash -c '
set -e
for f in helper.py providers.py limits.py spend.py socket-probe.py fixture-tests.py config.example.json; do
  install -o root -g root -m 0644 "/tmp/homelab-p151/helper/$f" "/opt/homelab-model-helper/$f"
done
mv /etc/homelab-model-helper/config.json.new /etc/homelab-model-helper/config.json
'

echo "== install ledger and credential drop-in, daemon-reload, then verify =="
sudo env SRC=/tmp/homelab-p151/helper \
    bash /tmp/homelab-p151/helper/install-model-helper.sh install

echo "== explicit node fixture evidence: expect rows 1-8 and All 36 checks passed above =="
echo "== helper score AFTER LoadCredential: expect <=3.8 =="
sudo systemd-analyze security 'homelab-model-helper@probe.service' --no-pager \
    | grep -i 'overall exposure' | tee /tmp/p151-score-after
echo "== score comparison =="
diff -u /tmp/p151-score-before /tmp/p151-score-after || true
echo "== running unit has the credential mapping and 270-second ceiling =="
systemctl show 'homelab-model-helper@probe.service' -p LoadCredential -p RuntimeMaxUSec
```

Stop unless the installer ends `All checks passed`, its embedded fixture prints every row 1–8 and
`All 36 checks passed`, and the score is no worse than 3.8.

## 5 — Deploy endpoint correlation/cost and `/spend` without changing units (S1, Phone)

```bash
echo "== install all four harness modules together, then restart the existing service =="
for f in harness.py classify.py fixture-tests.py config.example.json; do
  sudo install -o root -g root -m 0644 "/tmp/homelab-p151/harness/$f" "/opt/homelab-harness/$f"
done
sudo systemctl restart homelab-harness.service
sleep 2
systemctl is-active homelab-harness.service
echo "== endpoint node regression: expect All 64 checks passed, no external call =="
sudo env SRC=/tmp/homelab-p151/harness \
  bash /tmp/homelab-p151/harness/install-homelab-harness.sh verify

echo "== install all four bot modules together, then restart the existing service =="
for f in bot.py router.py executors.py model_client.py; do
  sudo install -o root -g root -m 0644 "/tmp/homelab-p151/bot/$f" "/opt/homelab-telegram-bot/$f"
done
sudo systemctl restart homelab-telegram-bot.service
sleep 2
systemctl is-active homelab-telegram-bot.service
echo "== code is root-owned; bot cannot rewrite it =="
sudo stat -c '%n %U:%G %a' /opt/homelab-telegram-bot/{bot.py,router.py,executors.py,model_client.py}
```

Phone: send `/spend`. Expected: eight zero figures, the configured ceilings, and zero metered calls.
Paste the reply. Do not put the credential or any dashboard secret in the paste.

## 6 — Credential boundary and environment (S1)

```bash
echo "== source credential permission refusals; content suppressed =="
if sudo -u homelab-bot cat /etc/homelab-model-helper/gateway-key >/dev/null 2>&1; then
  echo "FAIL: homelab-bot read the key"
else
  echo "ok: homelab-bot permission denied"
fi
if sudo -u homelab-harness cat /etc/homelab-model-helper/gateway-key >/dev/null 2>&1; then
  echo "FAIL: homelab-harness read the key"
else
  echo "ok: homelab-harness permission denied"
fi
echo "== helper unit environment must not contain a gateway-key variable =="
if systemctl show 'homelab-model-helper@probe.service' -p Environment --value \
     | grep -q 'AI_GATEWAY_API_KEY'; then
  echo "FAIL: forbidden gateway-key environment variable present"
else
  echo "ok: no gateway-key environment variable"
fi
sudo stat -c '%n %U:%G %a' /etc/homelab-model-helper/gateway-key
```

## 7 — Free regressions before row 10 (S1, Phone)

```bash
echo "== live spend ledger before two subscription calls =="
sudo stat -c '%Y %s' /var/lib/homelab-model-helper/spend.json | tee /tmp/p151-spend-before
sudo python3 -c 'import json; d=json.load(open("/var/lib/homelab-model-helper/spend.json")); print("metered ledger calls",len(d["calls"]))'
echo "== PHONE NOW: send /ask Reply with exactly FREE and paste its reply before continuing =="
```

After `/ask` succeeds:

```bash
echo "== execution-agent endpoint regression: one SUBSCRIPTION call =="
curl -sS --max-time 300 \
  -H 'X-Homelab-Client: p151-regression' \
  -H 'Content-Type: application/json' \
  -d '{"v":1,"kind":"question","role":"execution-agent","question":"Reply with exactly FREE."}' \
  http://127.0.0.1:8766/v1/request
echo
echo "== spend ledger must be byte/mtime unchanged by both free routes =="
sudo stat -c '%Y %s' /var/lib/homelab-model-helper/spend.json | diff /tmp/p151-spend-before - \
  && echo "ok: spend ledger untouched"
```

Stop if either call fails, if either response names `gateway`, or if `spend.json` changed. At this
point the session has made two real subscription calls and zero metered calls.

## 8 — Row 10: the one real metered call (Browser, S1, Phone)

Browser first: open the AI Gateway dashboard and record its current request count and spend. State
the figures in the paste, but do not paste a key, account id, URL containing a token, or screenshot
with personal data. The expected S2 baseline is zero gateway requests from this phase.

Phone: send `/spend` once more; it must still show zero metered calls.

Then, exactly once:

```bash
echo "== running the single-use row-10 script: ONE REAL GATEWAY ATTEMPT =="
bash /tmp/homelab-p151/p151-s2-row10.sh
```

Do not rerun the script for any reason. It writes `/tmp/p151-row10-attempted` before `curl`; an
error or absent response is still counted as one real gateway attempt and needs diagnosis against
the ledger/dashboard before another call can ever be authorized.

Afterward:

1. Browser: refresh once. Expected request count increases by exactly one; record dashboard spend.
2. Phone: send `/spend`. Expected metered calls this week `1` and attended spend above zero.
3. Paste the script output, dashboard before/after figures, and `/spend` reply.

### Authorized retry after the 403 diagnostic

This is a separate owner authorization from the first row-10 attempt. It is allowed only after the
dashboard facts are recorded: **OBSERVED** on 2026-09-13, the team had no prepaid balance; the owner
added `$10.00`; the resulting balance is `$10.00` prepaid; and the `homelab` key remains at its
`$10/week` budget with no other displayed scope. Zero Data Retention is not required under the
accepted ADR-039 §1 decision.

On T, transfer only the committed diagnostic code and fixture. This contains no credential:

```bash
scp services/model-helper/helper.py services/model-helper/providers.py \
    services/model-helper/fixture-tests.py \
    homelab:/tmp/homelab-p151/helper/
scp guide/15.1-gateway-and-spend-governor/s2-row10.sh homelab:/tmp/homelab-p151/
```

On S1, install and verify before any request leaves the node:

```bash
echo "== install diagnostic helper code; no network call =="
for f in helper.py providers.py fixture-tests.py; do
  sudo install -o root -g root -m 0644 "/tmp/homelab-p151/helper/$f" "/opt/homelab-model-helper/$f"
done
sudo env SRC=/tmp/homelab-p151/helper \
  bash /tmp/homelab-p151/helper/install-model-helper.sh verify
```

Expected: the helper verifier's fixture ends `All 36 checks passed`, including the synthetic error
redaction check. Stop if it fails. The verifier makes no gateway call.

Before the retry, record the dashboard's current request count (`1`) and spend (`$0.0000`). Then
run this exactly once; the argument archives the prior marker and records the credit-fix reason in
the new marker. It requires exactly one prior uncertain settled gateway record and refuses any
second retry:

```bash
echo "== ONE AUTHORIZED RETRY after prepaid credit and diagnostic commit =="
bash /tmp/homelab-p151/helper/p151-s2-row10.sh --authorized-retry-after-credit
```

Refresh the dashboard once and send `/spend`. Paste the script output, the dashboard request/usage/
cost figures, and the `/spend` reply. If this attempt returns any error, stop; paste only the
journal's validated `gateway_error_type` and `gateway_error_code`. No third attempt is authorized.

## 9 — Health and paste-back (S1, T)

```bash
echo "== S2 final node health =="
systemctl --failed
systemctl is-system-running
systemctl is-active homelab-model-helper.socket homelab-telegram-bot.service homelab-harness.service
echo "== scores =="
cat /tmp/p151-score-before /tmp/p151-score-after
echo "== real gateway attempt marker =="
cat /tmp/p151-row10-attempted
echo "== live files, metadata only =="
sudo stat -c '%n %U:%G %a %s bytes' \
  /etc/homelab-model-helper/gateway-key \
  /var/lib/homelab-model-helper/spend.json \
  /etc/systemd/system/homelab-model-helper@.service.d/credential.conf
```

```bash
echo "== backup source and verifier name all three Phase 15.1 paths =="
if command -v rg >/dev/null 2>&1; then
  rg -n 'gateway-key|spend.json|credential.conf' \
    scripts/macos/backup-node.sh scripts/macos/verify-node-backup.sh
else
  grep -nE 'gateway-key|spend\.json|credential\.conf' \
    scripts/macos/backup-node.sh scripts/macos/verify-node-backup.sh
fi
```

The fallback is intentional: the S2 reference Mac did not have `rg`. There is no leading comment
inside the paste block because interactive zsh does not necessarily enable `interactivecomments`.

Paste back all outputs from steps 1–9, both Telegram replies, and the dashboard's numeric
before/after request count and spend. Label the call count explicitly:

```text
subscription calls in S2: 2
real gateway attempts in S2: 1
```

## Rollback — only if directed

This preserves the paid ledger beside the old code rather than deleting its only record.

```bash
echo "== refreshing sudo for rollback (password prompt follows) =="
sudo -v
echo "== preserve S2 ledger, restore old config/helper/bot, remove exact new surfaces =="
sudo mv /var/lib/homelab-model-helper/spend.json \
  /var/lib/homelab-model-helper/spend.json.p151-rollback-$(date +%F)
sudo cp -p /tmp/p151-rollback/config.json /etc/homelab-model-helper/config.json
for f in helper.py providers.py limits.py fixture-tests.py config.example.json socket-probe.py; do
  sudo cp -p "/tmp/p151-rollback/helper/$f" "/opt/homelab-model-helper/$f"
done
for f in bot.py router.py executors.py model_client.py; do
  sudo cp -p "/tmp/p151-rollback/bot/$f" "/opt/homelab-telegram-bot/$f"
done
for f in harness.py classify.py fixture-tests.py config.example.json; do
  sudo cp -p "/tmp/p151-rollback/harness/$f" "/opt/homelab-harness/$f"
done
sudo rm /opt/homelab-model-helper/spend.py
sudo rm /etc/systemd/system/homelab-model-helper@.service.d/credential.conf
sudo rm /etc/homelab-model-helper/gateway-key
sudo systemctl daemon-reload
sudo systemctl restart homelab-telegram-bot.service
sudo systemctl restart homelab-harness.service
systemctl --failed
systemctl is-system-running
```

The credential remains in the owner's password manager. If rollback was caused by suspected
credential exposure, revoke it in Vercel AI Gateway before doing anything else.
