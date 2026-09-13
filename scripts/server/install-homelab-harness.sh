#!/usr/bin/env bash
#
# install-homelab-harness.sh -- Phase 23.0, the endpoint.
#
# Installs the harness: the always-running, loopback-only endpoint that accepts
# a request from a local client, classifies it, forwards a question to the
# model helper and writes one content-free audit line per request.
#
# WHAT THIS SCRIPT REFUSES TO DO
# ------------------------------
#   - create the account as anything but a system account with no shell and no
#     home, in no group but its own and homelab-model (ADR-048)
#   - add the account to aleix, docker, sudo, adm or lxd (baseline §3)
#   - create the homelab-model group or change the helper's socket unit -- that
#     is `install-model-helper.sh group`, which runs FIRST (brief §7.2 order:
#     the regression check on the bot comes before the new consumer exists)
#   - touch sshd, the firewall, Tailscale or the data volume
#   - make the harness's code or config writable by the account that runs it
#
# WHAT IT PROVES BEFORE REPORTING SUCCESS (verify)
# ------------------------------------------------
#   - the account has no shell, no home, and exactly the intended groups
#   - the unit is active, and the listener is 127.0.0.1:8766 owned by the
#     harness (the eighth socket) -- and there is no other new listener
#   - GET /health answers; GET /health/helper reaches the helper's socket AS
#     the harness account, through its group membership, spending nothing
#   - a third account outside the group cannot connect to the helper's socket
#     (brief test 18: the group is the boundary)
#   - the fixture passes as the harness account against the installed
#     helper.py, spending nothing
#   - the code under /opt is not writable by the runtime account
#   - systemd-analyze security reports the score (the threshold is the
#     baseline's: <= 2.0 or a # WHY per finding)
#
# Boot-class (safe-changes-headless.md): the unit is WantedBy=multi-user.target.
# A unit that fails at boot fails alone -- nothing else depends on it, and it
# does not touch network, SSH, authentication or the admin account -- so this
# is not lockout-class, but the second idle session stays open regardless.
#
# Runbook rule (baseline §7): every step prints what it does before it waits.
# This script never prompts; sudo is asked for once, by the caller.

set -euo pipefail

SERVICE_USER="homelab-harness"
MODEL_GROUP="homelab-model"
BOT_USER="homelab-bot"
CODE_DIR="/opt/homelab-harness"
CONF_DIR="/etc/homelab-harness"
STATE_DIR="/var/lib/homelab-harness"
UNIT="homelab-harness.service"
UNIT_DIR="/etc/systemd/system"
HELPER_CODE_DIR="/opt/homelab-model-helper"
HELPER_SOCKET="/run/homelab-model-helper.sock"
PORT="8766"
SRC="${SRC:-/tmp/homelab-phase230}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok    $*"; }
info() { echo "      $*"; }
step() { echo; echo "--> $*"; }

[[ $EUID -eq 0 ]] || fail "run as root: sudo bash $0 $*"

usage() {
    cat <<'USAGE'
Usage: install-homelab-harness.sh <install|verify|uninstall>

  install    create the account, deploy code, config and units, start, then verify
  verify     re-run every check without changing anything
  uninstall  stop, disable, remove the unit, drop-in, code, config and account;
             LEAVE /var/lib/homelab-harness (the audit file) in place

Expects the harness files in $SRC (default /tmp/homelab-phase230):
  harness.py classify.py fixture-tests.py config.example.json
  homelab-harness.service onfailure.conf

Prerequisite: `install-model-helper.sh group` has run (ADR-048) -- the group
homelab-model exists and the helper's socket is aleix:homelab-model:0660.
USAGE
}

# --------------------------------------------------------------------------
# Checks. Each says ok, FAIL or UNKNOWN -- an UNKNOWN is "nothing was tested",
# never a pass and never a finding.
# --------------------------------------------------------------------------

