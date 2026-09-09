#!/usr/bin/env bash
#
# Install Docker Engine and the Compose v2 plugin from Docker's own apt
# repository.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/install-docker.sh install
# Phase:   05 (Docker & Compose). See docs/handovers/05-docker.md, ADR-022.
#
# THIS IS A LOCKOUT-CLASS CHANGE. READ THIS BEFORE RUNNING IT.
#
#   Docker creates network interfaces (docker0, plus a veth pair per
#   container), inserts its own packet-filtering chains, sets the FORWARD
#   policy to DROP, and enables IP forwarding. By the definition in
#   docs/standards/safe-changes-headless.md that is lockout-class: it touches
#   the network.
#
#   On this node that matters more than usual. eno1 is down with no carrier,
#   so `ssh homelab` (Tailscale) and `ssh homelab-lan` (LAN) are independent
#   above the link layer and identical below it. Losing the network does not
#   cost one route. It costs both, at once, on a machine with no console.
#
#   Before running this, from the MacBook:
#     bash scripts/macos/preflight.sh          # both routes, two sessions
#     sudo bash /tmp/capture-network-state.sh before
#   And run this inside tmux: both routes share one Wi-Fi adapter, and a
#   dropped link mid-apt can leave dpkg half-configured, which is a worse
#   state than a failed install.
#
# WHY NOT `apt install docker.io`
#
#   Ubuntu's docker.io is older and packages Compose differently from every
#   piece of upstream documentation the reader will encounter. The trade-off
#   is one more third-party repository, added the same way Tailscale's was
#   (ADR-014): explicitly, pinned with signed-by, and verified before use --
#   never a script piped into a root shell.
#
# WHAT THIS SCRIPT DOES NOT DO
#
#   - It does not add anyone to the `docker` group. That group is equivalent
#     to root (it can mount the host filesystem), so joining it is a separate,
#     deliberate decision recorded in ADR-022 -- not a side effect of install.
#   - It does not start any container.
#   - It does not configure a firewall. Phase 13 owns that, and it inherits
#     the fact that published ports bypass filter/INPUT entirely.

set -euo pipefail

KEYRING="/etc/apt/keyrings/docker.asc"
LIST="/etc/apt/sources.list.d/docker.list"
BASE="https://download.docker.com/linux/ubuntu"
DAEMON_JSON="/etc/docker/daemon.json"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
ok()  { printf '  ok   %s\n' "$*"; }
note(){ printf '  --   %s\n' "$*"; }

[ "${1:-}" = "install" ] || {
  printf 'usage: sudo bash %s install\n' "$0" >&2
  printf '\nThe explicit argument is deliberate. This change rewrites the\n' >&2
  printf 'packet-filtering rules on a machine with no console.\n' >&2
  exit 2
}

printf '\n=== Home Lab: install Docker Engine + Compose v2 ===\n\n'

[ "$(id -u)" -eq 0 ] || die "must run as root (use: sudo bash $0 install)"
ok "running as root"

# --- Refuse to run without a way back -------------------------------------
#
# preflight.sh is the real check and it runs on the Mac, because only a
# machine outside can prove a NEW connection arrives. This is the weaker,
# local half: it will not catch a broken route, but it will catch the most
# common omission, which is having no second session at all.
#
# Counted with `w`, never `who`: systemd 257 removed utmp support and Ubuntu
# 26.04 ships 259, so /run/utmp does not exist and `who` prints nothing while
# exiting 0. A silent wrong answer here would be aimed at the one check that
# matters most.
SESSIONS="$(w -h 2>/dev/null | awk '$2 ~ /^pts\//' | wc -l | tr -d ' ')"
WLINES="$(w -h 2>/dev/null | wc -l | tr -d ' ')"
if [ "${WLINES:-0}" -eq 0 ]; then
  note "cannot determine session count -- check manually with: w"
elif [ "${SESSIONS:-0}" -lt 2 ]; then
  die "only ${SESSIONS} interactive session(s). Open a second and leave it idle.
This is a lockout-class change on a node with no console (ADR-020)."
else
  ok "${SESSIONS} interactive sessions -- one can stay idle as the way back"
fi

if [ -z "${TMUX:-}" ]; then
  note "not running inside tmux -- a dropped link mid-apt can leave dpkg"
  note "half-configured. Strongly consider: tmux new -s docker"
fi

# --- Which Ubuntu release is this, really? --------------------------------

# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${VERSION_CODENAME:-}"
[ -n "$CODENAME" ] || die "cannot determine VERSION_CODENAME from /etc/os-release"
ok "running $PRETTY_NAME (codename: $CODENAME)"

# --- Does Docker actually publish for it? ---------------------------------
#
# Verified before anything is written to /etc. If Docker does not publish for
# this codename, ADR-014 requires that be recorded as a problem with a
# decision attached -- never a silent fallback to an older suite.

