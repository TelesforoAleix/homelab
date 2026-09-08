#!/usr/bin/env bash
#
# Write a verified Ubuntu ISO to a USB stick on macOS.
#
# Run on: the MacBook (Phase 01, Part C)
#
# *** THIS SCRIPT DESTROYS EVERYTHING ON THE TARGET DISK. ***
#
# Why the guards below exist
# --------------------------
# The classic, unrecoverable homelab mistake is typing the wrong disk number
# into dd and overwriting your own laptop's drive. There is no undo. This
# script therefore refuses to proceed unless the target is a real, external,
# physical disk, and it makes you type the identifier back before it runs.
#
# Deliberate design choices:
#   - no default target. You must name the disk explicitly.
#   - a hard refusal (not a warning) if the disk reports as internal.
#   - the confirmation requires retyping the disk identifier, so muscle-memory
#     "y<enter>" cannot destroy anything.

set -euo pipefail

say()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: $0 <path-to-iso> <disk-identifier>

  <path-to-iso>      e.g. ~/Downloads/ubuntu-26.04.1-live-server-amd64.iso
  <disk-identifier>  e.g. disk4   (NOT /dev/disk4, NOT disk4s1)

Find the identifier by running this BEFORE and AFTER plugging the stick in,
and looking for the line that appeared:

    diskutil list external physical

USAGE
  exit 64
}

[ $# -eq 2 ] || usage
ISO_PATH="$1"
DISK_ID="$2"

[ "$(uname -s)" = "Darwin" ] || fail "This script is macOS-specific (it uses diskutil)."
[ -f "$ISO_PATH" ]           || fail "ISO not found: ${ISO_PATH}"

# Reject /dev/disk4, disk4s1, sda, etc. We want exactly 'diskN'.
if ! [[ "$DISK_ID" =~ ^disk[0-9]+$ ]]; then
  fail "Target must look like 'disk4' — got '${DISK_ID}'.
A trailing 's1' is a *partition*; writing there produces an unbootable stick."
fi

DEV_NODE="/dev/${DISK_ID}"
RAW_NODE="/dev/r${DISK_ID}"   # 'raw' device: much faster for a full-disk write

diskutil info "$DISK_ID" >/dev/null 2>&1 || fail "No such disk: ${DISK_ID}"

info() { diskutil info "$DISK_ID" | awk -F': +' -v k="$1" '$1 ~ k {print $2; exit}'; }

IS_INTERNAL="$(info 'Device Location')"
IS_REMOVABLE="$(info 'Removable Media')"
DISK_SIZE="$(info 'Disk Size')"
DISK_NAME="$(info 'Device / Media Name')"

# --- The guard that matters --------------------------------------------------
if [ "$IS_INTERNAL" = "Internal" ]; then
  fail "REFUSING: ${DISK_ID} reports as an INTERNAL disk (${DISK_NAME}).
This is almost certainly your Mac's own drive. Re-check with:
    diskutil list external physical"
fi

say "Target disk"
cat <<SUMMARY
    identifier : ${DISK_ID}
    name       : ${DISK_NAME}
    size       : ${DISK_SIZE}
    location   : ${IS_INTERNAL}
    removable  : ${IS_REMOVABLE}

    source ISO : ${ISO_PATH}

Everything currently on ${DISK_ID} will be destroyed and cannot be recovered.
SUMMARY

printf '\nType the disk identifier (%s) to confirm, or anything else to abort: ' "$DISK_ID"
read -r CONFIRM
[ "$CONFIRM" = "$DISK_ID" ] || { echo "Aborted. Nothing was written."; exit 1; }

# Unmount the volumes but keep the device claimed, so dd can write to it.
say "Unmounting ${DISK_ID}"
diskutil unmountDisk "$DEV_NODE"

say "Writing image — this takes several minutes and prints nothing while it works"
echo "    (press Ctrl-T at any time to see progress; macOS dd has no status=progress)"
# bs=4m is a large block size, which BSD dd needs to write at full speed.
sudo dd if="$ISO_PATH" of="$RAW_NODE" bs=4m

say "Flushing and ejecting"
sync
diskutil eject "$DEV_NODE"

say "Done — USB stick is ready"
echo "    macOS may warn that the disk is unreadable. That is expected: it cannot"
echo "    read the Linux filesystem on the stick. The stick is fine."