check_account() {
    if ! id "$SERVICE_USER" >/dev/null 2>&1; then
        echo "FAIL  account ${SERVICE_USER} does not exist"
        return 1
    fi
    local shell home groups rc=0
    shell=$(getent passwd "$SERVICE_USER" | cut -d: -f7)
    home=$(getent passwd "$SERVICE_USER" | cut -d: -f6)
    groups=$(id -nG "$SERVICE_USER" | tr ' ' '\n' | sort | paste -sd' ' -)
    case "$shell" in
        /usr/sbin/nologin|/sbin/nologin|/bin/false) ok "${SERVICE_USER} shell is ${shell}" ;;
        *) echo "FAIL  ${SERVICE_USER} shell is ${shell}"; rc=1 ;;
    esac
    if [[ -d "$home" && "$home" != /nonexistent && "$home" != / ]]; then
        echo "FAIL  ${SERVICE_USER} has a home directory: ${home}"; rc=1
    else
        ok "${SERVICE_USER} has no home directory (${home})"
    fi
    # Compared as a sorted set; `sort` puts homelab-harness before homelab-model.
    if [[ "$groups" == "$(printf '%s\n' "$SERVICE_USER" "$MODEL_GROUP" | sort | paste -sd' ' -)" ]]; then
        ok "${SERVICE_USER} groups are exactly: ${groups}"
    else
        echo "FAIL  ${SERVICE_USER} groups are: ${groups} (expected exactly ${SERVICE_USER} and ${MODEL_GROUP})"; rc=1
    fi
    for g in aleix docker sudo adm lxd; do
        if id -nG "$SERVICE_USER" | tr ' ' '\n' | grep -qx "$g"; then
            echo "FAIL  ${SERVICE_USER} is in ${g}"; rc=1
        fi
    done
    return $rc
}

check_group_membership() {
    local members
    if ! getent group "$MODEL_GROUP" >/dev/null; then
        echo "FAIL  group ${MODEL_GROUP} does not exist -- run install-model-helper.sh group first (ADR-048)"
        return 1
    fi
    members=$(getent group "$MODEL_GROUP" | cut -d: -f4 | tr ',' '\n' | sort | paste -sd',' -)
    if [[ "$members" == "${BOT_USER},${SERVICE_USER}" ]]; then
        ok "getent group ${MODEL_GROUP} = ${members}"
        return 0
    fi
    echo "FAIL  group ${MODEL_GROUP} members are '${members}', expected '${BOT_USER},${SERVICE_USER}'"
    return 1
}

check_unit_active() {
    if systemctl is-active --quiet "$UNIT"; then
        ok "${UNIT} is active"
        return 0
    fi
    echo "FAIL  ${UNIT} is $(systemctl is-active "$UNIT" || true)"
    journalctl -u "$UNIT" -n 5 --no-pager | sed 's/^/      /'
    return 1
}

check_listener() {
    # The eighth socket: 127.0.0.1:8766, owned by the harness, and nothing
    # else new. `ss -tlnp` is what the brief's row 8 reads.
    local line
    line=$(ss -tlnp | grep -E "127\.0\.0\.1:${PORT}\b" || true)
    if [[ -z "$line" ]]; then
        echo "FAIL  nothing listens on 127.0.0.1:${PORT}"
        return 1
    fi
    if grep -q '"python3"' <<<"$line" && ss -tlnpe | grep -E "127\.0\.0\.1:${PORT}\b" \
            | grep -q "uid:$(id -u "$SERVICE_USER")"; then
        ok "127.0.0.1:${PORT} is listening as uid $(id -u "$SERVICE_USER") (${SERVICE_USER})"
    else
        echo "FAIL  127.0.0.1:${PORT} is listening but not as ${SERVICE_USER}: ${line}"
        return 1
    fi
    if ss -tln | grep -qE "(0\.0\.0\.0|\*|\[::\]):${PORT}\b"; then
        echo "FAIL  ${PORT} is also bound on a non-loopback address"
        return 1
    fi
    info "TCP listeners now: $(ss -tln | tail -n +2 | wc -l) (the brief expects eight)"
    return 0
}