REL="/tmp/docker-release.$$"
trap 'rm -f "$REL"' EXIT
HTTP="$(curl -fsS -o "$REL" -w '%{http_code}' -m 30 "$BASE/dists/$CODENAME/Release" || true)"
[ "$HTTP" = "200" ] || die "Docker does not appear to publish for '$CODENAME'.
  $BASE/dists/$CODENAME/Release returned HTTP $HTTP
Do not work around this silently. Record it in the build log and decide
deliberately between waiting, using Ubuntu's docker.io, or pinning another
release's repository (ADR-014)."

grep -q "^Origin: Docker$" "$REL" \
  || die "repository does not declare 'Origin: Docker'. Refusing to continue."
grep -qE "^(Suite|Codename): $CODENAME$" "$REL" \
  || die "repository does not declare Suite/Codename '$CODENAME'. Refusing."
ok "repository publishes for $CODENAME (Origin: Docker)"

ARCH="$(dpkg --print-architecture)"
grep -qE "^Architectures:.*\b$ARCH\b" "$REL" \
  || die "repository does not list architecture '$ARCH'"
ok "architecture $ARCH is published"

grep -qE "^Components:.*\bstable\b" "$REL" \
  || die "repository does not publish a 'stable' component"
ok "stable component present"

# --- Signing key ----------------------------------------------------------

install -m 0755 -d /etc/apt/keyrings
if [ ! -s "$KEYRING" ]; then
  curl -fsSL -m 30 "$BASE/gpg" -o "$KEYRING" || die "could not download Docker's signing key"
  chmod a+r "$KEYRING"
  ok "signing key written to $KEYRING"
else
  ok "signing key already present"
fi
grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$KEYRING" \
  || die "$KEYRING does not look like a PGP public key"

# --- Repository -----------------------------------------------------------
#
# signed-by is the security control: it binds this repository to that one key,
# so a compromise elsewhere in apt's trust store cannot serve Docker packages.

printf 'deb [arch=%s signed-by=%s] %s %s stable\n' \
  "$ARCH" "$KEYRING" "$BASE" "$CODENAME" > "$LIST"
ok "repository written to $LIST"

apt-get update -qq
ok "apt index updated"

apt-cache policy docker-ce | sed 's/^/       /'

# --- daemon.json BEFORE first start ---------------------------------------
#
# Written before the package starts the daemon, so log rotation applies from
# the very first container rather than from a later restart.
#
# The default json-file driver writes container logs with NO size limit. One
# chatty container can fill the root filesystem, and this volume group has no
# free extents -- so the usual remedy, growing the volume, is unavailable.
# That is a concrete need, which is why this is the only thing configured here.

if [ ! -f "$DAEMON_JSON" ]; then
  install -m 0755 -d /etc/docker
  cat > "$DAEMON_JSON" <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
  chmod 0644 "$DAEMON_JSON"
  ok "wrote $DAEMON_JSON (log rotation: 3 x 10m per container)"
else
  note "$DAEMON_JSON already exists -- left untouched"
fi

# --- Install --------------------------------------------------------------

DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

ok "packages installed"

# --- Report, from the running system, not from the files we wrote ---------

printf '\n=== versions ===\n'
docker --version        || note "docker --version failed"
docker compose version  || note "docker compose version failed"
containerd --version    || note "containerd --version failed"

printf '\n=== daemon state ===\n'
systemctl is-enabled docker.service 2>&1 | sed 's/^/  enabled: /'
systemctl is-active  docker.service 2>&1 | sed 's/^/  active:  /'

printf '\n=== is daemon.json actually in effect? ===\n'
docker info --format 'logging driver: {{.LoggingDriver}}' 2>&1 | sed 's/^/  /'

printf '\n=== what Docker did to the network ===\n'
ip -br link | grep -E 'docker|br-' | sed 's/[0-9a-fA-F:]\{17\}/<mac>/' | sed 's/^/  /' || echo "  (no docker interfaces yet)"
sysctl net.ipv4.ip_forward | sed 's/^/  /'

cat <<'NEXT'

=== NEXT, in this order ===

  1. From the MacBook, open a THIRD fresh connection on BOTH routes.
     An established session proves nothing about new ones.

  2. sudo bash /tmp/capture-network-state.sh after
     diff /tmp/netstate-before.txt /tmp/netstate-after.txt

     Expected differences ONLY: a docker0 interface, Docker's own chains,
     FORWARD policy DROP, ip_forward=1. Anything else is a finding.

  3. Do NOT publish a container port without an explicit interface.
     -p 127.0.0.1:8080:80   yes
     -p 8080:80             NO -- that is 0.0.0.0, and it bypasses the
                            host firewall's INPUT chain entirely.
NEXT
