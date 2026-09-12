#!/usr/bin/env bash
#
# backup-node.sh -- pull everything irreplaceable off the reference node, plus
# mirrors of every repository, encrypt both, and write them to removable media.
#
# WHY THIS EXISTS
#
#   Phase 04 gave the *repository* an offsite copy. It did nothing for the
#   *machine*. The node holds two OAuth credentials, a bot token, a polkit
#   grant, three service accounts, a hand-built unit with 22 hardening
#   directives, and a per-deployment allowlist -- none of which is in git and
#   none of which existed anywhere else before this script.
#
#   It is deliberately small. Measured, the irreplaceable state is ~2.3 MB and
#   the five repository mirrors are ~28 MB. That is the whole job. Anything
#   that reinstalls (the 366 MB of Codex packages, the /opt payloads that live
#   in git) is excluded on purpose: backing up replaceable bytes makes a
#   restore slower to verify and easier to skip.
#
# WHY IT IS INTERACTIVE, AND WHY THAT IS NOT A DEFECT
#
#   It prompts twice: once for the node's sudo password, once for the age
#   passphrase. That is the design, not an unfinished edge.
#
#   ADR-022 records that `aleix` is in the `docker` group and is therefore
#   root-equivalent. The Phase 18 brief (section 5) requires that the backup
#   must not quietly become a *second* root-equivalent path. A NOPASSWD
#   sudoers entry or a stored key would do exactly that -- a standing
#   privilege that exists whether or not anyone is backing anything up.
#   Typing a password once a week is the price of not creating one.
#
#   ADR-012 (progressive automation) says the same thing from the other side:
#   perform a process by hand while doing so is useful for understanding it.
#
# WHY EVERYTHING IS A TARBALL AND NOTHING IS COPIED LOOSE
#
#   The target is exFAT, which stores no POSIX modes, no ownership and no
#   symlinks. The node's file modes are load-bearing: the bot token is
#   0600 root:root and reaches the unprivileged service through systemd's
#   LoadCredential=, and the three allowlists are 0640 root:homelab-bot.
#   Copied loose onto exFAT those would silently flatten, and the restore
#   would either break the service or widen who can read a token.
#
#   `--numeric-owner` matters for the same reason: homelab-bot is uid 999 /
#   gid 982, and the socket's SocketGroup=homelab-bot breaks if a rebuild
#   renumbers it.
#
# WHY age, AND NOT A macOS ENCRYPTED DISK IMAGE
#
#   The restore target is a rebuilt *Ubuntu* node, not a Mac. A sparsebundle
#   would be unopenable at precisely the moment it is needed. age has Linux
#   builds and one obvious way to use it.
#
#   Passphrase rather than a key file, because a key file stored on the Mac
#   dies with the Mac -- and surviving the loss of the Mac is the entire point
#   of a card that lives somewhere else. Keep the passphrase in a password
#   manager. Never on the card.
#
# USAGE
#
#   ./backup-node.sh                      # writes to /Volumes/SD Card
#   DEST="/Volumes/Other" ./backup-node.sh
#   ./backup-node.sh --force              # overwrite today's directory
#
set -euo pipefail

NODE="${NODE:-homelab}"
DEST="${DEST:-/Volumes/SD Card}"
ROOT="${DEST}/homelab-backup"
STAMP="$(date +%Y-%m-%d)"
OUT="${ROOT}/${STAMP}"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

# Repositories to mirror. Mirrored from the LOCAL clones rather than from
# GitHub on purpose: the local copies contain anything not yet pushed, which is
# exactly the work GitHub cannot give back.
REPOS=(
    "$HOME/Code/homelab"
    "$HOME/Code/factory"
    "$HOME/Code/brain"
    "$HOME/Code/projects/oncla"
    "$HOME/Code/projects/factory"
)