check_health() {
    local out
    out=$(curl -s -m 5 "http://127.0.0.1:${PORT}/health" || true)
    if grep -q '"ok": true' <<<"$out"; then
        ok "GET /health: ${out}"
    else
        echo "FAIL  GET /health: '${out}'"
        return 1
    fi
    # Through the endpoint, so the connect(2) to the helper's socket happens
    # AS homelab-harness inside its sandbox -- the ADR-048 membership tested
    # live. `ping` makes no model call.
    out=$(curl -s -m 15 "http://127.0.0.1:${PORT}/health/helper" || true)
    if grep -q '"helper": "reachable"' <<<"$out"; then
        ok "GET /health/helper: the harness reached the helper's socket (no model call): ${out}"
        return 0
    fi
    echo "FAIL  GET /health/helper: '${out}'"
    info "If 'errno 13' (EACCES): ${SERVICE_USER} is not in ${MODEL_GROUP}, or the socket's group is not ${MODEL_GROUP}, or the unit was started before the membership existed (restart it)."
    info "If 'errno 2' (ENOENT): the helper socket is not up."
    return 1
}

check_third_account_refused() {
    # Brief test 18: the group is the boundary. `nobody` is outside it. The
    # probe must RUN and be refused; a probe that did not run is UNKNOWN.
    local out rc
    if [[ ! -f "${HELPER_CODE_DIR}/socket-probe.py" ]]; then
        echo "UNKNOWN  ${HELPER_CODE_DIR}/socket-probe.py is not installed; nothing was tested"
        return 1
    fi
    set +e
    out=$(setpriv --reuid=nobody --regid=nogroup --clear-groups \
            /usr/bin/python3 "${HELPER_CODE_DIR}/socket-probe.py" "$HELPER_SOCKET" 2>&1)
    rc=$?
    set -e
    if [[ $rc -ne 0 ]] && grep -q "PROBE FAIL" <<<"$out" && grep -qi "errno=13\|Permission denied" <<<"$out"; then
        ok "nobody (outside ${MODEL_GROUP}) is refused at the helper socket: $(head -1 <<<"$out")"
        return 0
    fi
    if [[ $rc -eq 0 ]]; then
        echo "FAIL  nobody CAN reach the helper socket -- the group is not a boundary"
    else
        echo "UNKNOWN  the probe did not report a permission refusal: ${out}"
    fi
    return 1
}

check_code_not_writable_by_runtime_user() {
    local bad=0 f n=0
    [[ -d "$CODE_DIR" ]] || { echo "UNKNOWN  ${CODE_DIR} does not exist"; return 1; }
    while IFS= read -r f; do
        n=$((n + 1))
        if setpriv --reuid="$SERVICE_USER" --regid="$SERVICE_USER" --clear-groups \
               /usr/bin/test -w "$f" 2>/dev/null; then
            echo "FAIL  ${SERVICE_USER} can modify $f, which it also executes"; bad=1
        fi
    done < <(find "$CODE_DIR" "$CONF_DIR" -type f 2>/dev/null)
    [[ $n -gt 0 ]] || { echo "UNKNOWN  no files under ${CODE_DIR}/${CONF_DIR}"; return 1; }
    [[ $bad -eq 0 ]] && ok "${n} files under ${CODE_DIR} and ${CONF_DIR}, none writable by ${SERVICE_USER}"
    return $bad
}

