#!/usr/bin/env bash
#
# homelab-watchdog.sh -- runs once per boot (Phase 12): tells the owner the
# node came back, how long it was down, whether the prior stop was clean, and
# whether the encrypted data volume needs unlocking.
#
# WHY THIS EXISTS
#
#   Phase 18.1 closed the volume's own gap (LUKS2, refuses without the
#   passphrase) but left an operational one open: the volume does not survive
#   an unattended reboot, and nothing told the owner. systemd's own timer is
#   the trigger source (homelab-watchdog.timer); this script is what it runs.
#
# WHY DOWNTIME COMES FROM `last -x`, NOT A HEARTBEAT -- AND A BLOCKING GAP
# FOUND DURING EXECUTION, NOT PAPERED OVER
#
#   `last -x` reads /var/log/wtmp, where a clean shutdown/reboot writes a
#   `shutdown` pseudo-entry timestamped at the moment it happened, and an
#   unclean one (a power cut) writes none -- the next `reboot` entry simply
#   appears with nothing before it. That absence is the entire signal (Phase
#   12 brief §7.3). No daemon samples anything while the node is healthy,
#   which is the "recovery-oriented, not real-time" scope decision on paper
#   still holding in practice.
#
#   THIS NODE DOES NOT HAVE `last` INSTALLED. Verified during execution:
#   `util-linux` 2.41.3 on Ubuntu 26.04 ("resolute") no longer ships
#   /usr/bin/last or /usr/bin/utmpdump -- `dpkg -L util-linux` lists neither.
#   The modern replacement is the separate `wtmpdb` package (candidate
#   0.75.0-5ubuntu1, not installed), which the brief's §14 ("no package is
#   installed beyond what the node already has") did not anticipate needing.
#   A from-scratch substitute -- grepping the previous boot's last few journal
#   lines for a clean-shutdown marker -- was tried and DISPROVEN against this
#   node's own known-clean boot -1->0 transition (Phase 18.1's rescue reboot):
#   the tail of that boot's journal carries no shutdown-sequence text at all,
#   so that heuristic would misclassify a clean reboot as unplanned. Rather
#   than ship a classifier proven wrong on the one real case available, this
#   script fails loudly (see the `command -v last` check below) instead of
#   guessing. See the Phase 12 execution stage report for the full finding;
#   this is recorded as a decision for the orchestrator, not resolved here.
#
# WHY THIS DOES NOT CALL `systemctl is-active` -- A DEVIATION FROM THE BRIEF'S
# OWN §7.4 TABLE
#
#   §7.4 as written checks `findmnt /srv/homelab` AND
#   `systemctl is-active homelab-data.target`. `systemctl` cannot ask PID 1
#   anything without an AF_UNIX socket (D-Bus, or /run/systemd/private
#   directly), and homelab-watchdog.service's own RestrictAddressFamilies=
#   deliberately excludes AF_UNIX (§6 of the brief -- the same restriction
#   that keeps this account off the model helper's socket). Those two
#   requirements cannot both hold in the same unit, for any account. This
#   script checks `findmnt` alone. It is a narrower signal than the brief
#   specifies, not a broader one: `findmnt` succeeding is necessary for
#   "unlocked" either way, and this node's own unlock procedure
#   (data-volume.sh unlock) always mounts before starting the target, so a
#   mount that exists without the target ever having been started is not a
#   state this node produces in practice. Recorded here and in the Phase 12
#   execution stage report, per §13's own instruction: the fix for something
#   RestrictAddressFamilies breaks is not to add AF_UNIX back.
#
# WHY IT DOES NOT, AND STRUCTURALLY CANNOT, REACH THE MODEL HELPER
#
#   §6 of the brief: nothing this phase schedules may call a model. The unit
#   running this script carries RestrictAddressFamilies=AF_INET AF_INET6 with
#   no AF_UNIX, so /run/homelab-model-helper.sock is unreachable at the
#   kernel's own seccomp filter before this script gets anywhere near it. This
#   script does not attempt to dial it, but the reason it MUST NOT is
#   enforced one layer below this file, in the unit, not by this comment.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   - Hold any key material for the volume (ADR-046 §3). It only reads
#     /etc/crypttab (world-readable, no secret in it -- no keyfile path is
#     ever recorded there) and asks findmnt, exactly the unprivileged half of
#     what `data-volume.sh status` already asks.
#   - Retry on its own. homelab-watchdog.service's bounded on-failure restart
#     is the retry policy; a loop in here would duplicate it.
#   - Send the message itself. homelab-notify.sh is the one place this
#     project defines "post text to every allowlisted chat_id" -- this script
#     only composes the text and calls it.
#
set -euo pipefail

NOTIFY="/usr/local/sbin/homelab-notify.sh"
CRYPTTAB="/etc/crypttab"
MOUNT="/srv/homelab"

