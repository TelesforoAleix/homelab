#!/usr/bin/env bash
#
# configure-telegram-bot-profile.sh
#
# Sets what the bot LOOKS LIKE in a Telegram client: its name, its two
# descriptions, and -- the useful part on a phone -- its command list, so the
# client offers autocomplete instead of requiring you to remember /ask.
#
# THE COMMAND LIST IS DERIVED FROM THE ROUTER REGISTRY
# ----------------------------------------------------
# It is not typed out here. `executors.register_all()` is the single source of
# truth, exactly as it is for /help, and for the same reason: a hand-maintained
# copy goes stale silently. Phase 09 shipped a /help legend that explained a
# marker no command carried any more, which is the small version of this bug.
#
# So adding an executor updates the phone's autocomplete, with nobody editing
# a list.
#
# THE TOKEN NEVER APPEARS IN argv, AND NEVER IN OUTPUT
# ----------------------------------------------------
# A bot token is a bearer credential: whoever holds it IS the bot. Two specific
# mistakes are avoided here.
#
#   1. It is NOT passed on curl's command line. Anything in argv is visible in
#      `ps` to every user on the machine for the life of the process. The URL
#      reaches curl through `--config -`, i.e. over a pipe.
#   2. Every byte of output is filtered through a redactor before printing.
#      Telegram echoes the request URL in some error bodies, and an error path
#      is exactly where nobody is looking carefully.
#
# The token is read from /etc/homelab-telegram-bot/token, which is root:root
# 0600 -- so this needs root, and the token never leaves the machine except to
# api.telegram.org, which is where it belongs.
#
# REQUEST BODIES ARE BUILT AS FILES, NOT INTERPOLATED INTO PYTHON
# ---------------------------------------------------------------
# The first draft of this script did the latter -- python3 -c "... '''$CMDS'''"
# -- which works right up until a command description contains a quote, at
# which point it is a syntax error at best. Bodies are written to a scratch
# directory and read back by path. Nothing generated is secret; the token is
# never written into any of them.
#
# OUTWARD-FACING BY NATURE
# ------------------------
# This changes what the bot presents to Telegram, not just local state, so
# `show` is the default and `apply` must be asked for explicitly. `show` makes
# no writing call at all.
#
# Not lockout-class (ADR-020): it touches no unit, no account, no network
# configuration and no authentication. The worst case is a wrong description.

set -euo pipefail

TOKEN_FILE="/etc/homelab-telegram-bot/token"
ALLOWLIST="/etc/homelab-telegram-bot/allowlist"
APP_DIR="/opt/homelab-telegram-bot"
PROFILE="${PROFILE:-/tmp/homelab-bot-profile/bot-profile.json}"
API="https://api.telegram.org"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok    $*"; }
info() { echo "      $*"; }

usage() {
    cat <<'USAGE'
Usage: configure-telegram-bot-profile.sh <show|apply|verify>

  show    print what WOULD be sent, and what Telegram currently has.
          Makes no writing API call.
  apply   send it, then read it back and compare.
  verify  read back only, and compare against the profile file.

Needs root: the bot token is root-only by design.
Expects the profile JSON at $PROFILE
(default /tmp/homelab-bot-profile/bot-profile.json).
USAGE
}

case "${1:-}" in
    show|apply|verify) MODE="$1" ;;
    *) usage; exit 1 ;;
esac

[[ $EUID -eq 0 ]] || fail "run as root: sudo bash $0 $MODE"
[[ -f "$TOKEN_FILE" ]] || fail "$TOKEN_FILE not found"
[[ -f "$PROFILE" ]] || fail "$PROFILE not found -- scp config/telegram/bot-profile.json first"
[[ -d "$APP_DIR" ]] || fail "$APP_DIR not found -- install the bot first"
command -v curl >/dev/null || fail "curl is required"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
[[ -n "$TOKEN" ]] || fail "$TOKEN_FILE is empty"

# '|' as the delimiter: a bot token contains ':' but never '|'.
redact() { sed "s|${TOKEN}|[REDACTED-TOKEN]|g"; }

