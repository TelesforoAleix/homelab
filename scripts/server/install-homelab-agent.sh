#!/usr/bin/env bash
#
# install-homelab-agent.sh -- Phase 13.1, ADR-049. The executor agent's own
# account on the node: a key, a shell, and a closed NOPASSWD command list.
#
# Run on:  the node, as root (sudo bash ...), by the OWNER. Never by the agent:
#          the agent's grant does not include this script, useradd, or visudo,
#          and must never -- ADR-049 section 3, "change its own grant".
#
# WHAT THIS SCRIPT REFUSES TO DO
# ------------------------------
#   - touch sshd. AllowUsers is lockout-class (safe-changes-headless.md); the
#     owner appends the account in a second-session window, with sshd -t, a
#     reload, and a third connection. This script prints that step and stops.
#   - add homelab-agent to any group but its own (not sudo, docker,
#     homelab-model, aleix)
#   - install a sudoers file that visudo has not accepted first
#   - overwrite a same-day .bak of a previous sudoers file
#
# WHAT `verify` PROVES, BY DOING IT AS homelab-agent
# --------------------------------------------------
#   Every allow in ADR-049 section 2 is run; every deny in section 3 is
#   attempted. Harmless denies are attempted for real with output discarded
#   (a broken deny on `cat gateway-key` must not print the key). Destructive
#   denies (reboot, usermod -aG sudo, data-volume.sh lock) are probed with
#   `sudo -n -l <cmd>`, which reports the decision without running anything:
#   "attempting" a reboot to prove it is denied is not a test, it is a bet.
#   sudo-rs matches arguments exactly (a lone trailing `*` is its only
#   wildcard), so three probes check that an extra argument, a second unit
#   and a `..` path are refused -- each against a harmless target.
#
# Landing the sudoers file IS lockout-class: a parse error in any file under
# /etc/sudoers.d/ disables sudo for every account. Hence visudo -c -f before
# install, and hence the runbook holds a root shell in a second session.

set -euo pipefail

AGENT="homelab-agent"
AGENT_HOME="/home/${AGENT}"
SUDOERS_DST="/etc/sudoers.d/${AGENT}"
SSHD_DROPIN="/etc/ssh/sshd_config.d/10-homelab-hardening.conf"
STAGE="/tmp/${AGENT}"                      # the agent's staging directory (brief 6.2)
SRC="${SRC:-/tmp/p131}"                    # where the owner scp'd this phase's files
HELPER_CONF="/etc/homelab-model-helper/config.json"
HELPER_STATE="/var/lib/homelab-model-helper"
HELPER_KEY="/etc/homelab-model-helper/gateway-key"
BOT_TOKEN="/etc/homelab-telegram-bot/token.cred"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok    $*"; }
info() { echo "      $*"; }

[[ $EUID -eq 0 ]] || fail "run as root: sudo bash $0 $*"

usage() {
    cat <<'USAGE'
Usage: install-homelab-agent.sh <install <pubkey-file> | verify | uninstall>

  install <pubkey-file>  create the account (no password, /bin/bash, own
                         group only), install its authorized_keys from the
                         PUBLIC key file given, visudo-check then install
                         config/sudoers.d/homelab-agent (0440), then verify.
                         Does NOT touch sshd -- prints the owner's step.
  verify                 re-run every check without changing anything; runs
                         every allow and attempts every deny as homelab-agent.
  uninstall              remove the sudoers file first, then the account and
                         its home. Prints the sshd line to remove.

Expects in $SRC (default /tmp/p131): homelab-agent (the sudoers file).
USAGE
}

# --------------------------------------------------------------------------
# Running things AS the agent. runuser, not sudo -u: this script is already
# root, and a nested sudo would test root's rules, not the agent's.
# --------------------------------------------------------------------------

as_agent() { runuser -u "$AGENT" -- "$@"; }

# agent_sudo <cmd...>: run `sudo -n cmd` as the agent. stdout discarded,
# stderr captured in $ERR, rc in $RC. Never prints the command's output --
# if a deny is broken the secret stays off the terminal.
ERR=""; RC=0
agent_sudo() {
    set +e
    ERR=$(as_agent sudo -n "$@" 2>&1 >/dev/null)
    RC=$?
    set -e
}

# sudo-rs refuses with "I'm sorry <user>. I'm afraid I can't do that"
# (OBSERVED 2026-09-13, S2 step 1: every deny was refused and this function,
# knowing only C sudo's phrasings, reported all nineteen as UNKNOWN).
denied_msg() { grep -qiE "not allowed|password is required|not permitted|afraid I can't do that" <<<"$1"; }