die() { printf 'homelab-watchdog: %s\n' "$*" >&2; exit 1; }

# --- §7.3: duration parsing --------------------------------------------
#
# `last`'s own printed span looks like "(01:04)" (HH:MM) or "(3+01:04)"
# (days+HH:MM). Converts either form to whole minutes. `10#` forces base-10
# so a leading zero (e.g. "08") is never read as an invalid octal digit.
duration_to_minutes() {
    local dur="$1" days=0 hh mm
    if [[ "$dur" == *+* ]]; then
        days="${dur%%+*}"
        dur="${dur#*+}"
    fi
    hh="${dur%%:*}"
    mm="${dur##*:}"
    printf '%d\n' $(( 10#$days * 1440 + 10#$hh * 60 + 10#$mm ))
}

# --- §7.3: was the prior stop clean, and how long was the node down? -------
#
# Sets CLASS ("clean reboot" | "unplanned reboot") and DOWN_MIN (integer
# minutes, approximate -- the message says "~N minutes" for exactly that
# reason, never an exact figure).
classify_boot() {
    local hist line1 line2 type1 type2 dur prev_ts now_boot down_seconds

    # Fail loudly rather than silently default to "unplanned reboot" when the
    # tool is simply missing -- see the header note. A wrong-but-confident
    # classification is worse than this unit landing in `failed` and paging
    # the owner via homelab-notify@watchdog.service with the real reason in
    # its last journal lines.
    command -v last >/dev/null 2>&1 \
        || die "'last' is not installed on this node (util-linux dropped it; wtmpdb is its replacement and is also not installed). Cannot classify the prior stop as clean or unplanned -- see the Phase 12 execution stage report."

    hist="$(last -x -n 4 reboot shutdown --time-format=iso 2>/dev/null)" || hist=""
    line1="$(printf '%s\n' "$hist" | sed -n '1p')"
    line2="$(printf '%s\n' "$hist" | sed -n '2p')"
    type1="$(awk '{print $1}' <<< "$line1")" || type1=""
    type2="$(awk '{print $1}' <<< "$line2")" || type2=""

    if [ "$type1" = "reboot" ] && [ "$type2" = "shutdown" ]; then
        CLASS="clean reboot"
        dur="$(grep -oE '\(([0-9]+\+)?[0-9]+:[0-9]+\)' <<< "$line2" | tail -1 | tr -d '()')" || dur=""
        if [ -n "$dur" ]; then
            DOWN_MIN="$(duration_to_minutes "$dur")"
        else
            # last's own printed span was unparseable -- approximate, per §7.3.
            DOWN_MIN=0
        fi
    else
        CLASS="unplanned reboot"
        # No `shutdown` entry between the two most recent `reboot` entries:
        # compute downtime from what the previous boot last logged before it
        # stopped, per §7.3's exact mechanism.
        prev_ts="$(journalctl -b -1 -n 1 --output=short-iso --no-pager 2>/dev/null | awk '{print $1}')" || prev_ts=""
        now_boot="$(uptime -s 2>/dev/null)" || now_boot=""
        if [ -n "$prev_ts" ] && [ -n "$now_boot" ] && date -d "$prev_ts" >/dev/null 2>&1; then
            down_seconds=$(( $(date -d "$now_boot" +%s) - $(date -d "$prev_ts" +%s) ))
            [ "$down_seconds" -ge 0 ] || down_seconds=0
            DOWN_MIN=$(( down_seconds / 60 ))
        else
            # No prior boot's journal to compute from (e.g. journal not
            # persisted across this gap, or the very first boot) --
            # approximate as 0 rather than fail the whole run over one number.
            DOWN_MIN=0
        fi
    fi
}

# --- §7.4: the data volume's lock state, unprivileged, three-way -----------
#
# Order matters: an unconfigured node must never be reported as LOCKED, so
# /etc/crypttab is checked first. Matches on the first field exactly, not on
# any line mentioning "homelab-data" as a comment or neighbour (§4 rule 7).
volume_state() {
    if ! awk '$1 !~ /^#/ && $1 == "homelab-data" { f=1 } END { exit !f }' "$CRYPTTAB" 2>/dev/null; then
        STATE="not configured on this node"
    elif findmnt -n "$MOUNT" >/dev/null 2>&1; then
        STATE="unlocked"
    else
        STATE="LOCKED -- ssh homelab && sudo data-volume.sh unlock"
    fi
}

classify_boot
volume_state

MESSAGE="$(printf 'Home Lab back up. Down ~%dm, %s. Data volume: %s' "$DOWN_MIN" "$CLASS" "$STATE")"

# Logged before sending: journalctl -u homelab-watchdog.service -b shows
# exactly what was (or would have been) sent, with no separate debug path to
# drift from what homelab-notify.sh actually receives.
printf '%s\n' "$MESSAGE"

"$NOTIFY" "$MESSAGE"