# Bounded, IPv4-only. Both flags were added after this script hung.
#
# --connect-timeout / --max-time: the first version had NO timeout, so a stalled
#   request blocked forever and the only way out was Ctrl-C. A script that can
#   hang indefinitely is not a script you can put in a verification path, and
#   "it worked when I ran it" is not availability.
#
# --ipv4: measured, not assumed. This host has NO working global IPv6 route --
#   `curl -6 https://api.telegram.org/` fails in 9ms with no route, while the
#   only IPv6 address on the node is the Tailscale one. api.telegram.org
#   publishes AAAA records, so leaving address selection to chance means
#   sometimes racing toward an address that cannot work. IPv4 is the route that
#   exists here; when that changes, remove this flag deliberately.
#
# Note what is NOT here: --retry. A retry would paper over exactly the
# intermittent stall that made this comment necessary.
# 20s to connect, not 10. The description write failed on the first real run
# with "Connection timed out after 10001 milliseconds", and identical calls
# from this node had already been measured at up to 8.9s -- so a 10s connect
# budget was inside the observed spread. The timeout was right; the number was
# guessed. Measure, then choose.
CURL_OPTS=(--silent --show-error --ipv4 --connect-timeout 20 --max-time 60)

# $1 = method, $2 = optional path to a JSON body file.
api() {
    local method="$1" body="${2:-}"
    if [[ -n "$body" ]]; then
        printf 'url = "%s/bot%s/%s"\n' "$API" "$TOKEN" "$method" \
            | curl "${CURL_OPTS[@]}" --config - \
                   --header "Content-Type: application/json" \
                   --data-binary "@${body}" 2>&1 | redact
    else
        printf 'url = "%s/bot%s/%s"\n' "$API" "$TOKEN" "$method" \
            | curl "${CURL_OPTS[@]}" --config - 2>&1 | redact
    fi
}

# Telegram signals rejection as HTTP 200 with ok:false. curl exiting 0 means
# the conversation happened, nothing more -- treating that as success is the
# failure family this project keeps hitting, so the field is checked.
# One field out of a successful reply. Exits non-zero, printing NOTHING, when
# the reply is unusable -- so the caller can tell "could not check" apart from
# "does not match".
readonly PY_GET='
import json, os, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(3)
if doc.get("ok") is not True:
    sys.exit(4)
try:
    print(doc["result"][os.environ["FIELD"]], end="")
except (KeyError, TypeError):
    sys.exit(5)
'

# Compare the command list as a set. Prints match | differ | unknown.
readonly PY_CMP='
import json, os, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    print("unknown"); sys.exit(0)
if doc.get("ok") is not True or not isinstance(doc.get("result"), list):
    print("unknown"); sys.exit(0)
want = sorted((c["command"], c["description"])
              for c in json.load(open(os.environ["WANT"], encoding="utf-8")))
got = sorted((c["command"], c["description"]) for c in doc["result"])
print("match" if want == got else "differ")
'

readonly PY_OK='
import json, sys
raw = sys.stdin.read()
try:
    print("yes" if json.loads(raw).get("ok") is True else "no")
except Exception:
    print("unparseable")
'

# --- The command list, from the registry ---------------------------------
#
# Telegram requires lowercase letters, digits and underscores, 1-32 chars, no
# leading slash, and a 1-256 char description. Aliases are skipped: two menu
# entries for one executor would only confuse.
build_commands() {
    local include_privileged="$1" dest="$2"
    ( cd "$APP_DIR" \
        && INCLUDE_PRIV="$include_privileged" DEST="$dest" APP_DIR="$APP_DIR" \
           python3 - <<'PYCMD'
import json, os, re, sys
sys.path.insert(0, os.environ["APP_DIR"])
import executors
from router import Capability, Router

include_priv = os.environ["INCLUDE_PRIV"] == "yes"

r = Router(privileged_users=set(), log=lambda m: None)
executors.register_all(r, allowed_units=set(), log=lambda m: None)

out = []
for ex in r.unique_executors():
    if ex.capability is Capability.PRIVILEGED and not include_priv:
        continue
    if ex.capability is Capability.UNAVAILABLE:
        continue
    name = ex.name.lstrip("/").lower()
    if not re.fullmatch(r"[a-z0-9_]{1,32}", name):
        continue
    out.append({"command": name, "description": ex.summary[:256]})

with open(os.environ["DEST"], "w", encoding="utf-8") as fh:
    json.dump(out, fh)
PYCMD
    )
}

# --- Allowlisted chat ids ------------------------------------------------
#
# For a private chat the chat id IS the user id, so the allowlist doubles as
# the list of chats that get the full command set.
#
# The ids are never printed. They identify the owner's Telegram account, the
# allowlist is deliberately not in the repository, and anything whose output is
# meant to be pasted must be safe to paste.
allowed_ids() {
    [[ -f "$ALLOWLIST" ]] || return 0
    sed 's/#.*//' "$ALLOWLIST" | tr -d '[:blank:]' | grep -E '^-?[0-9]+$' || true
}

PUBLIC_FILE="$WORK/public-commands.json"
OWNER_FILE="$WORK/owner-commands.json"
build_commands no  "$PUBLIC_FILE"
build_commands yes "$OWNER_FILE"

