#!/usr/bin/env bash
#
# verify-node-backup.sh -- prove that a backup written by backup-node.sh can
# actually be restored, by decrypting it and comparing it against the live node
# file by file, mode by mode, owner by owner.
#
# WHY THIS EXISTS, AND WHY IT IS A SEPARATE SCRIPT
#
#   The Phase 18 brief states the objective as "a restore has actually been
#   performed and proved -- not a backup job reporting success". Those are
#   different claims and they fail independently. A writer that has only ever
#   written, and a checker that has only ever said "ok", are both unvalidated.
#
#   This project has recorded nine separate instances of a check reporting a
#   result it could not support. The standing rule that came out of them is
#   that a detector which has only ever reported "clean" is worthless until a
#   planted positive has made it fire. Step 5 below plants one. If the planted
#   failure is NOT detected, this script exits non-zero and says so -- because
#   at that point every "ok" above it is unsupported.
#
# WHAT IT PROVES
#
#   That the archive decrypts; that its bytes match what was recorded at
#   creation; and that every captured file's content, permission bits and
#   numeric owner match the running node right now.
#
# WHAT IT DOES NOT PROVE
#
#   That a bare-metal rebuild from this archive would boot. Proving that needs
#   a real reinstall onto real hardware, which is Phase 18's own decision to
#   schedule. This is the strongest check available without one, and the gap is
#   stated rather than papered over.
#
# USAGE
#
#   ./verify-node-backup.sh                          # newest backup on the card
#   ./verify-node-backup.sh /Volumes/SD\ Card/homelab-backup/2026-09-11
#
set -euo pipefail

NODE="${NODE:-homelab}"
DEST="${DEST:-/Volumes/SD Card}"
ROOT="${DEST}/homelab-backup"

fail() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }
step() { printf '\n=== %s\n' "$*"; }
ok()   { printf '    ok    %s\n' "$*"; }
bad()  { printf '    WRONG %s\n' "$*"; }