# expect_allowed <label> <cmd...>: rc 0 => ok. rc != 0 with a sudo denial
# message => FAIL (the grant is missing). rc != 0 otherwise => the command
# itself failed; report as UNKNOWN with its stderr, since that is a different
# claim from "denied".
expect_allowed() {
    local label="$1"; shift
    agent_sudo "$@"
    if [[ $RC -eq 0 ]]; then ok "ALLOW  $label"; return 0; fi
    if denied_msg "$ERR"; then
        echo "FAIL  ALLOW  $label -- sudo refused it: ${ERR}"
    else
        echo "UNKNOWN  ALLOW  $label -- ran but failed (rc=$RC): ${ERR}"
    fi
    return 1
}

# expect_denied <label> <cmd...>: sudo must refuse. A run that succeeds is a
# FAIL; a run that fails for another reason is UNKNOWN (the command ran).
expect_denied() {
    local label="$1"; shift
    agent_sudo "$@"
    if [[ $RC -ne 0 ]] && denied_msg "$ERR"; then ok "DENY   $label"; return 0; fi
    if [[ $RC -eq 0 ]]; then
        echo "FAIL  DENY   $label -- sudo RAN it. The grant is wider than ADR-049."
    else
        echo "UNKNOWN  DENY   $label -- not refused by sudo; the command itself failed (rc=$RC): ${ERR}"
    fi
    return 1
}

# expect_denied_dry <label> <cmd...>: `sudo -n -l cmd` lists the decision
# without executing. Exit 0 = would be allowed (FAIL), 1 = refused (ok),
# anything else = the list form is unsupported here (UNKNOWN; sudo-rs).
expect_denied_dry() {
    local label="$1"; shift
    local out rc
    set +e
    out=$(as_agent sudo -n -l "$@" 2>&1)
    rc=$?
    set -e
    case $rc in
        0) echo "FAIL  DENY   $label -- sudo -l says it WOULD run"; return 1 ;;
        1) ok "DENY   $label (sudo -l, not executed)"; return 0 ;;
        *) echo "UNKNOWN  DENY   $label -- 'sudo -l <cmd>' unsupported (rc=$rc): ${out}"; return 1 ;;
    esac
}

# --------------------------------------------------------------------------
# Checks. Each can say UNKNOWN rather than invent a verdict.
# --------------------------------------------------------------------------

check_account() {
    local rc=0 groups shell home_mode pw
    if ! id "$AGENT" >/dev/null 2>&1; then
        echo "FAIL  account ${AGENT} does not exist"; return 1
    fi
    groups=$(id -nG "$AGENT" | tr ' ' '\n' | sort | paste -sd' ' -)
    if [[ "$groups" == "$AGENT" ]]; then
        ok "${AGENT} is in exactly its own group: $(id "$AGENT")"
    else
        echo "FAIL  ${AGENT} groups are '${groups}', expected only '${AGENT}'"; rc=1
    fi
    shell=$(getent passwd "$AGENT" | cut -d: -f7)
    [[ "$shell" == "/bin/bash" ]] && ok "shell is /bin/bash" \
        || { echo "FAIL  shell is ${shell}, expected /bin/bash"; rc=1; }
    pw=$(passwd -S "$AGENT" 2>/dev/null | awk '{print $2}')
    case "$pw" in
        L|NP) ok "no usable password (passwd -S: ${pw})" ;;
        *)    echo "FAIL  passwd -S reports '${pw}' -- the account must have no password"; rc=1 ;;
    esac
    if [[ -d "$AGENT_HOME/.ssh" ]]; then
        home_mode=$(stat -c '%U:%G:%a' "$AGENT_HOME/.ssh")
        [[ "$home_mode" == "${AGENT}:${AGENT}:700" ]] && ok ".ssh is ${home_mode}" \
            || { echo "FAIL  .ssh is ${home_mode}, expected ${AGENT}:${AGENT}:700"; rc=1; }
    else
        echo "FAIL  ${AGENT_HOME}/.ssh does not exist"; rc=1
    fi
    if [[ -f "$AGENT_HOME/.ssh/authorized_keys" ]]; then
        local ak_mode ak_lines
        ak_mode=$(stat -c '%U:%G:%a' "$AGENT_HOME/.ssh/authorized_keys")
        ak_lines=$(grep -c . "$AGENT_HOME/.ssh/authorized_keys" || true)
        [[ "$ak_mode" == "${AGENT}:${AGENT}:600" ]] && ok "authorized_keys is ${ak_mode}, ${ak_lines} key line(s)" \
            || { echo "FAIL  authorized_keys is ${ak_mode}"; rc=1; }
        [[ "$ak_lines" -eq 1 ]] || { echo "FAIL  authorized_keys has ${ak_lines} lines; ADR-049 says one key, revocable by one line"; rc=1; }
    else
        echo "FAIL  no authorized_keys"; rc=1
    fi
    return $rc
}