read_field() {
    PROFILE="$PROFILE" KEY="$1" python3 - <<'PYF'
import json, os
prof = json.load(open(os.environ["PROFILE"], encoding="utf-8"))
print(prof[os.environ["KEY"]], end="")
PYF
}

NAME="$(read_field name)"
SHORT="$(read_field short_description)"
LONG="$(read_field description)"

count_in() { COUNTF="$1" python3 -c 'import json,os;print(len(json.load(open(os.environ["COUNTF"]))))'; }

# One profile field as a request body file.
body_field() {
    PROFILE="$PROFILE" KEY="$1" DEST="$2" python3 - <<'PYB'
import json, os
prof = json.load(open(os.environ["PROFILE"], encoding="utf-8"))
key = os.environ["KEY"]
with open(os.environ["DEST"], "w", encoding="utf-8") as fh:
    json.dump({key: prof[key]}, fh)
PYB
}

# A setMyCommands body file. $3 = scope type, $4 = chat id (optional).
body_commands() {
    CMDS="$1" DEST="$2" SCOPE="$3" CHAT="${4:-}" python3 - <<'PYS'
import json, os
scope = {"type": os.environ["SCOPE"]}
if os.environ["CHAT"]:
    scope["chat_id"] = int(os.environ["CHAT"])
body = {"commands": json.load(open(os.environ["CMDS"], encoding="utf-8")),
        "scope": scope}
with open(os.environ["DEST"], "w", encoding="utf-8") as fh:
    json.dump(body, fh)
PYS
}

pretty() { python3 -m json.tool 2>/dev/null || cat; }

# --------------------------------------------------------------------------

do_show() {
    echo "=== Telegram bot profile ==="
    echo
    info "profile source: $PROFILE"
    info "commands derived from: ${APP_DIR}/executors.py (the registry)"
    echo
    echo "--- would set name:"
    info "$NAME"
    echo "--- would set short_description:"
    info "$SHORT"
    echo "--- would set description:"
    printf '%s\n' "$LONG" | sed 's/^/      /'
    echo
    echo "--- commands, DEFAULT scope ($(count_in "$PUBLIC_FILE") — privileged withheld):"
    pretty < "$PUBLIC_FILE" | sed 's/^/      /'
    echo "--- commands, allowlisted chats ($(count_in "$OWNER_FILE") — full set):"
    pretty < "$OWNER_FILE" | sed 's/^/      /'
    info "$(allowed_ids | wc -l | tr -d ' ') allowlisted chat id(s) would get the full set (ids not printed)"
    echo
    echo "--- what Telegram has NOW ---"
    local m out
    for m in getMe getMyName getMyShortDescription getMyDescription getMyCommands; do
        echo "${m}:"
        out="$(api "$m")"
        if [[ -z "${out//[[:space:]]/}" ]]; then
            info "(no usable reply within ${CURL_OPTS[-1]}s — network, not configuration)"
        else
            printf '%s\n' "$out" | pretty | sed 's/^/      /'
        fi
    done
    echo
    echo "Nothing was changed. Re-run with 'apply' to send it."
}

send() {
    local method="$1" body="$2" label="$3" out verdict
    out="$(api "$method" "$body")"
    verdict="$(printf '%s' "$out" | python3 -c "$PY_OK")"
    if [[ "$verdict" == "yes" ]]; then
        ok "$label"
        return 0
    fi
    echo "FAIL  $label"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1
}

do_apply() {
    echo "=== Applying Telegram bot profile ==="
    echo
    local rc=0

    # setMyName is rate-limited by Telegram far more aggressively than the
    # others and refuses if called too often. Reported, never hidden.
    body_field name "$WORK/name.json"
    send setMyName "$WORK/name.json" "name set" || rc=1

    body_field short_description "$WORK/short.json"
    send setMyShortDescription "$WORK/short.json" "short description set" || rc=1

    body_field description "$WORK/long.json"
    send setMyDescription "$WORK/long.json" "description set" || rc=1

    # Default scope gets everything except the privileged command. The
    # allowlist already refuses non-owners, so this is NOT the access control
    # -- it is simply not advertising a privileged action to strangers.
    body_commands "$PUBLIC_FILE" "$WORK/cmd-default.json" default
    send setMyCommands "$WORK/cmd-default.json" \
        "default-scope commands set ($(count_in "$PUBLIC_FILE"))" || rc=1

    local n=0 id
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        body_commands "$OWNER_FILE" "$WORK/cmd-chat.json" chat "$id"
        send setMyCommands "$WORK/cmd-chat.json" \
            "full command set applied to an allowlisted chat" || rc=1
        n=$((n + 1))
    done < <(allowed_ids)
    info "$n allowlisted chat(s) configured"

    echo
    echo "--- reading it back ---"
    do_verify || rc=1
    return $rc
}