check_fixture_tests() {
    # As the harness account, against the installed helper.py (root:root
    # 0644, readable), with a stub in place of both CLIs: no allowance spent.
    local out rc tmp
    [[ -f "${CODE_DIR}/fixture-tests.py" ]] || { echo "UNKNOWN  ${CODE_DIR}/fixture-tests.py not installed"; return 1; }
    [[ -f "${HELPER_CODE_DIR}/helper.py" ]] || { echo "UNKNOWN  ${HELPER_CODE_DIR}/helper.py not installed"; return 1; }
    tmp=$(mktemp -d /tmp/homelab-p230-fixture.XXXXXX)
    chown "$SERVICE_USER:$SERVICE_USER" "$tmp"
    set +e
    out=$(setpriv --reuid="$SERVICE_USER" --regid="$SERVICE_USER" --clear-groups \
            env TMPDIR="$tmp" HOMELAB_HELPER_DIR="$HELPER_CODE_DIR" \
            /usr/bin/python3 "${CODE_DIR}/fixture-tests.py" 2>/dev/null)
    rc=$?
    set -e
    rm -rf "$tmp"
    if [[ $rc -eq 0 ]] && grep -q "^All .* checks passed" <<<"$out"; then
        ok "fixture tests passed as ${SERVICE_USER}: $(grep '^All' <<<"$out")"
        grep -E '^ok +(test [2-7]|audit)' <<<"$out" | sed 's/ --.*//; s/^/      /'
        return 0
    fi
    if grep -qE '^(ok|FAIL) ' <<<"$out"; then
        echo "FAIL  fixture tests did not all pass"
    else
        echo "UNKNOWN  the fixture tests did not run"
    fi
    grep -E '^(FAIL|UNKNOWN|[0-9]+ of)' <<<"$out" | sed 's/^/      /'
    return 1
}

check_security_score() {
    local score
    score=$(systemd-analyze security "$UNIT" 2>/dev/null | grep -oE 'Overall exposure level[^:]*: [0-9.]+' | grep -oE '[0-9.]+$' || true)
    if [[ -z "$score" ]]; then
        echo "UNKNOWN  systemd-analyze security gave no score"
        return 1
    fi
    if awk "BEGIN{exit !($score <= 2.0)}"; then
        ok "systemd-analyze security ${UNIT}: ${score} (baseline threshold 2.0)"
    else
        echo "FAIL  systemd-analyze security ${UNIT}: ${score} > 2.0 -- every finding above needs a # WHY in the unit"
        return 1
    fi
}

run_verify() {
    local rc=0
    echo "=== Harness -- verification (Phase 23.0) ==="
    check_account                        || rc=1
    check_group_membership               || rc=1
    check_unit_active                    || rc=1
    check_listener                       || rc=1
    check_health                         || rc=1
    check_third_account_refused          || rc=1
    check_code_not_writable_by_runtime_user || rc=1
    check_fixture_tests                  || rc=1
    check_security_score                 || rc=1
    echo
    if [[ $rc -eq 0 ]]; then
        echo "All checks passed."
    else
        echo "At least one check did not pass. A FAIL and an UNKNOWN are different claims."
    fi
    return $rc
}