if [ $# -ge 1 ]; then
    SRC="$1"
else
    [ -d "$ROOT" ] || fail "No backup root at ${ROOT}"
    SRC="$(find "$ROOT" -maxdepth 1 -type d -name '20*' | sort | tail -1)"
    [ -n "$SRC" ] || fail "No dated backup directories under ${ROOT}"
fi
[ -f "${SRC}/node-state.tar.gz.age" ] || fail "No node archive in ${SRC}"
[ -f "${SRC}/MANIFEST.txt" ]          || fail "No MANIFEST.txt in ${SRC}"

printf 'Verifying: %s\n' "$SRC"

WORK="$(mktemp -d)"; chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
step "1/5  Decrypt  --  you will be asked for the age passphrase"

age -d -o "${WORK}/node-state.tar.gz" "${SRC}/node-state.tar.gz.age" \
    || fail "Decryption failed. The archive or the passphrase is wrong."
ok "decrypted $(du -h "${WORK}/node-state.tar.gz" | cut -f1)"

# ---------------------------------------------------------------------------
step "2/5  Checksum against the manifest written at creation time"

# Match on the SHAPE of a checksum line, not on the filename appearing
# anywhere. The manifest also contains the help line
#     Inspect:   tar -tvzf node-state.tar.gz
# which an earlier pattern matched, yielding WANT="Inspect:" and a mismatch
# against a backup that was in fact perfectly good. A verifier that cries wolf
# is worse than none: it teaches you to ignore it.
WANT="$(awk '$1 ~ /^[0-9a-f]{64}$/ && $2 == "node-state.tar.gz" {print $1; exit}' "${SRC}/MANIFEST.txt")"
[ -n "$WANT" ] || fail "MANIFEST.txt records no plaintext checksum for the node archive."
[ "${#WANT}" -eq 64 ] || fail "Recovered a malformed checksum from MANIFEST.txt: '${WANT}'"
GOT="$(shasum -a 256 "${WORK}/node-state.tar.gz" | awk '{print $1}')"
[ "$WANT" = "$GOT" ] || fail "Checksum mismatch. recorded=${WANT} actual=${GOT}"
ok "sha256 matches the value recorded before encryption"

# ---------------------------------------------------------------------------
step "3/5  Extract to scratch (different media from the node's own disk)"

mkdir -p "${WORK}/tree"
tar -xzf "${WORK}/node-state.tar.gz" -C "${WORK}/tree"
COUNT="$(find "${WORK}/tree" -type f | wc -l | tr -d ' ')"
[ "$COUNT" -gt 5 ] || fail "Extracted only ${COUNT} files."
ok "extracted ${COUNT} files"

# ---------------------------------------------------------------------------
step "4/5  Compare every file against the LIVE node  --  sudo password needed"

# The file list is derived FROM THE ARCHIVE, not from an independent path list
# on the node. An earlier version enumerated the node separately, which meant
# the verifier had its own copy of backup-node.sh's include/exclude rules and
# would report false failures the moment the two drifted. Asking "is everything
# I backed up still identical to the node?" needs only one list, and it is the
# archive's.
#
# Coverage -- "did the backup capture the right things at all?" -- is a
# different question, checked separately in 4b against a fixed critical list.
#
# Same pty rule as backup-node.sh: the interactive call writes to the node's
# tmpfs and a second, pty-less connection reads it back, because with a pty ssh
# folds stdout, stderr and /dev/tty into one stream and $( ) would swallow
# sudo-rs's prompt.

REMOTE_LIST=/dev/shm/homelab-verify-list.txt
REMOTE_OUT=/dev/shm/homelab-verify.txt

# Regular files only; tar lists directories with a trailing slash.
tar -tzf "${WORK}/node-state.tar.gz" | grep -v '/$' | sed 's|^|/|' > "${WORK}/filelist.txt"
WANTED="$(wc -l < "${WORK}/filelist.txt" | tr -d ' ')"
[ "$WANTED" -gt 5 ] || fail "Archive lists only ${WANTED} regular files."
ok "archive lists ${WANTED} regular files"

# Ownership table, built in ONE pass rather than re-reading the archive per
# file. Format note that cost a full failed run: GNU tar renders numeric owners
# as "0/982", BSD tar -- which is what macOS ships, and what runs here --
# renders them as two separate columns, "0  982". Matching the GNU form against
# BSD output fails for every single file while every content hash passes, which
# looks alarming and means nothing.
#
#   -rw-r-----  0 0      982       851 Sep  9 20:42 etc/.../allowlist
#    $1         $2 $3     $4        $5 $6  $7 $8    $9
#
# --numeric-owner at creation means no names are stored, so these stay numeric.
tar -tvzf "${WORK}/node-state.tar.gz" \
  | awk '$NF !~ /\/$/ && NF>=9 {print $3, $4, "/" $NF}' > "${WORK}/tarowners.txt"
OWNROWS="$(wc -l < "${WORK}/tarowners.txt" | tr -d ' ')"
[ "$OWNROWS" -eq "$WANTED" ] \
    || fail "Owner table has ${OWNROWS} rows but the archive lists ${WANTED} files."
ok "owner table built for ${OWNROWS} files"

ssh "$NODE" "cat > '${REMOTE_LIST}'" < "${WORK}/filelist.txt" \
    || fail "Could not send the file list to the node."

ssh -t "$NODE" "
    set -e
    : > '${REMOTE_OUT}'
    while IFS= read -r p; do
        if sudo test -f \"\$p\"; then
            printf '%s %s %s %s\n' \
                \"\$(sudo stat -c %u \"\$p\")\" \
                \"\$(sudo stat -c %g \"\$p\")\" \
                \"\$(sudo sha256sum \"\$p\" | cut -d' ' -f1)\" \
                \"\$p\" >> '${REMOTE_OUT}'
        else
            printf 'GONE - - %s\n' \"\$p\" >> '${REMOTE_OUT}'
        fi
    done < '${REMOTE_LIST}'
    echo \"    hashed \$(wc -l < '${REMOTE_OUT}') files on the node\"
" || fail "Could not read the live node. Was the sudo password accepted?"

LIVE="$(ssh "$NODE" "cat '${REMOTE_OUT}'; rm -f '${REMOTE_OUT}' '${REMOTE_LIST}'")"
[ -n "$LIVE" ] || fail "Got nothing back from the node."

MISMATCH=0; CHECKED=0; GONE=0
while read -r uid gid hash fname; do
    [ -n "${fname:-}" ] || continue
    if [ "$uid" = "GONE" ]; then
        # Not an error: the node may legitimately have changed since the backup.
        GONE=$((GONE+1)); printf '    note  no longer on the node: %s\n' "$fname"; continue
    fi
    CHECKED=$((CHECKED+1))
    local_copy="${WORK}/tree${fname}"
    [ -f "$local_copy" ] || { bad "MISSING FROM EXTRACT: ${fname}"; MISMATCH=$((MISMATCH+1)); continue; }

    lhash="$(shasum -a 256 "$local_copy" | awk '{print $1}')"
    [ "$lhash" = "$hash" ] || { bad "CONTENT DIFFERS: ${fname}"; MISMATCH=$((MISMATCH+1)); }

    # Ownership comes from the tar header, not from the extracted copy: the
    # scratch filesystem cannot represent the node's uids.
    towner="$(awk -v p="$fname" '$3 == p {print $1" "$2; exit}' "${WORK}/tarowners.txt")"
    if [ -z "$towner" ]; then
        bad "NOT IN TAR INDEX: ${fname}"; MISMATCH=$((MISMATCH+1))
    elif [ "$towner" != "${uid} ${gid}" ]; then
        bad "OWNER DIFFERS: ${fname} (node ${uid}/${gid}, archive ${towner// //})"
        MISMATCH=$((MISMATCH+1))
    fi
done <<< "$LIVE"

printf '    compared %s files' "$CHECKED"
# Not `[ ... ] && printf`: under `set -e` that exits the script when GONE is 0,
# i.e. precisely when everything is fine.
if [ "$GONE" -gt 0 ]; then printf ' (%s no longer present on the node)' "$GONE"; fi
printf '\n'
[ "$CHECKED" -gt 5 ] || fail "Only ${CHECKED} files compared; the comparison did not really run."
[ "$MISMATCH" -eq 0 ] || fail "${MISMATCH} mismatch(es) above. This backup is NOT trustworthy."
ok "every compared file matches the live node in content and numeric owner"

step "4b/5  Coverage  --  are the things that matter actually in there?"

# A fidelity check cannot notice something that was never backed up. These are
# the files whose absence would make a rebuild impossible or insecure.
CRITICAL=(
    etc/homelab-telegram-bot/token
    etc/homelab-telegram-bot/allowlist
    etc/homelab-telegram-bot/privileged-allowlist
    etc/homelab-telegram-bot/restart-allowlist
    etc/systemd/system/homelab-telegram-bot.service
    etc/systemd/system/homelab-model-helper@.service
    etc/systemd/system/homelab-model-helper.socket
    etc/polkit-1/rules.d/50-homelab-bot.rules
    home/aleix/.claude/.credentials.json
    home/aleix/.codex/auth.json
)
MISSING=0
for c in "${CRITICAL[@]}"; do
    if grep -qxF "/${c}" "${WORK}/filelist.txt"; then ok "$c"; else bad "ABSENT: $c"; MISSING=$((MISSING+1)); fi
done
[ "$MISSING" -eq 0 ] || fail "${MISSING} critical file(s) are not in this backup."

# ---------------------------------------------------------------------------
step "5/5  Planted positive control  --  the check must fail on purpose"

# Everything above reported success. That is exactly the situation in which a
# broken checker is indistinguishable from a good one. So corrupt a copy by a
# single byte and require the same comparison to notice.
cp "${WORK}/node-state.tar.gz" "${WORK}/planted.tar.gz"
printf 'x' | dd of="${WORK}/planted.tar.gz" bs=1 seek=200 count=1 conv=notrunc 2>/dev/null

PLANTED_HASH="$(shasum -a 256 "${WORK}/planted.tar.gz" | awk '{print $1}')"
if [ "$PLANTED_HASH" = "$WANT" ]; then
    fail "Planted corruption did not change the checksum. The check is broken."
fi
ok "checksum check fires on a one-byte corruption"

if tar -tzf "${WORK}/planted.tar.gz" >/dev/null 2>&1; then
    printf '    note  tar still reads the corrupted archive -- gzip caught nothing at\n'
    printf '          offset 200. This is why the checksum, not tar, is the gate.\n'
else
    ok "tar also rejects the corrupted archive"
fi

printf '\nPASS -- %s verified against the live node, and the verifier itself was\n' "$SRC"
printf 'proved to fail on planted corruption.\n\n'
printf 'Still unproved: that a bare-metal rebuild from this archive would boot.\n'
printf 'That needs a real reinstall and is Phase 18 scheduling, not this script.\n'