# Paths on the node whose loss would be expensive. Kept explicit rather than
# globbed: a glob that silently matches nothing is how a backup ends up empty
# while reporting success.
NODE_PATHS=(
    /etc/systemd/system/homelab-telegram-bot.service
    /etc/systemd/system/homelab-model-helper@.service
    /etc/systemd/system/homelab-model-helper.socket
    /etc/homelab-telegram-bot
    /etc/homelab-model-helper
    /etc/polkit-1/rules.d/50-homelab-bot.rules
    /var/lib/homelab-model-helper
    /home/aleix/.claude
    /home/aleix/.codex
    # Without these two a restored node has no network and no way for the owner
    # to reach it, which would strand the rebuild at the console. Added after
    # asking how a restore would actually work rather than assuming it would.
    /home/aleix/.ssh
    /etc/netplan
    # Phase 18.1 (ADR-037): boot-class files for the encrypted data volume.
    # Without noauto in both of these, a restored node hangs at a passphrase
    # prompt nobody is there to answer.
    /etc/crypttab
    /etc/fstab
    /etc/systemd/system/homelab-data.target
    /etc/systemd/system/homelab-data-probe.service
    /usr/local/sbin/data-volume.sh
    # Phase 12: the boot-recovery trigger and its script. Without these three
    # a restored node has no way to tell the owner it came back, which is
    # this phase's entire reason for existing. (homelab-notify.sh,
    # homelab-notify@.service and the two onfailure.conf drop-ins are NOT
    # listed here -- the Phase 12 brief §7.5 scopes this backup-list update to
    # exactly these three, and the execution stage report records that as a
    # gap worth the orchestrator's attention rather than one silently
    # widened or silently accepted.)
    /etc/systemd/system/homelab-watchdog.timer
    /etc/systemd/system/homelab-watchdog.service
    /usr/local/sbin/homelab-watchdog.sh
)

# DELIBERATELY NOT BACKED UP, so that these are decisions rather than omissions:
#
#   /var/lib/tailscale  -- the node's tailnet identity. Re-authenticating a
#       rebuilt machine is a two-minute job and is cleaner than restoring the
#       identity of a machine that no longer exists. ADR-019 governs the
#       tailnet; this does not change it.
#
#   /etc/ssh/ssh_host_* -- the host keys. Restoring them makes a rebuilt
#       machine present itself as the old one. Regenerating and accepting the
#       new fingerprint once is the honest behaviour; the warning you would
#       otherwise suppress is the warning that matters.
#
# NOTE: /etc/netplan contains the Wi-Fi passphrase. PROJECT.md and AGENTS.md
# forbid committing it to the repository -- this is an encrypted archive on
# removable media, which is a different thing, but it is why the card must be
# treated as secret material and why the passphrase lives in a password
# manager and never on the card itself.
#
#   /srv/homelab (the data volume's contents) and the LUKS header -- neither
#       is this script's job. This script backs up node *state*; the volume
#       exists precisely to keep its *content* off media this weekly, routine
#       backup would otherwise put it on (ADR-037 Sec7) -- and that content
#       already gets its own backup path, a git remote, which is how the
#       repositories inside it are recovered (Phase 18.2 decides whether that
#       is enough). The LUKS header is a one-time artefact taken by hand
#       straight to the card, age-encrypted (Phase 18.1 step C6), never
#       staged on the node's tmpfs or the Mac's disk the way everything else
#       here is.

# ~/.codex is 366 MB, of which 365 MB reinstalls from the network. Excluding
# those three directories takes it to ~236 KB while keeping auth.json, the
# config, and the sqlite state that holds session history and memories.
#
# An earlier version listed only auth.json, config.toml and installation_id by
# hand. That produced an 80 KB archive and silently dropped the session state,
# which is the kind of omission nobody notices until they need it.
NODE_EXCLUDES=(
    --exclude=/home/aleix/.codex/packages
    --exclude=/home/aleix/.codex/plugins
    --exclude=/home/aleix/.codex/cache
)

fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
step() { printf '\n=== %s\n' "$*"; }

command -v age >/dev/null || fail "age is not installed. Run: brew install age"
[ -d "$DEST" ] || fail "Destination not mounted: ${DEST}"
[ -w "$DEST" ] || fail "Destination is not writable: ${DEST}"

if [ -d "$OUT" ] && [ "$FORCE" -eq 0 ]; then
    fail "${OUT} already exists. Re-run with --force to overwrite today's backup."