check_sudoers_file() {
    local spec
    [[ -f "$SUDOERS_DST" ]] || { echo "FAIL  ${SUDOERS_DST} does not exist"; return 1; }
    spec=$(stat -c '%U:%G:%a' "$SUDOERS_DST")
    [[ "$spec" == "root:root:440" ]] || { echo "FAIL  ${SUDOERS_DST} is ${spec}, expected root:root:440"; return 1; }
    if visudo -c -f "$SUDOERS_DST" >/dev/null 2>&1; then
        ok "${SUDOERS_DST} is ${spec} and visudo -c -f accepts it"
    else
        echo "FAIL  visudo -c -f rejects ${SUDOERS_DST}:"; visudo -c -f "$SUDOERS_DST" 2>&1 | sed 's/^/      /'
        return 1
    fi
    if [[ -f "${SRC}/homelab-agent" ]] && ! cmp -s "${SRC}/homelab-agent" "$SUDOERS_DST"; then
        echo "FAIL  ${SUDOERS_DST} differs from ${SRC}/homelab-agent (the committed file)"
        diff "${SRC}/homelab-agent" "$SUDOERS_DST" | sed 's/^/      /' || true
        return 1
    fi
}

show_sudo_l() {
    # Brief row 4: pasted verbatim into the guide. Two forms, because sudo-rs
    # may not accept -U; the agent listing its own grant is the same truth.
    echo "--> sudo -l for ${AGENT} (ground truth of the grant; paste into the guide)"
    if sudo -n -l -U "$AGENT" 2>/dev/null | sed 's/^/      /'; then return 0; fi
    info "(sudo -l -U unsupported here; listing as the agent instead)"
    as_agent sudo -n -l 2>&1 | sed 's/^/      /' || echo "UNKNOWN  neither form of sudo -l worked"
}

