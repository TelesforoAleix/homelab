#!/usr/bin/env bash
# Phase 15.1 S2, row 10 -- exactly one metered request through the endpoint.
# Run on the node as aleix only after p151-s2-runbook.md rows 1-9 pass.
set -uo pipefail

RETRY=false
if [[ "${1:-}" == "--authorized-retry-after-credit" ]]; then
    RETRY=true
elif [[ $# -ne 0 ]]; then
    echo "usage: $0 [--authorized-retry-after-credit]"
    exit 2
fi

ENDPOINT="http://127.0.0.1:8766/v1/request"
MARKER="/tmp/p151-row10-attempted"
RESULT="/tmp/p151-row10-result.json"
LEDGER="/var/lib/homelab-model-helper/spend.json"

echo "== row 10 preflight: refreshing sudo (password prompt follows) =="
sudo -v || exit 1

echo "== row 10 machine preconditions: live route, expected ledger, active services =="
systemctl is-active --quiet homelab-model-helper.socket \
    homelab-harness.service homelab-telegram-bot.service || {
    echo "STOP: a required service is not active"
    exit 2
}
EXPECTED_CALLS=0
if [[ "$RETRY" == true ]]; then EXPECTED_CALLS=1; fi
sudo env P151_EXPECTED_CALLS="$EXPECTED_CALLS" python3 -c '
import os
import json
c=json.load(open("/etc/homelab-model-helper/config.json"))
d=json.load(open("/var/lib/homelab-model-helper/spend.json"))
assert c["routes"]["utility"] == ["gateway/luna"]
assert c["providers"]["gateway"]["models"]["luna"]["id"].startswith("openai/")
assert "vercel-ai-gateway:openai" in c["providers_approved"]
expected = int(os.environ["P151_EXPECTED_CALLS"])
assert d.get("version") == 1 and len(d.get("calls", [])) == expected
if expected:
    prior = d["calls"][-1]
    assert prior.get("status") == "settled"
    assert prior.get("provider") == "gateway" and prior.get("model") == "luna"
    assert prior.get("settle_note") == "call outcome or charge uncertain"
print("ok: utility route pinned to approved OpenAI vendor; expected ledger state present")
' || {
    echo "STOP: row 10 preconditions failed"
    exit 2
}

if [[ "$RETRY" == true ]]; then
    PRIOR_MARKER="${MARKER}.prior-403-credit"
    if [[ ! -e "$MARKER" ]]; then
        echo "STOP: no prior marker exists; authorized retry requires the recorded 403 attempt"
        exit 2
    fi
    if [[ -e "$PRIOR_MARKER" ]]; then
        echo "STOP: retry marker archive already exists; this retry was already prepared"
        exit 2
    fi
    mv "$MARKER" "$PRIOR_MARKER" || exit 1
    {
        echo "authorized-retry-reset $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "reason=credits-added-and-diagnostic-commit-4a0c9c4"
        echo "prior_marker=$PRIOR_MARKER"
    } > "$MARKER" || exit 1
    echo "ok: prior marker archived; retry reason recorded in $MARKER"
elif [[ -e "$MARKER" ]]; then
    echo "STOP: $MARKER exists. Row 10 has already been attempted on this boot."
    echo "Do not retry: a failed response can still represent billed work."
    exit 2
fi

echo "== recording the one-attempt marker before any request leaves =="
if [[ "$RETRY" == true ]]; then
    date -u '+retry-attempted %Y-%m-%dT%H:%M:%SZ' >> "$MARKER" || exit 1
else
    date -u '+attempted %Y-%m-%dT%H:%M:%SZ' > "$MARKER" || exit 1
fi
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
