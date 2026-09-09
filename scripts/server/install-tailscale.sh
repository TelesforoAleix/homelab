#!/usr/bin/env bash
#
# Install Tailscale on the Home Lab server from Tailscale's own apt repository.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/install-tailscale.sh
# Phase:   03 (Remote Access). See docs/handovers/03-remote-access.md, ADR-019.
#
# Why not the one-line installer
# ------------------------------
# Tailscale publishes an install.sh that pipes a remote script into a root
# shell. It works, but it hides which repository was configured and which key
# was trusted — and this project has to be able to say what is installed and
# why (PROJECT.md §6). Adding the repository explicitly is four steps, all
# inspectable, and it leaves apt in charge of upgrades.
#
# Why not Tailscale's Ubuntu documentation
# ----------------------------------------
# Because it is wrong for this release, and ADR-014 says so explicitly. As of
# 2026-09-09 Tailscale's Linux docs still reference Noble 24.04, and the URL
# tailscale.com/kb/1187/install-ubuntu-2604 returns HTTP 200 while serving a
# generic docs index rather than a 26.04 page. Vendor documentation lags vendor
# packages. The package repository is the authoritative source:
#
#   https://pkgs.tailscale.com/stable/ubuntu/dists/resolute/Release
#   -> Origin: Tailscale, Codename: resolute, amd64 present (checked 2026-09-09)
#
# This script therefore derives the codename from the running system and fails
# loudly if the repository does not publish for it, rather than silently
# pinning some other release.

set -euo pipefail

KEYRING="/usr/share/keyrings/tailscale-archive-keyring.gpg"
LIST="/etc/apt/sources.list.d/tailscale.list"
BASE="https://pkgs.tailscale.com/stable/ubuntu"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
ok()  { printf '  ok   %s\n' "$*"; }

printf '\n=== Home Lab: install Tailscale ===\n\n'

[ "$(id -u)" -eq 0 ] || die "must run as root (use: sudo bash $0)"
ok "running as root"

# --- Which Ubuntu release is this, really? --------------------------------

# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${VERSION_CODENAME:-}"
[ -n "$CODENAME" ] || die "cannot determine VERSION_CODENAME from /etc/os-release"
ok "running $PRETTY_NAME (codename: $CODENAME)"

# --- Does Tailscale actually publish for it? ------------------------------
#
# Checked before writing anything to /etc. If this fails, ADR-014 requires it be
# recorded as a problem in the build log, not worked around by quietly pinning
# a different release's repository.

REL_URL="$BASE/dists/$CODENAME/Release"
HTTP="$(curl -s -o /tmp/ts-release -w '%{http_code}' -m 30 "$REL_URL" || true)"
[ "$HTTP" = "200" ] || die "Tailscale does not appear to publish for '$CODENAME'.
  $REL_URL returned HTTP $HTTP
Do not work around this silently. Record it in the build log and decide
deliberately between the upstream generic installer and pinning another
release's repository (ADR-014)."

grep -q "^Codename: $CODENAME$" /tmp/ts-release \
  || die "$REL_URL does not declare 'Codename: $CODENAME'. Refusing to continue."
grep -q "^Origin: Tailscale$" /tmp/ts-release \
  || die "$REL_URL does not declare 'Origin: Tailscale'. Refusing to continue."
ok "repository publishes for $CODENAME (Origin: Tailscale)"

ARCH="$(dpkg --print-architecture)"
grep -q "^Architectures:.*\b$ARCH\b" /tmp/ts-release \
  || die "repository does not list architecture '$ARCH'"
ok "architecture $ARCH is published"

# --- Signing key ----------------------------------------------------------
#
# .noarmor.gpg is the binary (dearmored) form, which is what signed-by= wants.
# Fetched to a temp file and checked before being installed, so a truncated or
# HTML error page never lands in /usr/share/keyrings.

curl -fsSL -m 30 "$BASE/$CODENAME.noarmor.gpg" -o /tmp/ts-keyring.gpg \
  || die "failed to download the signing key"

file /tmp/ts-keyring.gpg | grep -qi "PGP\|GPG\|OpenPGP\|public key" \
  || die "downloaded keyring is not a GPG keyring:
  $(file /tmp/ts-keyring.gpg)"

install -o root -g root -m 0644 /tmp/ts-keyring.gpg "$KEYRING"
ok "signing key installed at $KEYRING"

# --- Repository -----------------------------------------------------------

curl -fsSL -m 30 "$BASE/$CODENAME.tailscale-keyring.list" -o /tmp/ts.list \
  || die "failed to download the source list"

grep -q "signed-by=$KEYRING" /tmp/ts.list \
  || die "source list does not pin signed-by=$KEYRING. Refusing to install it."
ok "source list pins the key we just installed (signed-by=)"

install -o root -g root -m 0644 /tmp/ts.list "$LIST"
ok "repository configured at $LIST"
printf '\n  %s\n\n' "$(grep '^deb' "$LIST")"

# --- Install --------------------------------------------------------------

printf 'Updating package lists...\n'
apt-get update -qq
ok "apt-get update completed"

printf 'Installing tailscale...\n'
DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale
ok "tailscale installed"

systemctl enable --now tailscaled
ok "tailscaled enabled and started"

rm -f /tmp/ts-release /tmp/ts-keyring.gpg /tmp/ts.list

# --- Report ---------------------------------------------------------------

printf '\nVersions:\n\n'
printf '  tailscale  %s\n' "$(tailscale version | head -1)"
printf '  package    %s\n' "$(dpkg-query -W -f='${Version}' tailscale)"
printf '  tailscaled active=%s enabled=%s\n' \
  "$(systemctl is-active tailscaled)" "$(systemctl is-enabled tailscaled)"

printf '\nInstalled, but NOT yet joined to a tailnet.\n\n'
printf 'Next, run this yourself and open the URL it prints:\n\n'
printf '    sudo tailscale up\n\n'
printf 'It will ask you to authenticate in a browser. Sign in with the account\n'
printf 'recorded in ADR-019 — that identity becomes the root of trust for the\n'
printf 'whole tailnet and changing it later means rebuilding it.\n\n'
printf 'Tailscale SSH is deliberately NOT enabled (no --ssh flag): OpenSSH with\n'
printf 'keys stays the authentication mechanism. See ADR-019.\n\n'