fi

# Stage under the Mac's own disk, which is FileVault-protected. Nothing
# unencrypted is ever written to the removable card.
STAGE="$(mktemp -d)"
chmod 700 "$STAGE"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$OUT"

# ---------------------------------------------------------------------------
step "1/5  Node state  --  you will be asked for the node's sudo password"

# THE RULE THIS OBEYS, LEARNED THE HARD WAY TWICE:
#
#   Never redirect the stdout of an `ssh -t` that needs to prompt.
#
# When ssh allocates a pty, it folds the remote command's stdout, its stderr,
# AND anything written to /dev/tty into a single stream and hands it to local
# stdout. Measured, with a real pty:
#
#     ssh -t host 'echo A; echo B >/dev/tty; echo C >&2' > file
#     file now contains A, B, C *and* "Connection to host closed."
#
# The node runs sudo-rs, which writes its password prompt to /dev/tty. So an
# earlier version of this script that streamed `sudo tar -czf -` into a
# redirected file was writing the password prompt into the tarball, where the
# operator could not see it. The run appeared to hang and then die with no
# explanation, twice.
#
# The fix is to give the interactive step nothing to redirect. sudo writes the
# archive to the node's /dev/shm, which is tmpfs -- RAM, not disk -- so no
# second unencrypted copy of any secret ever touches the filesystem this backup
# exists to protect, and nothing survives a reboot. A second connection with no
# pty then fetches the bytes cleanly.
#
# (Two things were also suspected and disproved, recorded so they are not
# re-litigated: the pty does not rewrite newlines in a binary stream -- 200 kB
# of random data with 818 newline bytes returned byte-identical -- and the
# original `2>/dev/null`, while genuinely wrong, was not the whole problem.)

REMOTE_STAGE=/dev/shm/homelab-backup

# No redirection on this call. The prompt must reach the terminal.
ssh -t "$NODE" "
    set -e
    sudo install -d -m 700 -o \$(id -un) -g \$(id -gn) '${REMOTE_STAGE}'
    sudo tar --numeric-owner ${NODE_EXCLUDES[*]} -czf '${REMOTE_STAGE}/node-state.tar.gz' ${NODE_PATHS[*]}
    sudo chown \$(id -un) '${REMOTE_STAGE}/node-state.tar.gz'
    chmod 600 '${REMOTE_STAGE}/node-state.tar.gz'
    echo \"    built \$(du -h '${REMOTE_STAGE}/node-state.tar.gz' | cut -f1) in RAM\"
" || fail "Could not build the archive on the node. Was the sudo password accepted?"

# No -t: nothing to prompt for, and the stream is binary.
ssh "$NODE" "cat '${REMOTE_STAGE}/node-state.tar.gz'" > "${STAGE}/node-state.tar.gz" \
    || fail "Could not retrieve the archive from the node."

ssh "$NODE" "rm -rf '${REMOTE_STAGE}'" \
    || printf '    WARNING: could not remove %s on the node. Remove it by hand.\n' "$REMOTE_STAGE"

[ -s "${STAGE}/node-state.tar.gz" ] || fail "Node tarball is empty. Nothing was captured."

# gzip stores a CRC32 of the uncompressed data, so this catches a truncated or
# polluted transfer before anything gets encrypted and trusted.
gzip -t "${STAGE}/node-state.tar.gz" \
    || fail "The archive failed its gzip integrity check -- the transfer was corrupted."

# gzip stores a CRC32 of the uncompressed data, so this catches a truncated or
# mangled transfer before anything gets encrypted and trusted.
gzip -t "${STAGE}/node-state.tar.gz" \
    || fail "The archive failed its gzip integrity check -- the transfer was corrupted."

# Prove the transfer did not mangle the stream. gzip carries a CRC32 of the
# uncompressed data, so this detects exactly the corruption bug 2 would cause.
gzip -t "${STAGE}/node-state.tar.gz" \
    || fail "The archive failed its gzip integrity check -- the transfer corrupted it."

