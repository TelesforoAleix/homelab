#!/usr/bin/env bash

# Continue through independent checks so one run reports every failure.
set -u

readonly CLAUDE_BIN="$HOME/.local/bin/claude"
readonly CODEX_BIN="$HOME/.local/bin/codex"

failures=0

ok() {
    printf 'ok   %s\n' "$*"
}

fail() {
    printf 'FAIL %s\n' "$*" >&2
    failures=$((failures + 1))
}

check_binary() {
    local name="$1"
    local path="$2"

    if [ ! -x "$path" ]; then
        fail "$name is not executable at $path"
        return
    fi

    printf '%-7s ' "$name:"
    "$path" --version || fail "$name --version failed"
}

check_environment() {
    local variable

    printf '\n--- API-billing environment ---\n'
    for variable in \
        ANTHROPIC_API_KEY \
        ANTHROPIC_AUTH_TOKEN \
        CLAUDE_CODE_OAUTH_TOKEN \
        OPENAI_API_KEY \
        CODEX_ACCESS_TOKEN
    do
        if printenv "$variable" >/dev/null 2>&1; then
            fail "$variable is set; value deliberately not printed"
        else
            ok "$variable is unset"
        fi
    done
}

check_credential_file() {
    local label="$1"
    local path="$2"
    local mode
    local owner
    local expected_owner

    if [ ! -e "$path" ]; then
        fail "$label credential file is absent: $path"
        return
    fi

    mode="$(stat -c '%a' "$path")"
    owner="$(stat -c '%U:%G' "$path")"
    expected_owner="$(id -un):$(id -gn)"
    printf '%s: path=%s mode=%s owner=%s\n' "$label" "$path" "$mode" "$owner"

    [ "$mode" = "600" ] || fail "$label credential file mode is $mode, expected 600"
    [ "$owner" = "$expected_owner" ] ||
        fail "$label credential file owner is $owner, expected $expected_owner"
}

check_authentication() {
    local claude_status
    local codex_status

    printf '\n--- authentication class (no identifiers or tokens) ---\n'
    if claude_status="$("$CLAUDE_BIN" auth status 2>/dev/null)"; then
        if command -v jq >/dev/null 2>&1; then
            if ! printf '%s\n' "$claude_status" |
                jq -e '{loggedIn, authMethod, apiProvider, subscriptionType} |
                    select(.loggedIn == true and .authMethod == "claude.ai" and
                    .apiProvider == "firstParty" and .subscriptionType != null)'
            then
                fail "Claude is authenticated through an unexpected billing class"
            fi
        else
            fail "jq is required to verify Claude's redacted authentication class"
        fi
    else
        fail "Claude does not report an authenticated session"
    fi

    if codex_status="$("$CODEX_BIN" login status 2>&1)"; then
        if [[ "$codex_status" == *"Logged in using ChatGPT"* ]]; then
            ok "Codex reports Sign in with ChatGPT"
        else
            fail "Codex is authenticated through an unexpected billing class"
        fi
    else
        fail "Codex does not report an authenticated session"
    fi

    printf '\n--- credential metadata only ---\n'
    check_credential_file "Claude" "$HOME/.claude/.credentials.json"
    check_credential_file "Codex" "$HOME/.codex/auth.json"
}

check_sandbox_prerequisite() {
    local restriction_file="/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
    local restriction

    printf '\n--- Codex Linux sandbox prerequisite ---\n'
    if command -v bwrap >/dev/null 2>&1; then
        bwrap --version || fail "bwrap --version failed"
    else
        fail "bubblewrap is not installed"
    fi

    if [ -r "$restriction_file" ]; then
        restriction="$(<"$restriction_file")"
        printf 'kernel.apparmor_restrict_unprivileged_userns = %s\n' "$restriction"
        [ "$restriction" = "1" ] ||
            fail "AppArmor's unprivileged user-namespace restriction is not enabled"
    else
        fail "cannot read $restriction_file"
    fi

    [ -r /etc/apparmor.d/bwrap-userns-restrict ] ||
        fail "Ubuntu's bwrap AppArmor profile is absent or unreadable"
}

check_host_impact() {
    local failed_units
    local matching_units
    local process_output
    local system_state
    local unit_output

    printf '\n--- persistent host impact ---\n'
    process_output="$(pgrep -f '(^|/)(claude|codex)( |$)' 2>/dev/null || true)"
    if [ -n "$process_output" ]; then
        printf 'matching AI process count: %s\n' "$(printf '%s\n' "$process_output" | wc -l)"
        fail "Claude or Codex process remains running"
    else
        ok "no Claude or Codex process remains"
    fi

    if unit_output="$(systemctl list-unit-files --no-legend 2>/dev/null)"; then
        matching_units="$(printf '%s\n' "$unit_output" | rg -i '(claude|codex)' || true)"
        if [ -n "$matching_units" ]; then
            printf '%s\n' "$matching_units"
            fail "Claude or Codex systemd unit exists"
        else
            ok "no Claude or Codex systemd unit exists"
        fi
    else
        fail "could not inspect systemd unit files"
    fi

    if command -v docker >/dev/null 2>&1; then
        docker system df || fail "docker system df failed"
    fi

    df -h / || fail "root filesystem check failed"
    ss -tln || fail "listener check failed"

    system_state="$(systemctl is-system-running 2>/dev/null || true)"
    if [ "$system_state" = "running" ]; then
        ok "system state is running"
    else
        fail "system state is ${system_state:-unknown}, expected running"
    fi

    if failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null)"; then
        if [ -z "$failed_units" ]; then
            ok "no failed systemd units"
        else
            printf '%s\n' "$failed_units"
            fail "failed systemd units exist"
        fi
    else
        fail "could not query failed systemd units"
    fi
}

main() {
    [ "$(id -u)" -ne 0 ] || {
        printf 'error: run as the user whose AI CLI access is being verified, not root\n' >&2
        exit 2
    }

    printf '%s\n' '--- installed versions ---'
    check_binary "Claude" "$CLAUDE_BIN"
    check_binary "Codex" "$CODEX_BIN"
    check_environment
    check_authentication
    check_sandbox_prerequisite
    check_host_impact

    printf '\n--- result ---\n'
    if [ "$failures" -eq 0 ]; then
        ok "AI CLI access checks passed"
        exit 0
    fi

    printf 'FAIL %s check(s) failed\n' "$failures" >&2
    exit 1
}

main "$@"
