#!/usr/bin/env bash
#
# install-model-helper.sh — Phase 09, ADR-025. Phase 15.0: registry, fixture.
#
# Installs the model helper: the service that makes model calls on the bot's
# behalf because the bot cannot read either AI credential and must not gain the
# ability.
#
# WHAT THIS SCRIPT REFUSES TO DO
# ------------------------------
#   - add homelab-bot to any group
#   - copy, move or read either OAuth credential
#   - make the helper's code writable by the account that runs it
#
# The first two would defeat the entire design. The third is why /opt is
# root-owned: the helper runs as `aleix`, and code that its own runtime user can
# rewrite is not a boundary.
#
# WHAT IT PROVES BEFORE REPORTING SUCCESS
# ---------------------------------------
#   - the socket exists with the exact owner, group and mode intended
#   - a process running AS homelab-bot, INSIDE the bot's sandbox, can reach it
#   - homelab-bot still cannot read either credential file
#   - homelab-bot's group membership is unchanged
#   - (15.0) the eligibility refusal, the unknown-key refusal and the
#     hints-do-not-select check pass against a fixture, as the helper's own
#     account, spending no allowance (fixture-tests.py)
#
# The sandbox part matters. ProtectSystem=strict mounts / read-only, /run
# included, and whether connect(2) to a socket on a read-only mount is permitted
# is a kernel question this project should answer by trying it rather than by
# reasoning about it. A check run as root from a login shell would pass and
# prove nothing.
#
# Not lockout-class (ADR-020): no [Install] section on the service, nothing
# WantedBy=multi-user.target that can fail closed at boot, no change to network,
# SSH, authentication or the admin account. The socket unit IS enabled at boot,
# but a socket that fails to bind takes nothing else down with it.

set -euo pipefail

OWNER="aleix"
BOT_USER="homelab-bot"
CODE_DIR="/opt/homelab-model-helper"
CONF_DIR="/etc/homelab-model-helper"
STATE_DIR="/var/lib/homelab-model-helper"
SOCKET_PATH="/run/homelab-model-helper.sock"
UNIT_DIR="/etc/systemd/system"
SRC="${SRC:-/tmp/homelab-phase09}"

CLAUDE_CRED="/home/${OWNER}/.claude/.credentials.json"
CODEX_CRED="/home/${OWNER}/.codex/auth.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok    $*"; }
info() { echo "      $*"; }

[[ $EUID -eq 0 ]] || fail "run as root: sudo bash $0 $*"

usage() {
    cat <<'USAGE'
Usage: install-model-helper.sh <install|verify>

  install   deploy code, config and units, then prove the boundary
  verify    re-run every check without changing anything

Expects the helper source files in $SRC (default /tmp/homelab-phase09):
  helper.py providers.py limits.py socket-probe.py fixture-tests.py
  config.example.json homelab-model-helper.socket homelab-model-helper@.service

Phase 15.0: an existing /etc/homelab-model-helper/config.json in the Phase 09
shape is NOT migrated by this script -- see guide/15-model-routing/s2-runbook.md.
USAGE
}

# --------------------------------------------------------------------------
# Checks. Every one of these must be able to say UNKNOWN rather than invent a
# verdict -- the failure family this project has hit seven times.
# --------------------------------------------------------------------------

check_socket_permissions() {
    if [[ ! -S "$SOCKET_PATH" ]]; then
        echo "FAIL  socket $SOCKET_PATH does not exist"
        return 1
    fi
    local spec
    spec=$(stat -c '%U:%G:%a' "$SOCKET_PATH")
    if [[ "$spec" == "${OWNER}:${BOT_USER}:660" ]]; then
        ok "socket is ${spec} — only ${OWNER} and ${BOT_USER} can connect"
        return 0
    fi
    echo "FAIL  socket is ${spec}, expected ${OWNER}:${BOT_USER}:660"
    return 1
}

check_bot_can_reach_socket() {
    # Run the probe as homelab-bot, inside the bot's own filesystem sandbox.
    #
    # These -p flags are copied from homelab-telegram-bot.service on purpose. If
    # they drift apart this check stops testing the real thing, which is why the
    # unit is named here in a comment: keep them in step.
    local out rc
    set +e
    out=$(systemd-run --pipe --quiet --wait --collect \
            --unit="homelab-model-probe-$$" \
            --uid="$BOT_USER" --gid="$BOT_USER" \
            -p NoNewPrivileges=yes \
            -p ProtectSystem=strict \
            -p ProtectHome=yes \
            -p PrivateTmp=yes \
            -p ProtectProc=invisible \
            -p RestrictAddressFamilies="AF_INET AF_INET6 AF_UNIX" \
            /usr/bin/python3 "${CODE_DIR}/socket-probe.py" "$SOCKET_PATH" 2>&1)
    rc=$?
    set -e

    if [[ $rc -eq 0 ]] && grep -q "PROBE OK" <<<"$out"; then
        ok "${BOT_USER} reached the socket from inside the bot's sandbox"
        info "${out}"
        return 0
    fi

    # Distinguish "the probe ran and was refused" from "the probe never ran".
    # Phase 08 read `setpriv: Operation not permitted` as a security result when
    # the test had simply not executed. Never again without saying so.
    if grep -q "PROBE FAIL" <<<"$out"; then
        echo "FAIL  ${BOT_USER} could NOT reach the socket — the probe ran and was refused"
        info "${out}"
        info "If errno=30 (EROFS) the bot's ProtectSystem=strict blocked the connect;"
        info "the fix is ReadWritePaths=${SOCKET_PATH} in the bot unit."
        info "If errno=13 (EACCES) the socket's group or mode is wrong."
    else
        echo "UNKNOWN  the probe did not run, so nothing was tested"
        info "${out}"
    fi
    return 1
}

