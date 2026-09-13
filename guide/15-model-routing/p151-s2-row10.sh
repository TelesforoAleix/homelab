#!/usr/bin/env bash
# Phase 15.1 S2, row 10 -- exactly one metered request through the endpoint.
# Run on the node as aleix only after p151-s2-runbook.md rows 1-9 pass.
set -uo pipefail

ENDPOINT="http://127.0.0.1:8766/v1/request"
MARKER="/tmp/p151-row10-attempted"
RESULT="/tmp/p151-row10-result.json"
LEDGER="/var/lib/homelab-model-helper/spend.json"

echo "== row 10 preflight: refreshing sudo (password prompt follows) =="
sudo -v || exit 1

echo "== row 10 machine preconditions: live route, empty ledger, active services =="
systemctl is-active --quiet homelab-model-helper.socket \
    homelab-harness.service homelab-telegram-bot.service || {
    echo "STOP: a required service is not active"
    exit 2
}
sudo python3 -c '
import json
c=json.load(open("/etc/homelab-model-helper/config.json"))
d=json.load(open("/var/lib/homelab-model-helper/spend.json"))
assert c["routes"]["utility"] == ["gateway/luna"]
assert c["providers"]["gateway"]["models"]["luna"]["id"].startswith("openai/")
assert "vercel-ai-gateway:openai" in c["providers_approved"]
assert d.get("version") == 1 and d.get("calls") == []
print("ok: utility route pinned to approved OpenAI vendor; live ledger empty")
' || {
    echo "STOP: row 10 preconditions failed"
    exit 2
}

if [[ -e "$MARKER" ]]; then
    echo "STOP: $MARKER exists. Row 10 has already been attempted on this boot."
    echo "Do not retry: a failed response can still represent billed work."
    exit 2
fi

echo "== recording the one-attempt marker before any request leaves =="
date -u '+attempted %Y-%m-%dT%H:%M:%SZ' > "$MARKER" || exit 1
T0=$(date '+%Y-%m-%d %H:%M:%S')
echo "journal mark: $T0"

echo "== ROW 10: ONE REAL METERED CALL; there is no automatic retry =="
curl -sS --max-time 300 \
    -H 'X-Homelab-Client: p151-runbook' \
    -H 'Content-Type: application/json' \
    -d '{"v":1,"kind":"question","role":"utility","question":"What is two plus two? Reply with only the number."}' \
    "$ENDPOINT" > "$RESULT"
CURL_RC=$?
echo "curl rc=$CURL_RC"

if [[ -s "$RESULT" ]]; then
    echo "== endpoint response =="
    python3 -c 'import json; print(json.dumps(json.load(open("/tmp/p151-row10-result.json")), indent=2))'
else
    echo "NO RESPONSE BODY. This still counts as one real attempt; do not rerun."
fi

echo "== latest content-free spend-ledger record =="
sudo python3 -c 'import json; d=json.load(open("/var/lib/homelab-model-helper/spend.json")); print(json.dumps(d["calls"][-1] if d["calls"] else {"STOP":"ledger has no call"}, indent=2))'

echo "== endpoint audit line for p151-runbook =="
sudo grep '"client_declared":"p151-runbook"\|"client_declared": "p151-runbook"' \
    /var/lib/homelab-harness/audit.jsonl | tail -1

echo "== helper journal since the mark; question and credential are never logged =="
sudo journalctl -u 'homelab-model-helper@*' --since "$T0" --no-pager -o cat

echo "== ROW 10 ATTEMPT COMPLETE: count it as one real gateway call regardless of outcome =="
echo "Now check the Vercel dashboard once and send /spend in Telegram. Do not rerun this script."
exit "$CURL_RC"
