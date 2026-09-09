#!/usr/bin/env bash
#
# capture-network-state.sh -- snapshot the host's network and packet-filter
# state, before and after a lockout-class change.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/capture-network-state.sh before
#          sudo bash /tmp/capture-network-state.sh after
#          diff /tmp/netstate-before.txt /tmp/netstate-after.txt
#
# WHY THIS EXISTS
#
#   docs/standards/safe-changes-headless.md (ADR-020) says to verify the
#   running system rather than the file you wrote. For a change that rewrites
#   packet-filtering rules -- installing Docker is the first one this project
#   makes -- "verify" means being able to say exactly what changed. You cannot
#   diff against a memory.
#
#   Docker legitimately adds a docker0 bridge, its own iptables chains, and
#   sets the FORWARD policy to DROP. Those differences are expected. Anything
#   else in the diff is a finding, and without a "before" you cannot tell the
#   two apart.
#
# SAFE TO PASTE
#
#   Output is written so it can go straight into the repository:
#     - MAC addresses are replaced with <mac>. The owner's standing rule is
#       that MAC addresses are never committed, and `ip link` prints two.
#     - The tailnet name is replaced with <tailnet>. The address is not
#       sensitive; the account-linked name is (Phase 04 audit).
#   Everything else -- RFC1918 and CGNAT addresses -- was adjudicated
#   publishable by the Phase 04 audit and is left intact.
#
# WHAT IT DOES NOT DO
#
#   It does not judge whether a difference is safe. It gives you a diff. The
#   judgement is yours, and it is the actual control.

set -uo pipefail        # not -e: a missing optional tool must be reported,
                        # not abort the capture half-written.

LABEL="${1:-}"
case "$LABEL" in
  before|after) ;;
  *) echo "usage: sudo bash $0 before|after" >&2; exit 2 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)" >&2; exit 2; }

OUT="/tmp/netstate-${LABEL}.txt"

# Redaction. Applied to everything before it reaches the file, never after --
# a file that is briefly correct-but-unsafe on disk is still a leak.
#
# Both well-known constant MACs (all-zero loopback, all-ones broadcast) are
# not secrets, but they are also not interesting, so they are redacted along
# with the rest rather than special-cased. Simpler is easier to trust.
redact() {
  sed -E \
    -e 's/\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b/<mac>/g' \
    -e 's/\b[a-zA-Z0-9][a-zA-Z0-9-]*\.ts\.net\b/<tailnet>.ts.net/g'
}

section() { printf '\n===== %s =====\n' "$1" >> "$OUT"; }
run()     { section "$1"; shift; { "$@" 2>&1 || echo "(command failed: $*)"; } | redact >> "$OUT"; }

{
  echo "network state capture: $LABEL"
  echo "host: $(hostname)"
  echo "date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "kernel: $(uname -r)"
} > "$OUT"

run "ip -br link"              ip -br link
run "ip -br addr"              ip -br addr
run "ip route"                 ip route
run "ip -6 route"              ip -6 route
run "listening sockets"        ss -tlnp
run "sysctl ip_forward"        sysctl net.ipv4.ip_forward
run "sysctl swappiness"        sysctl vm.swappiness

section "iptables-save"
if command -v iptables-save >/dev/null 2>&1; then
  iptables-save 2>&1 | redact >> "$OUT"
else
  echo "(iptables-save not present)" >> "$OUT"
fi

section "ip6tables-save"
if command -v ip6tables-save >/dev/null 2>&1; then
  ip6tables-save 2>&1 | redact >> "$OUT"
else
  echo "(ip6tables-save not present)" >> "$OUT"
fi

section "nft list ruleset"
if command -v nft >/dev/null 2>&1; then
  nft list ruleset 2>&1 | redact >> "$OUT"
else
  echo "(nft not present)" >> "$OUT"
fi

section "bridges / docker networks"
{ command -v docker >/dev/null 2>&1 && docker network ls 2>&1 || echo "(docker not installed)"; } | redact >> "$OUT"

# Self-check: refuse to claim success if the redaction did not hold. A capture
# that leaks the thing it promised to strip is worse than no capture, because
# it will be trusted and pasted.
LEAKS=0
if grep -qE '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b' "$OUT"; then
  echo "ERROR: a MAC address survived redaction in $OUT" >&2; LEAKS=1
fi
if grep -qE '\b[a-zA-Z0-9][a-zA-Z0-9-]*\.ts\.net\b' "$OUT" \
   && ! grep -qE '^\s*<tailnet>\.ts\.net' "$OUT"; then
  if grep -E '\.ts\.net' "$OUT" | grep -qv '<tailnet>'; then
    echo "ERROR: a tailnet name survived redaction in $OUT" >&2; LEAKS=1
  fi
fi

printf '\nwrote %s (%s lines)\n' "$OUT" "$(wc -l < "$OUT" | tr -d ' ')"
if [ "$LEAKS" -ne 0 ]; then
  echo "DO NOT PASTE THIS FILE. Redaction failed; fix the script first." >&2
  exit 1
fi
echo "redaction self-check passed: no MAC addresses, no tailnet name"
