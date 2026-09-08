#!/usr/bin/env bash
#
# Download and verify the Ubuntu Server installation image used by the Home Lab
# reference build.
#
# Run on: the MacBook (Phase 01, Part B)
# Reads:  nothing sensitive. Writes: one .iso file into ISO_DIR.
#
# Why this script exists
# ----------------------
# Downloading an operating system image is the one step where a corrupted or
# tampered file silently becomes the foundation of everything built afterwards.
# Verifying the checksum is therefore not ceremony: it is the only cheap moment
# to catch a truncated download or a hostile mirror.
#
# Two different checks happen below, and they prove different things:
#
#   1. The file matches the SHA256 recorded in this repository (ADR-014).
#      -> proves the file is the same one the project was documented against.
#   2. That recorded SHA256 still matches the live SHA256SUMS published by
#      Ubuntu.
#      -> catches the case where this repository's pinned value has gone stale.
#
# Neither check proves *authenticity* on its own, because an attacker who can
# serve you a bad ISO could also serve a matching SHA256SUMS. Real authenticity
# requires verifying SHA256SUMS.gpg against Canonical's signing key; the guide
# in guide/01-ubuntu-server/ shows how to do that.

set -euo pipefail

# --- What we are downloading (see ADR-014) ----------------------------------
ISO_RELEASE="26.04"
ISO_VERSION="26.04.1"
ISO_NAME="ubuntu-${ISO_VERSION}-live-server-amd64.iso"
ISO_SHA256="cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927"

BASE_URL="https://releases.ubuntu.com/${ISO_RELEASE}"
ISO_URL="${BASE_URL}/${ISO_NAME}"
SUMS_URL="${BASE_URL}/SHA256SUMS"

# Where to put it. Override with: ISO_DIR=/some/path ./download-ubuntu-iso.sh
ISO_DIR="${ISO_DIR:-$HOME/Downloads}"
ISO_PATH="${ISO_DIR}/${ISO_NAME}"

say()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

mkdir -p "$ISO_DIR"

# --- Step 1: cross-check our pinned checksum against upstream ---------------
say "Cross-checking the pinned checksum against ${SUMS_URL}"
upstream_line="$(curl -fsSL "$SUMS_URL" | grep -F "$ISO_NAME" || true)"
[ -n "$upstream_line" ] || fail "Ubuntu no longer publishes ${ISO_NAME}. ADR-014 needs revisiting."

upstream_sha="${upstream_line%% *}"
if [ "$upstream_sha" != "$ISO_SHA256" ]; then
  fail "Pinned checksum does not match upstream.
  pinned:   ${ISO_SHA256}
  upstream: ${upstream_sha}
This is a documentation problem, not a download problem. Update ADR-014 and
this script together, and record why in the build log."
fi
echo "    pinned checksum matches upstream."

# --- Step 2: download (resumable) -------------------------------------------
if [ -f "$ISO_PATH" ]; then
  say "Image already present at ${ISO_PATH} — skipping download, verifying only"
else
  say "Downloading ${ISO_NAME} (about 2.7 GB) to ${ISO_DIR}"
  # -C - resumes a partial download instead of restarting from zero.
  curl -fL -C - -o "$ISO_PATH" "$ISO_URL"
fi

# --- Step 3: verify what is actually on disk --------------------------------
say "Verifying SHA256 of the downloaded file (this reads the whole 2.7 GB)"
actual_sha="$(shasum -a 256 "$ISO_PATH" | awk '{print $1}')"

if [ "$actual_sha" != "$ISO_SHA256" ]; then
  fail "Checksum MISMATCH — do not use this file.
  expected: ${ISO_SHA256}
  actual:   ${actual_sha}
Delete it and download again:  rm '${ISO_PATH}'"
fi

say "OK — verified image ready"
echo "    ${ISO_PATH}"
echo
echo "Next: write it to a USB stick with"
echo "    scripts/macos/write-ubuntu-usb.sh '${ISO_PATH}' diskN"