check_credential_boundary() {
    # The Phase 07 property that must survive this phase. Tested by ATTEMPTING
    # the read as the service account, not by reading a mode bit and reasoning.
    local rc=0 f
    for f in "$CLAUDE_CRED" "$CODEX_CRED"; do
        if [[ ! -e "$f" ]]; then
            echo "UNKNOWN  $f does not exist; nothing to test"
            rc=1
            continue
        fi
        if setpriv --reuid="$BOT_USER" --regid="$BOT_USER" --clear-groups \
               /usr/bin/cat "$f" >/dev/null 2>&1; then
            echo "FAIL  ${BOT_USER} CAN read $f — the Phase 09 design is void"
            rc=1
        else
            ok "${BOT_USER} still cannot read $f"
        fi
    done
    return $rc
}

check_bot_groups_unchanged() {
    local groups
    groups=$(id -nG "$BOT_USER" | tr ' ' '\n' | sort | paste -sd' ' -)
    if [[ "$groups" == "$BOT_USER" ]]; then
        ok "${BOT_USER} is in no group but its own: ${groups}"
        return 0
    fi
    echo "FAIL  ${BOT_USER} groups changed: ${groups}"
    return 1
}

check_code_not_writable_by_runtime_user() {
    local bad=0 f n=0
    if [[ ! -d "$CODE_DIR" ]]; then
        echo "UNKNOWN  ${CODE_DIR} does not exist; no files were examined"
        return 1
    fi
    while IFS= read -r f; do
        n=$((n + 1))
        if setpriv --reuid="$OWNER" --regid="$OWNER" --clear-groups \
               /usr/bin/test -w "$f" 2>/dev/null; then
            echo "FAIL  ${OWNER} can modify $f, which ${OWNER} also executes"
            bad=1
        fi
    done < <(find "$CODE_DIR" -type f 2>/dev/null)
    if [[ $n -eq 0 ]]; then
        echo "UNKNOWN  no files found under ${CODE_DIR}; nothing was examined"
        return 1
    fi
    [[ $bad -eq 0 ]] && ok "${n} helper files, none writable by ${OWNER}, who runs them"
    return $bad
}

check_fixture_tests() {
    # Phase 15.0. The eligibility check permits every real call today, so the
    # refusal is proved against a fixture provider set unattended:false, next
    # to a positive control. Run as the helper's own account, from the
    # installed code, with a stub in place of both CLIs: no allowance spent.
    # The temp dir is created here (root) and handed to $OWNER because
    # setpriv's target cannot rely on a writable $TMPDIR under PrivateTmp.
    local out rc tmp
    if [[ ! -f "${CODE_DIR}/fixture-tests.py" ]]; then
        echo "UNKNOWN  ${CODE_DIR}/fixture-tests.py is not installed; nothing was tested"
        return 1
    fi
    tmp=$(mktemp -d /tmp/homelab-p150-fixture.XXXXXX)
    chown "$OWNER:$OWNER" "$tmp"
    set +e
    out=$(setpriv --reuid="$OWNER" --regid="$OWNER" --clear-groups \
            env TMPDIR="$tmp" /usr/bin/python3 "${CODE_DIR}/fixture-tests.py" 2>&1)
    rc=$?
    set -e
    rm -rf "$tmp"
    if [[ $rc -eq 0 ]] && grep -q "^All .* checks passed" <<<"$out"; then
        ok "fixture tests passed as ${OWNER} (refusal, control, no cap, hints, unknown key)"
        grep -E '^ok +test (1|2|3|11|12):' <<<"$out" | sed 's/ --.*//; s/^/      /'
        return 0
    fi
    if grep -qE '^(ok|FAIL) ' <<<"$out"; then
        echo "FAIL  fixture tests did not all pass"
    else
        echo "UNKNOWN  the fixture tests did not run"
    fi
    sed 's/^/      /' <<<"$out"
    return 1
}

check_config_is_registry() {
    # The helper refuses the Phase 09 shape. Say so here, in words, rather
    # than letting the first /ask discover it.
    local shape
    if [[ ! -f "${CONF_DIR}/config.json" ]]; then
        echo "UNKNOWN  ${CONF_DIR}/config.json does not exist"
        return 1
    fi
    shape=$(python3 -c "import json;c=json.load(open('${CONF_DIR}/config.json'));print(type(c.get('providers')).__name__)" 2>&1)
    if [[ "$shape" == "dict" ]]; then
        ok "config.json is in the Phase 15.0 registry shape"
        return 0
    fi
    echo "FAIL  config.json 'providers' is ${shape}, not an object — Phase 09 shape; every /ask will fail until it is migrated (s2-runbook)"
    return 1
}