# Print one field from a successful API reply.
#
# Returns 0 and the value, or NON-ZERO AND NOTHING. It does not invent a
# placeholder, and that is the whole point of this comment.
#
# The first version did:
#
#     FIELD="$field" api "$method" | python3 -c '... os.environ["FIELD"] ...'
#
# In a pipeline, VAR=val cmd1 | cmd2 sets the variable for cmd1 ONLY -- so
# python never received FIELD, raised KeyError, and a bare `except Exception`
# turned that into the string "<unreadable>". The caller then compared that
# string against the expected value and reported FAIL.
#
# So a bug in the check was reported as a defect in the thing being checked.
# The values had almost certainly been set correctly. This is the NINTH
# instance of this project's oldest failure family -- after `sshd -T`, `who`,
# two Phase 04 scanner bugs, the Phase 07 verifier, the Phase 08 escalation
# test, the Phase 08 `setpriv` misread, and the Phase 09 installer's group
# check -- and the mechanism was, once again, an exception handler that
# produced something plausible instead of admitting it had nothing.
#
# Rule made concrete here: a check reports UNKNOWN when it cannot determine an
# answer, and UNKNOWN is not FAIL. They are different claims and only one of
# them is evidence.
get_result_field() {
    local method="$1" field="$2" out
    out="$(api "$method")" || return 1
    [[ -n "${out//[[:space:]]/}" ]] || return 1
    # -c, not `python3 - <<HEREDOC`. A heredoc AND a herestring on the same
    # command are two stdin redirections and the last one wins, so python would
    # have tried to read its own program out of the JSON.
    FIELD="$field" python3 -c "$PY_GET" <<<"$out"
}

# Three outcomes, three messages. Returns 0 matched, 1 differs, 2 unknown.
compare_field() {
    local method="$1" field="$2" want="$3" label="$4" got
    if ! got="$(get_result_field "$method" "$field")"; then
        echo "UNKNOWN  $label could not be read — no usable reply. This is NOT a mismatch."
        return 2
    fi
    if [[ "$got" == "$want" ]]; then
        ok "$label matches"
        return 0
    fi
    echo "FAIL  $label differs"
    info "want: $want"
    info "got:  $got"
    return 1
}

do_verify() {
    local failed=0 unknown=0

    compare_field getMyName name "$NAME" "name" \
        || { [[ $? -eq 2 ]] && unknown=$((unknown + 1)) || failed=$((failed + 1)); }
    compare_field getMyShortDescription short_description "$SHORT" "short description" \
        || { [[ $? -eq 2 ]] && unknown=$((unknown + 1)) || failed=$((failed + 1)); }
    compare_field getMyDescription description "$LONG" "description" \
        || { [[ $? -eq 2 ]] && unknown=$((unknown + 1)) || failed=$((failed + 1)); }

    # The command list, compared as a SET -- Telegram is not obliged to preserve
    # ordering, and a check that fails on ordering is a check that gets ignored.
    #
    # Distinguishes the same three outcomes: exit 3 means the reply could not be
    # read, which is unknown, not a mismatch.
    local raw
    if ! raw="$(api getMyCommands)" || [[ -z "${raw//[[:space:]]/}" ]]; then
        echo "UNKNOWN  command list could not be read — no usable reply."
        unknown=$((unknown + 1))
    else
        local verdict
        verdict="$(WANT="$PUBLIC_FILE" python3 -c "$PY_CMP" <<<"$raw")"
        case "$verdict" in
            match)
                ok "default-scope command list matches what was sent"
                printf '%s' "$raw" | python3 -c '
import json, sys
for c in json.load(sys.stdin)["result"]:
    print("      /" + c["command"], "--", c["description"])
'
                ;;
            differ)
                echo "FAIL  default-scope command list differs from the profile"
                printf '%s' "$raw" | pretty | sed 's/^/      /'
                failed=$((failed + 1))
                ;;
            *)
                echo "UNKNOWN  command list reply could not be parsed."
                unknown=$((unknown + 1))
                ;;
        esac
    fi

    echo
    if [[ $failed -eq 0 && $unknown -eq 0 ]]; then
        ok "everything read back as sent"
        return 0
    fi
    [[ $failed  -gt 0 ]] && echo "${failed} field(s) genuinely differ."
    [[ $unknown -gt 0 ]] && echo "${unknown} field(s) COULD NOT BE CHECKED — re-run 'verify'. \
Unknown is not failure; this link measures 200ms to 9s."
    return 1
}

case "$MODE" in
    show)   do_show ;;
    apply)  do_apply ;;
    verify) do_verify ;;
esac