run_install() {
    local f
    step "checking the source files in ${SRC}"
    for f in harness.py classify.py fixture-tests.py config.example.json \
             homelab-harness.service onfailure.conf; do
        [[ -f "${SRC}/${f}" ]] || fail "missing ${SRC}/${f} -- scp the harness files first"
    done
    ok "all six source files present"

    step "checking the prerequisites (ADR-048 group, helper installed)"
    getent group "$MODEL_GROUP" >/dev/null \
        || fail "group ${MODEL_GROUP} does not exist -- run 'install-model-helper.sh group' first"
    [[ -f "${HELPER_CODE_DIR}/helper.py" ]] || fail "${HELPER_CODE_DIR}/helper.py is not installed"
    ok "group ${MODEL_GROUP} exists; helper code present"

    step "creating the service account ${SERVICE_USER} (system, no shell, no home, groups: own + ${MODEL_GROUP})"
    if id "$SERVICE_USER" >/dev/null 2>&1; then
        info "account exists -- left alone; adding ${MODEL_GROUP} membership if missing"
        usermod -aG "$MODEL_GROUP" "$SERVICE_USER"
    else
        useradd --system --user-group --no-create-home --home-dir /nonexistent \
                --shell /usr/sbin/nologin --groups "$MODEL_GROUP" \
                --comment "Home Lab harness (Phase 23.0)" "$SERVICE_USER"
        ok "created ${SERVICE_USER}: $(id "$SERVICE_USER")"
    fi

    step "installing code to ${CODE_DIR} (root-owned, not writable by ${SERVICE_USER})"
    install -d -o root -g root -m 0755 "$CODE_DIR"
    for f in harness.py classify.py fixture-tests.py config.example.json; do
        install -o root -g root -m 0644 "${SRC}/${f}" "${CODE_DIR}/${f}"
    done
    ok "four files installed"

    step "installing config to ${CONF_DIR}/config.json"
    install -d -o root -g root -m 0755 "$CONF_DIR"
    if [[ -f "${CONF_DIR}/config.json" ]]; then
        info "${CONF_DIR}/config.json exists -- left alone"
    else
        install -o root -g root -m 0644 "${SRC}/config.example.json" "${CONF_DIR}/config.json"
        ok "config installed from the example (listen 127.0.0.1:${PORT}, audit in \$STATE_DIRECTORY)"
    fi

    step "installing the unit and its OnFailure= drop-in"
    install -o root -g root -m 0644 "${SRC}/homelab-harness.service" "${UNIT_DIR}/${UNIT}"
    install -d -o root -g root -m 0755 "${UNIT_DIR}/${UNIT}.d"
    install -o root -g root -m 0644 "${SRC}/onfailure.conf" "${UNIT_DIR}/${UNIT}.d/onfailure.conf"
    systemctl daemon-reload
    local vout
    vout=$(systemd-analyze verify "${UNIT_DIR}/${UNIT}" 2>&1 || true)
    if [[ -n "$vout" ]]; then
        echo "      systemd-analyze verify said:"; sed 's/^/      /' <<<"$vout"
    else
        ok "systemd-analyze verify accepted the unit with no complaint"
    fi
    # StateDirectory= always yields RequiresMountsFor=/var/lib/<name> -- a path on ROOT, which
    # is the point (brief §6.3). What must not appear is anything under /srv/homelab. OBSERVED
    # 2026-09-13: the first version asserted "empty" and failed on the root path.
    local rmf
    rmf=$(systemctl show -p RequiresMountsFor --value "$UNIT")
    if [[ "$rmf" == *"/srv/homelab"* ]]; then
        fail "the unit acquired RequiresMountsFor=${rmf} -- it must not depend on the volume"
    fi
    ok "RequiresMountsFor=${rmf:-<empty>} -- on root, nothing under /srv/homelab"

    step "enabling and starting ${UNIT} (boot-class: WantedBy=multi-user.target)"
    systemctl enable --now "$UNIT"
    sleep 1
    ok "enabled and started"
    echo
    run_verify
}

run_uninstall() {
    step "stopping and disabling ${UNIT}"
    systemctl disable --now "$UNIT" 2>/dev/null || true
    systemctl reset-failed "$UNIT" 2>/dev/null || true
    step "removing the unit, its drop-in, code and config"
    rm -f "${UNIT_DIR}/${UNIT}" "${UNIT_DIR}/${UNIT}.d/onfailure.conf"
    rmdir "${UNIT_DIR}/${UNIT}.d" 2>/dev/null || true
    rm -rf "$CODE_DIR" "$CONF_DIR"
    systemctl daemon-reload
    step "removing the account ${SERVICE_USER} (its group goes with it; ${MODEL_GROUP} stays)"
    if id "$SERVICE_USER" >/dev/null 2>&1; then
        userdel "$SERVICE_USER"
        ok "account removed"
    fi
    info "LEFT IN PLACE: ${STATE_DIR} (the audit file). Remove by hand if wanted."
    info "NOT REVERTED: the ${MODEL_GROUP} group and the helper socket's SocketGroup -- that is"
    info "the previous homelab-model-helper.socket from git + daemon-reload + socket restart (brief §7 rollback)."
    ok "uninstalled"
}

case "${1:-}" in
    install)   run_install ;;
    verify)    run_verify ;;
    uninstall) run_uninstall ;;
    *)         usage; exit 1 ;;
esac