check_no_new_listener() {
    # A UNIX socket is not a listening TCP socket, and this proves it rather
    # than asserting it. `ss -tln` is what the Phase 09 brief committed to being
    # byte-identical.
    local n
    n=$(ss -tln | tail -n +2 | wc -l)
    ok "TCP listeners: ${n} (a UNIX socket adds none — compare with the brief)"
    ss -tln | sed 's/^/      /'
}

run_verify() {
    local rc=0
    echo "=== Model helper — verification (Phase 09 + 15.0) ==="
    echo
    check_socket_permissions            || rc=1
    check_bot_can_reach_socket          || rc=1
    check_credential_boundary           || rc=1
    check_bot_groups_unchanged          || rc=1
    check_code_not_writable_by_runtime_user || rc=1
    check_config_is_registry            || rc=1
    check_fixture_tests                 || rc=1
    check_no_new_listener
    echo
    if [[ $rc -eq 0 ]]; then
        echo "All checks passed."
    else
        echo "At least one check did not pass. Read the lines above; a FAIL and"
        echo "an UNKNOWN are different claims and only one of them is a result."
    fi
    return $rc
}

run_install() {
    local f
    for f in helper.py providers.py limits.py socket-probe.py fixture-tests.py \
             config.example.json homelab-model-helper.socket \
             'homelab-model-helper@.service'; do
        [[ -f "${SRC}/${f}" ]] || fail "missing ${SRC}/${f} — scp the helper files first"
    done

    id "$OWNER"    >/dev/null 2>&1 || fail "user ${OWNER} does not exist"
    id "$BOT_USER" >/dev/null 2>&1 || fail "user ${BOT_USER} does not exist — install the bot first"

    # The CLIs must be runnable BY THE OWNER. Checking them as root proves
    # nothing: root can execute things the service user cannot, and the whole
    # point is what happens as `aleix`.
    local claude_bin codex_bin
    # Phase 15.0: the registry nests provider entries under "providers".
    claude_bin=$(python3 -c "import json,sys;print(json.load(open('${SRC}/config.example.json'))['providers']['claude']['bin'])")
    codex_bin=$(python3 -c "import json,sys;print(json.load(open('${SRC}/config.example.json'))['providers']['codex']['bin'])")
    for f in "$claude_bin" "$codex_bin"; do
        setpriv --reuid="$OWNER" --regid="$OWNER" --clear-groups \
            /usr/bin/test -x "$f" || fail "${OWNER} cannot execute ${f}"
        ok "${OWNER} can execute ${f}"
    done

    install -d -o root -g root -m 0755 "$CODE_DIR"
    # config.example.json goes beside the code too: fixture-tests.py derives
    # its fixture from it (OBSERVED 2026-09-13: without it, verify said
    # UNKNOWN, correctly). It is the format reference, not the live config.
    for f in helper.py providers.py limits.py socket-probe.py fixture-tests.py \
             config.example.json; do
        install -o root -g root -m 0644 "${SRC}/${f}" "${CODE_DIR}/${f}"
    done
    ok "code installed to ${CODE_DIR}, root-owned and not writable by ${OWNER}"

    install -d -o root -g root -m 0755 "$CONF_DIR"
    if [[ -f "${CONF_DIR}/config.json" ]]; then
        info "${CONF_DIR}/config.json exists — left alone"
    else
        install -o root -g root -m 0644 "${SRC}/config.example.json" "${CONF_DIR}/config.json"
        ok "config installed from the example — review it before relying on the caps"
    fi

    # StateDirectory= in the unit creates this, but the unit is templated and
    # per-connection; creating it here means the first request does not race.
    install -d -o "$OWNER" -g "$OWNER" -m 0700 "$STATE_DIR"
    ok "state directory ${STATE_DIR} owned by ${OWNER}"

    install -o root -g root -m 0644 "${SRC}/homelab-model-helper.socket" \
        "${UNIT_DIR}/homelab-model-helper.socket"
    install -o root -g root -m 0644 "${SRC}/homelab-model-helper@.service" \
        "${UNIT_DIR}/homelab-model-helper@.service"

    systemctl daemon-reload

    # Verify systemd accepted the units before enabling anything. A unit with a
    # rejected directive loads with a warning and runs WITHOUT it -- Phase 03's
    # lesson about configuration versus the running daemon.
    local vout
    vout=$(systemd-analyze verify "${UNIT_DIR}/homelab-model-helper.socket" \
                                  "homelab-model-helper@probe.service" 2>&1 || true)
    if [[ -n "$vout" ]]; then
        echo "      systemd-analyze verify said:"
        sed 's/^/      /' <<<"$vout"
    else
        ok "systemd-analyze verify accepted both units with no complaint"
    fi

    systemctl enable --now homelab-model-helper.socket
    ok "socket unit enabled and started"
    echo
    run_verify
}

case "${1:-}" in
    install) run_install ;;
    verify)  run_verify ;;
    *)       usage; exit 1 ;;
esac