check_allows() {
    # ADR-049 section 2, each by doing it. Brief rows 5, 6, 7 (allow half),
    # 10, 11 (allow half). Nothing here changes durable state: the harness
    # restart is what a runbook does routinely; the config re-install writes
    # byte-identical content; the ledger copy is removed again.
    local rc=0
    echo "--> every allow, run as ${AGENT}"
    # Exact unit names, suffix included: that is what the grant says.
    expect_allowed "systemctl restart homelab-harness.service"  systemctl restart homelab-harness.service || rc=1
    sleep 1
    expect_allowed "systemctl is-active homelab-harness.service" systemctl is-active homelab-harness.service || rc=1
    expect_allowed "systemctl status homelab-harness.service"   systemctl status homelab-harness.service  || rc=1
    expect_allowed "systemctl show homelab-harness.service"     systemctl show homelab-harness.service    || rc=1
    expect_allowed "systemctl cat homelab-harness.service"      systemctl cat homelab-harness.service     || rc=1
    expect_allowed "systemctl is-enabled homelab-harness.service" systemctl is-enabled homelab-harness.service || rc=1
    expect_allowed "systemctl reset-failed homelab-harness.service" systemctl reset-failed homelab-harness.service || rc=1
    expect_allowed "systemctl daemon-reload"                    systemctl daemon-reload                  || rc=1
    expect_allowed "systemctl list-units --failed"              systemctl list-units --failed            || rc=1
    expect_allowed "systemctl --failed"                         systemctl --failed                       || rc=1
    expect_allowed "systemctl list-timers"                      systemctl list-timers                    || rc=1
    expect_allowed "systemctl is-system-running"                systemctl is-system-running              || true  # rc 1 = degraded; reported below
    expect_allowed "journalctl -u homelab-harness -n 3"         journalctl -u homelab-harness -n 3 --no-pager || rc=1
    expect_allowed "ss -tlnp"                                   ss -tlnp                                 || rc=1
    expect_allowed "systemd-analyze security homelab-harness"   systemd-analyze security --no-pager homelab-harness.service || rc=1
    expect_allowed "systemd-analyze verify homelab-harness"     systemd-analyze verify homelab-harness.service || rc=1
    expect_allowed "stat /etc/homelab-model-helper"             stat /etc/homelab-model-helper           || rc=1
    expect_allowed "ls /etc/homelab-model-helper"               ls /etc/homelab-model-helper             || rc=1
    expect_allowed "cat ${HELPER_CONF}"                         cat "$HELPER_CONF"                       || rc=1
    expect_allowed "getent passwd ${AGENT}"                     getent passwd "$AGENT"                   || rc=1
    expect_allowed "id aleix"                                   id aleix                                 || rc=1
    expect_allowed "data-volume.sh status"                      /usr/local/sbin/data-volume.sh status    || rc=1

    # Row 7, allow half: stage a copy and install it over itself. The result
    # must be byte-identical and still 0644 root:root (the mode the helper,
    # running as aleix, needs to read it).
    local before after
    as_agent mkdir -p "$STAGE"
    before=$(sha256sum "$HELPER_CONF" | cut -d' ' -f1)
    cp "$HELPER_CONF" "${STAGE}/model-helper-config.json"; chown "$AGENT:$AGENT" "${STAGE}/model-helper-config.json"
    expect_allowed "install model-helper-config.json from ${STAGE}" \
        install -m 644 -o root -g root "${STAGE}/model-helper-config.json" "$HELPER_CONF" || rc=1
    after=$(sha256sum "$HELPER_CONF" | cut -d' ' -f1)
    [[ "$before" == "$after" && "$(stat -c '%U:%G:%a' "$HELPER_CONF")" == "root:root:644" ]] \
        && ok "config.json byte-identical after re-install, still root:root:644" \
        || { echo "FAIL  config.json changed or lost its mode after re-install"; rc=1; }

    # Row 11, allow half: cp -p to the fixed .bak name, check its owner, mv
    # it back over the original (same bytes). The ledger's owner must be what
    # it was: the helper writes it as aleix.
    if [[ -f "${HELPER_STATE}/spend.json" ]]; then
        local owner_before owner_after
        owner_before=$(stat -c '%U:%G:%a' "${HELPER_STATE}/spend.json")
        expect_allowed "cp -p spend.json spend.json.bak" \
            cp -p "${HELPER_STATE}/spend.json" "${HELPER_STATE}/spend.json.bak" || rc=1
        owner_after=$(stat -c '%U:%G:%a' "${HELPER_STATE}/spend.json.bak" 2>/dev/null || echo missing)
        expect_allowed "mv spend.json.bak spend.json" \
            mv "${HELPER_STATE}/spend.json.bak" "${HELPER_STATE}/spend.json" || rc=1
        [[ "$owner_before" == "$owner_after" && "$(stat -c '%U:%G:%a' "${HELPER_STATE}/spend.json")" == "$owner_before" ]] \
            && ok "ledger copy kept owner/mode ${owner_before} (cp -p as root preserves aleix)" \
            || { echo "FAIL  ledger copy is ${owner_after}, original ${owner_before} -- the helper could not write a restored ledger"; rc=1; }
    else
        echo "UNKNOWN  ${HELPER_STATE}/spend.json does not exist (Phase 15.1 not landed?); cp/mv allow not exercised"
    fi
    return $rc
}