NODE_ENTRIES="$(tar -tzf "${STAGE}/node-state.tar.gz" | wc -l | tr -d ' ')"
[ "$NODE_ENTRIES" -gt 10 ] || fail "Node tarball has only ${NODE_ENTRIES} entries; expected many more."

# ---------------------------------------------------------------------------
step "2/5  Repository mirrors"

mkdir -p "${STAGE}/repos"
for repo in "${REPOS[@]}"; do
    name="$(basename "$repo")"
    parent="$(basename "$(dirname "$repo")")"
    [ "$parent" = "projects" ] && name="projects-${name}"
    if [ ! -d "${repo}/.git" ]; then
        printf '    SKIP  %s (not a git repository)\n' "$repo"
        continue
    fi
    printf '    mirror  %s\n' "$name"
    git clone --quiet --mirror "$repo" "${STAGE}/repos/${name}.git"
done

MIRROR_COUNT="$(find "${STAGE}/repos" -maxdepth 1 -name '*.git' | wc -l | tr -d ' ')"
[ "$MIRROR_COUNT" -eq "${#REPOS[@]}" ] || \
    fail "Mirrored ${MIRROR_COUNT} repositories but expected ${#REPOS[@]}."

tar -czf "${STAGE}/repos.tar.gz" -C "${STAGE}/repos" .

# ---------------------------------------------------------------------------
step "3/5  Manifest  --  written before encryption, so a restore can be checked"

{
    printf 'Homelab node backup\n'
    printf 'Created:   %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Node:      %s\n' "$NODE"
    printf 'Tool:      age %s\n' "$(age --version)"
    printf '\n'
    printf 'Decrypt:   age -d -o node-state.tar.gz node-state.tar.gz.age\n'
    printf 'Inspect:   tar -tvzf node-state.tar.gz\n'
    printf 'Restore:   sudo tar -xzf node-state.tar.gz --numeric-owner -C /\n'
    printf '\n'
    printf 'The passphrase is NOT here and must never be written to this card.\n'
    printf '\n'
    # %s form, not a bare format string: bash's printf reads a format beginning
    # with "-" as an option and fails.
    printf '%s\n' '--- plaintext checksums (verify these after decrypting) ---'
    shasum -a 256 "${STAGE}/node-state.tar.gz" "${STAGE}/repos.tar.gz" | sed "s|${STAGE}/||"
    printf '\n--- node archive: %s entries ---\n' "$NODE_ENTRIES"
    tar -tvzf "${STAGE}/node-state.tar.gz"
    printf '\n--- repository mirrors ---\n'
    for m in "${STAGE}"/repos/*.git; do
        printf '%-28s %s refs, head %s\n' "$(basename "$m")" \
            "$(git -C "$m" show-ref | wc -l | tr -d ' ')" \
            "$(git -C "$m" rev-parse --short HEAD 2>/dev/null || echo '-')"
    done
} > "${OUT}/MANIFEST.txt"

# ---------------------------------------------------------------------------
step "4/5  Encrypt  --  you will be asked for the age passphrase (twice each)"

age -p -o "${OUT}/node-state.tar.gz.age" "${STAGE}/node-state.tar.gz"
age -p -o "${OUT}/repos.tar.gz.age"      "${STAGE}/repos.tar.gz"

{
    printf '\n--- encrypted artefact checksums ---\n'
    shasum -a 256 "${OUT}"/*.age | sed "s|${OUT}/||"
} >> "${OUT}/MANIFEST.txt"

# ---------------------------------------------------------------------------
step "5/5  Verify what actually landed on the card"

for f in "${OUT}/node-state.tar.gz.age" "${OUT}/repos.tar.gz.age"; do
    [ -s "$f" ] || fail "Missing or empty: $f"
    head -c 22 "$f" | grep -q 'age-encryption.org' \
        || fail "$f does not look like an age file."
    printf '    ok  %-24s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done

sync

printf '\nWritten to: %s\n' "$OUT"
printf '\nThis script has NOT proved the restore. A backup that has only ever\n'
printf 'been written is unvalidated. Run verify-node-backup.sh before trusting it.\n'
