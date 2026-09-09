#!/usr/bin/env bash

set -Eeuo pipefail

readonly CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
readonly CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"

usage() {
    cat <<'EOF'
Usage:
  install-ai-clis.sh stage STAGING_DIRECTORY
  install-ai-clis.sh install STAGING_DIRECTORY

stage     Download the two official installers, validate their shell syntax,
          and record SHA-256 hashes. Review the staged files before continuing.
install   Verify the staged hashes, ask for confirmation, and run the exact
          reviewed files as the current non-root user.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

check_host() {
    [ "$(id -u)" -ne 0 ] || die "run as the target user, not root or sudo"
    [ "$(uname -s)" = "Linux" ] || die "this helper is for the Linux reference node"

    case "$(uname -m)" in
        x86_64|amd64|aarch64|arm64) ;;
        *) die "unsupported architecture: $(uname -m)" ;;
    esac

    [ -n "${HOME:-}" ] || die "HOME is not set"
    [ -d "$HOME" ] && [ -w "$HOME" ] || die "HOME is not a writable directory"

    require_command curl
    require_command sha256sum
    require_command stat
}

check_stage_directory() {
    local staging_directory="$1"

    [ -n "$staging_directory" ] || die "a staging directory is required"
    [ "$staging_directory" != "/" ] || die "refusing the filesystem root as a staging directory"
    [ -d "$staging_directory" ] || die "staging directory does not exist: $staging_directory"
    [ ! -L "$staging_directory" ] || die "staging directory must not be a symlink"
    [ "$(stat -c '%U' "$staging_directory")" = "$(id -un)" ] ||
        die "staging directory is not owned by $(id -un)"
}

stage_installers() {
    local staging_directory="$1"

    [ -n "$staging_directory" ] || die "a staging directory is required"
    [ "$staging_directory" != "/" ] || die "refusing the filesystem root as a staging directory"
    [ ! -e "$staging_directory" ] || die "staging path already exists: $staging_directory"

    umask 077
    install -d -m 700 "$staging_directory"

    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        "$CLAUDE_INSTALL_URL" --output "$staging_directory/claude-install.sh"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        "$CODEX_INSTALL_URL" --output "$staging_directory/codex-install.sh"
    chmod 600 "$staging_directory/claude-install.sh" "$staging_directory/codex-install.sh"

    bash -n "$staging_directory/claude-install.sh"
    sh -n "$staging_directory/codex-install.sh"

    (
        cd "$staging_directory"
        sha256sum claude-install.sh codex-install.sh > SHA256SUMS
    )

    printf 'Staged installers in %s\n' "$staging_directory"
    cat "$staging_directory/SHA256SUMS"
    printf '\nReview both scripts, then run:\n  %q install %q\n' "$0" "$staging_directory"
}

install_staged() {
    local staging_directory="$1"
    local staged_file
    local answer

    check_stage_directory "$staging_directory"

    for staged_file in claude-install.sh codex-install.sh SHA256SUMS; do
        [ -f "$staging_directory/$staged_file" ] || die "missing staged file: $staged_file"
        [ ! -L "$staging_directory/$staged_file" ] || die "staged file must not be a symlink: $staged_file"
        [ "$(stat -c '%U' "$staging_directory/$staged_file")" = "$(id -un)" ] ||
            die "staged file is not owned by $(id -un): $staged_file"
    done

    (
        cd "$staging_directory"
        sha256sum --check SHA256SUMS
    )
    bash -n "$staging_directory/claude-install.sh"
    sh -n "$staging_directory/codex-install.sh"

    printf 'Run the two reviewed installers as %s? [y/N] ' "$(id -un)"
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) die "installation cancelled" ;;
    esac

    bash "$staging_directory/claude-install.sh" stable
    sh "$staging_directory/codex-install.sh"

    printf '\nInstalled commands:\n'
    "$HOME/.local/bin/claude" --version
    "$HOME/.local/bin/codex" --version
    printf '\nOpen a fresh interactive SSH terminal before using the commands by name.\n'
}

main() {
    local action="${1:-}"
    local staging_directory="${2:-}"

    [ "$#" -eq 2 ] || {
        usage >&2
        exit 2
    }

    check_host

    case "$action" in
        stage) stage_installers "$staging_directory" ;;
        install) install_staged "$staging_directory" ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