check_denies() {
    # ADR-049 section 3, each by attempting it. Brief rows 7 (deny half), 8,
    # 9, 11 (deny half), plus the glob holes.
    local rc=0
    echo "--> every named deny, attempted as ${AGENT} (output discarded)"
    expect_denied "cat gateway-key"                cat "$HELPER_KEY"                         || rc=1
    expect_denied "cat token.cred"                 cat "$BOT_TOKEN"                          || rc=1
    expect_denied "install to gateway-key"         install -m 644 -o root -g root "${STAGE}/model-helper-config.json" "$HELPER_KEY" || rc=1
    expect_denied "install with -m 600"            install -m 600 -o root -g root "${STAGE}/model-helper-config.json" "$HELPER_CONF" || rc=1
    expect_denied "sshd -t"                        sshd -t                                   || rc=1
    expect_denied "ufw status"                     ufw status                                || rc=1
    expect_denied "tailscale status"               tailscale status                          || rc=1
    expect_denied "visudo -c"                      visudo -c                                 || rc=1
    expect_denied "apt update (not run)"           apt-get --simulate update                 || rc=1
    expect_denied "systemd-creds list"             systemd-creds list                        || rc=1
    expect_denied "getent shadow"                  getent shadow "$AGENT"                    || rc=1
    expect_denied "cp spend.json to /tmp"          cp -p "${HELPER_STATE}/spend.json" "${STAGE}/x" || rc=1
    expect_denied "cp without -p"                  cp "${HELPER_STATE}/spend.json" "${HELPER_STATE}/spend.json.bak" || rc=1
    expect_denied "systemctl restart ssh"          systemctl restart ssh.service             || rc=1
    expect_denied "systemctl edit homelab-harness" systemctl edit homelab-harness            || rc=1

    echo "--> destructive denies, decided by sudo -l without running (reboot, usermod, lock)"
    expect_denied_dry "reboot"                     /usr/sbin/reboot                          || rc=1
    expect_denied_dry "systemctl reboot"           /usr/bin/systemctl reboot                 || rc=1
    expect_denied_dry "usermod -aG sudo ${AGENT}"  /usr/sbin/usermod -aG sudo "$AGENT"       || rc=1
    expect_denied_dry "data-volume.sh lock"        /usr/local/sbin/data-volume.sh lock       || rc=1
    expect_denied_dry "data-volume.sh unlock"      /usr/local/sbin/data-volume.sh unlock     || rc=1

    echo "--> exact matching: an extra argument, a second unit, a .. path (harmless targets)"
    expect_denied "cat config.json /etc/hostname" cat "$HELPER_CONF" /etc/hostname      || rc=1
    expect_denied "cat via .." cat /etc/homelab-model-helper/../hostname                || rc=1
    expect_denied "systemctl restart harness + workbench" \
        systemctl restart homelab-harness.service homelab-workbench.service              || rc=1
    expect_denied "systemctl restart homelab-harness (no suffix)" \
        systemctl restart homelab-harness                                                || rc=1
    rm -f "${STAGE}/model-helper-config.json"
    return $rc
}

check_sshd_allowusers() {
    # Informational before the owner's sshd step; a FAIL after it. The script
    # cannot tell which side of that step it is on, so it reports, only.
    local n
    n=$(grep -c "^AllowUsers.*\b${AGENT}\b" "$SSHD_DROPIN" 2>/dev/null || true)
    if [[ "$n" -eq 1 ]]; then
        ok "AllowUsers names ${AGENT} in ${SSHD_DROPIN}; sshd -T says: $(sshd -T 2>/dev/null | grep -i '^allowusers' || echo '?')"
    else
        info "AllowUsers does NOT yet name ${AGENT} -- the account cannot log in until the owner's sshd step (lockout-class; see the runbook)"
    fi
}

check_no_new_listener() {
    local n
    n=$(ss -tln | tail -n +2 | wc -l)
    ok "TCP listeners: ${n} (this phase adds none; Phase 13's baseline is eight)"
}

run_verify() {
    local rc=0
    echo "=== homelab-agent -- verification (Phase 13.1, ADR-049) ==="
    echo
    check_account       || rc=1
    check_sudoers_file  || rc=1
    show_sudo_l
    check_allows        || rc=1
    check_denies        || rc=1
    check_sshd_allowusers
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
    local pub="${1:-}"
    [[ -n "$pub" ]] || { usage; fail "install needs the PUBLIC key file"; }
    [[ -f "$pub" ]] || fail "no such file: ${pub}"
    [[ -f "${SRC}/homelab-agent" ]] || fail "missing ${SRC}/homelab-agent -- scp config/sudoers.d/homelab-agent first"

    # The public half only. A private key is 'BEGIN OPENSSH PRIVATE KEY';
    # refuse it rather than install it as authorized_keys and carry on.
    grep -q 'PRIVATE KEY' "$pub" && fail "${pub} is a PRIVATE key. Only the .pub crosses to the node."
    local fp
    fp=$(ssh-keygen -l -f "$pub" 2>/dev/null) || fail "${pub} is not a valid public key"
    grep -q 'ED25519' <<<"$fp" || fail "expected an Ed25519 key, got: ${fp}"
    [[ $(grep -c . "$pub") -eq 1 ]] || fail "${pub} must hold exactly one key line"
    ok "public key: ${fp}"

    echo "--> validating the sudoers file BEFORE anything lands (lockout-class if wrong)"
    visudo -c -f "${SRC}/homelab-agent" || fail "visudo rejected ${SRC}/homelab-agent -- nothing installed"
    ok "visudo -c -f accepted ${SRC}/homelab-agent"

    echo "--> account"
    if id "$AGENT" >/dev/null 2>&1; then
        info "${AGENT} exists -- left alone: $(id "$AGENT")"
    else
        # -p '*': no password at all. Not `!`-locked: OpenSSH's own locked-
        # account check keys on a leading '!' (brief 6.1 resolution).
        useradd --system --create-home --home-dir "$AGENT_HOME" --shell /bin/bash \
                --user-group --password '*' --comment "Homelab executor agent (ADR-049)" "$AGENT"
        ok "created ${AGENT}: $(id "$AGENT")"
    fi
    [[ "$(id -nG "$AGENT" | tr ' ' '\n' | sort | paste -sd' ' -)" == "$AGENT" ]] \
        || fail "${AGENT} is in a group other than its own: $(id "$AGENT"). Refusing to continue."

    echo "--> authorized_keys (the one revocable line)"
    install -d -o "$AGENT" -g "$AGENT" -m 0700 "$AGENT_HOME/.ssh"
    install -o "$AGENT" -g "$AGENT" -m 0600 "$pub" "$AGENT_HOME/.ssh/authorized_keys"
    ok "installed ${AGENT_HOME}/.ssh/authorized_keys"

    echo "--> sudoers (previous kept as .bak-$(date +%F), never overwritten the same day)"
    local bak="${SUDOERS_DST}.bak-$(date +%F)"
    if [[ -f "$SUDOERS_DST" && ! -f "$bak" ]]; then
        # Kept OUTSIDE /etc/sudoers.d/. sudo skips names containing '.' or
        # '~' there, so a .bak would in fact be ignored -- but a backup whose
        # safety rests on a filename rule is not a habit worth having.
        bak="/root/sudoers-${AGENT}.bak-$(date +%F)"
        cp -p "$SUDOERS_DST" "$bak"; ok "previous sudoers kept at ${bak}"
    fi
    install -o root -g root -m 0440 "${SRC}/homelab-agent" "$SUDOERS_DST"
    visudo -c -f "$SUDOERS_DST" >/dev/null || { rm -f "$SUDOERS_DST"; fail "installed file failed visudo -c; REMOVED it. sudo is intact."; }
    ok "installed ${SUDOERS_DST} (root:root 0440), visudo -c -f accepts it"

    as_agent mkdir -p "$STAGE"
    ok "staging directory ${STAGE} exists (cleared at boot)"

    echo
    run_verify || true
    cat <<STEP

=== OWNER STEP THIS SCRIPT DID NOT DO (lockout-class) ===
The account cannot log in until sshd's AllowUsers names it. In the runbook's
second-session window: scp the updated config/ssh/10-homelab-hardening.conf
(AllowUsers aleix ${AGENT}), keep a .bak-<date>, run
  sudo bash /tmp/p131/apply-ssh-hardening.sh     # sshd -t, then reload
then from the MacBook: ssh -o BatchMode=yes homelab true   (owner still in)
                       ssh homelab-agent true             (agent now in)
and a THIRD fresh connection before closing the second session.
STEP
}

run_uninstall() {
    echo "=== removing ${AGENT} (sudoers first, so no grant outlives its account) ==="
    if [[ -f "$SUDOERS_DST" ]]; then rm -f "$SUDOERS_DST"; ok "removed ${SUDOERS_DST}"; else info "no sudoers file"; fi
    visudo -c >/dev/null && ok "sudoers still parses (sudo intact)" || echo "FAIL  visudo -c rejects the remaining sudoers -- fix from the root shell in session 2"
    if id "$AGENT" >/dev/null 2>&1; then
        pkill -u "$AGENT" 2>/dev/null || true
        userdel -r "$AGENT" 2>/dev/null || userdel "$AGENT"
        ok "removed account ${AGENT} and its home"
    else
        info "no account ${AGENT}"
    fi
    rm -rf "$STAGE"
    cat <<STEP

=== OWNER STEP THIS SCRIPT DID NOT DO (lockout-class) ===
Remove '${AGENT}' from AllowUsers in ${SSHD_DROPIN} (back to 'AllowUsers aleix'),
sshd -t, systemctl reload ssh, from the second-session window. The MacBook's
~/.ssh/id_ed25519_homelab_agent and the Host homelab-agent alias are the
owner's to delete; the key is worthless without the authorized_keys line.
STEP
}

case "${1:-}" in
    install)   run_install "${2:-}" ;;
    verify)    run_verify ;;
    uninstall) run_uninstall ;;
    *)         usage; exit 1 ;;
esac
