#!/usr/bin/env bash
#
# scan-history.sh -- look for secrets in EVERY version of EVERY file this
# repository has ever committed, not just the files currently on disk.
#
# WHY THIS EXISTS
#
#   Before a repository is published, the working tree is the wrong thing to
#   check. Git keeps every version of every file it has ever been told about.
#   A password committed in January and deleted in February is still in the
#   history in March, and `git clone` hands it to anyone who asks.
#
#   .gitignore does not help with this. .gitignore only stops git tracking
#   files it is not already tracking. It is not retroactive and it never
#   removes anything. If a secret is already committed, .gitignore is silent
#   about it forever.
#
# WHAT IT SCANS
#
#   Every blob reachable from every ref (`git rev-list --objects --all`).
#   A "blob" is git's name for the stored contents of one version of one file.
#   Reachable-from-a-ref is exactly the set of objects `git push` would
#   transfer, so this is the right scope for a pre-publication check.
#
# WHAT IT DOES *NOT* CATCH -- read this part
#
#   1. Unreachable objects: things only in the reflog, or orphaned by a reset.
#      Those are not pushed, so they are out of scope here -- but they are
#      still on your disk.
#   2. Anything the patterns below do not describe. This is a list of things
#      someone already thought of. A novel secret format walks straight past.
#      That is why you should also run an independent scanner and compare.
#   3. Encoded or split secrets. A key stored base64'd, or in two halves,
#      matches nothing here except possibly the entropy check.
#   4. Binary files (skipped -- see SKIPPED count in the output).
#   5. Judgement. Several categories below are REVIEW, not FAIL, because
#      whether they are secret depends on the project. The script cannot
#      decide that; it can only refuse to let you publish without looking.
#
#   A clean run means "none of these patterns matched". It does not mean
#   "there are no secrets". Those are different statements.
#
# NOTE ON THE PATTERNS THEMSELVES
#
#   This script deliberately does NOT hardcode the owner's real email address,
#   tailnet name, or Wi-Fi passphrase. Writing a secret into the scanner that
#   looks for it would commit the secret to the repository -- the exact
#   outcome the script exists to prevent. Every pattern is generic, and the
#   known-safe values are excluded by an allow-list instead.
#
# Usage:  bash scripts/macos/scan-history.sh [path-to-repo]
#
# Exit:   0 = no CRITICAL findings (REVIEW findings may still be present)
#         1 = at least one CRITICAL finding -- do not publish
#         2 = could not run

# NOT `set -e`. A scan must report every finding it has, then exit with a
# considered status. Aborting on the first hit would hide the rest, and the
# whole point is to see the complete picture before deciding to publish.
set -uo pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
if [ -z "$REPO" ] || [ ! -d "$REPO/.git" ]; then
  echo "ERROR: not a git repository: ${REPO:-<none>}" >&2
  exit 2
fi
cd "$REPO" || exit 2

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CRITICAL=0
REVIEW=0
SKIPPED=0

c_red()  { printf '\033[31m%s\033[0m\n' "$1"; }
c_yel()  { printf '\033[33m%s\033[0m\n' "$1"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$1"; }

echo "======================================================================"
echo " Full-history secrets scan"
echo " Repository: $REPO"
echo " Date:       $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================================================"
echo

# ---------------------------------------------------------------------------
# Step 1: enumerate every blob that would be pushed.
#
# `git rev-list --objects --all` prints "<hash> <path>" for every object
# reachable from any ref. The same file content committed twice has one blob,
# so deduplicating by hash means we read each distinct version exactly once.
# ---------------------------------------------------------------------------
git rev-list --objects --all \
  | awk 'NF==2 {print $1" "$2}' \
  | sort -u -k1,1 \
  > "$WORK/objects.txt"

TOTAL_OBJ=$(wc -l < "$WORK/objects.txt" | tr -d ' ')
echo "Objects reachable from all refs: $TOTAL_OBJ"

# Keep only blobs. Trees and commits are structure, not content.
: > "$WORK/blobs.txt"
while read -r hash path; do
  if [ "$(git cat-file -t "$hash" 2>/dev/null)" = "blob" ]; then
    printf '%s %s\n' "$hash" "$path" >> "$WORK/blobs.txt"
  fi
done < "$WORK/objects.txt"

TOTAL_BLOB=$(wc -l < "$WORK/blobs.txt" | tr -d ' ')
echo "Of which file contents (blobs):  $TOTAL_BLOB"
echo

# ---------------------------------------------------------------------------
# Step 2: materialise every blob once, into one searchable corpus.
#
# Each blob is written with a header line naming its hash and path, so a hit
# can be traced back to a specific version of a specific file.
# ---------------------------------------------------------------------------
: > "$WORK/corpus.txt"
while read -r hash path; do
  # Skip binaries: a NUL byte in the first 8 KB is git's own heuristic too.
  #
  # Detected by deleting NULs and seeing whether the length changed. The
  # obvious version -- grep for $'\x00' -- CANNOT WORK: a NUL cannot survive
  # being passed to grep as a C-string pattern, so the pattern arrives empty,
  # an empty pattern matches every line, and every blob is classified binary.
  # That bug made this script skip all 213 blobs and report all 16 classes
  # clean, which looked exactly like a pass. See the Phase 04 build log.
  raw="$(git cat-file -p "$hash" 2>/dev/null | head -c 8192 | wc -c | tr -d ' ')"
  stripped="$(git cat-file -p "$hash" 2>/dev/null | head -c 8192 | LC_ALL=C tr -d '\000' | wc -c | tr -d ' ')"
  if [ "$raw" != "$stripped" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  printf '@@BLOB %s %s\n' "$hash" "$path" >> "$WORK/corpus.txt"
  git cat-file -p "$hash" 2>/dev/null >> "$WORK/corpus.txt"
done < "$WORK/blobs.txt"

echo "Binary blobs skipped:            $SKIPPED"

# ---------------------------------------------------------------------------
# Step 2b: prove the corpus is actually searchable BEFORE trusting any result.
#
# A scan that searched nothing reports every class clean, and a clean report
# is indistinguishable from a pass unless you check this. An earlier version
# of this script did exactly that. So: refuse to report at all unless the
# corpus is non-empty AND a string known to be in this repository can be
# found in it. A scanner that cannot find something you know is there is
# broken, and must say so rather than say "clean".
# ---------------------------------------------------------------------------
CORPUS_BYTES="$(wc -c < "$WORK/corpus.txt" | tr -d ' ')"
CORPUS_BLOBS="$((TOTAL_BLOB - SKIPPED))"
echo "Blobs actually searched:         $CORPUS_BLOBS  (${CORPUS_BYTES} bytes)"

if [ "$CORPUS_BLOBS" -le 0 ] || [ "$CORPUS_BYTES" -le 0 ]; then
  echo
  c_red " ERROR: nothing was searched. This is NOT a clean result -- it is no"
  c_red " result. Refusing to report a verdict."
  exit 2
fi

# Positive control: this file is in every commit of this repository.
if ! LC_ALL=C grep -q 'PROJECT.md' "$WORK/corpus.txt"; then
  echo
  c_red " ERROR: the positive control did not match. The corpus was built but"
  c_red " is not searchable as expected. Refusing to report a verdict."
  exit 2
fi
echo

# ---------------------------------------------------------------------------
# Step 3: the pattern classes.
#
# check <severity> <label> <extended-regex> [<allow-regex>]
#
#   severity FAIL   -- if this matches, do not publish. Counts as CRITICAL.
#   severity REVIEW -- a human must look and decide. Counts as REVIEW.
#
# <allow-regex> removes known-safe matches. Every allow-list entry is a claim
# that something is fine, so each one below carries a comment saying why.
# ---------------------------------------------------------------------------
check() {
  local severity="$1" label="$2" regex="$3" allow="${4:-}"
  local hits status

  # -e is MANDATORY here, not stylistic. Several patterns below begin with a
  # dash (a PEM header is "-----BEGIN ..."). Without -e, grep parses the
  # pattern as command-line options, fails with exit 2, prints nothing on
  # stdout, and the caller cannot tell that from "no matches". The private-key
  # class -- the most important one in this file -- was silently dead for
  # exactly this reason until a planted-secret test caught it.
  hits="$(LC_ALL=C grep -n -E -e "$regex" "$WORK/corpus.txt")"
  status=$?

  # grep: 0 = matched, 1 = no match, 2+ = error. Treating an error as "no
  # match" is how a broken check reports clean. Refuse to continue instead.
  if [ "$status" -gt 1 ]; then
    echo
    c_red " ERROR: the pattern for '$label' could not be applied (grep exit $status)."
    c_red " This is a broken check, not a clean result. Refusing to report a verdict."
    exit 2
  fi

  if [ -n "$allow" ] && [ -n "$hits" ]; then
    hits="$(printf '%s\n' "$hits" | LC_ALL=C grep -v -E -e "$allow")"
    status=$?
    if [ "$status" -gt 1 ]; then
      echo
      c_red " ERROR: the allow-list for '$label' could not be applied (grep exit $status)."
      exit 2
    fi
  fi

  if [ -z "$hits" ]; then
    printf '  %-34s %s\n' "$label" "$(c_grn 'clean')"
    return
  fi

  local n
  n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"

  if [ "$severity" = "FAIL" ]; then
    printf '  %-34s %s\n' "$label" "$(c_red "$n MATCHES -- CRITICAL")"
    CRITICAL=$((CRITICAL + 1))
  else
    printf '  %-34s %s\n' "$label" "$(c_yel "$n matches -- review")"
    REVIEW=$((REVIEW + 1))
  fi

  # Show the distinct matched text, not whole lines. Distinct tokens are what
  # a human actually needs: 59 hits of one placeholder is a different fact
  # from 59 hits of 59 real values, and the count alone cannot tell them apart.
  printf '%s\n' "$hits" \
    | sed -E 's/^[0-9]+://' \
    | LC_ALL=C grep -o -E -e "$regex" \
    | sort | uniq -c | sort -rn | head -12 \
    | sed 's/^/        /'
  echo
}

# Lines of this script's OWN OUTPUT, quoted into a build log as evidence.
#
# Phase 04 planted six fake secrets to prove this scanner could detect them,
# then wrote the results up -- and the write-up tripped all six classes on
# published main. The values were never real, but a gate that is permanently
# red is a gate people wave through.
#
# "MATCHES -- CRITICAL" is emitted only by this script. A genuine secret is
# never on a line that also contains it. That makes this a narrow, specific
# discriminator rather than a path exclusion: docs/build-log/ is still scanned
# in full, so a real secret landing there would still be caught.
#
# See Problem 5 in docs/build-log/2026-09-09-phase-04-audit.md.
EVIDENCE='MATCHES -- CRITICAL'

echo "Pattern classes"
echo "---------------"

# --- Credentials. Any match here is disqualifying. ---
check FAIL "private keys" \
  '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
  "$EVIDENCE"

check FAIL "SSH public keys" \
  'ssh-(rsa|ed25519|dss) AAAA[0-9A-Za-z+/]{20,}'

check FAIL "Tailscale auth keys" \
  'tskey-[a-zA-Z0-9-]{10,}' \
  "$EVIDENCE"

check FAIL "GitHub tokens" \
  '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})' \
  "$EVIDENCE"

check FAIL "OpenAI / Anthropic keys" \
  '(sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,})'

check FAIL "AWS access key ids" \
  'AKIA[0-9A-Z]{16}'

check FAIL "Slack tokens" \
  'xox[baprs]-[A-Za-z0-9-]{10,}'

# A wifi passphrase in netplan appears as a bare `password:` under the SSID.
# The repository's example files use an obvious placeholder, which is allowed.
check FAIL "wifi passphrase / psk" \
  '^[[:space:]]*(password|psk)[[:space:]]*:[[:space:]]*["'"'"']?[^"'"'"'[:space:]]{8,}' \
  'CHANGE-ME|<[A-Za-z-]+>|YOUR-|EXAMPLE|xxxxx|REDACTED|DO_NOT_COMMIT'

# --- Hardware and network identity. The owner's standing rule names MACs. ---
check FAIL "MAC addresses" \
  '\b[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}\b' \
  "00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|$EVIDENCE"

# --- Identity. Generic patterns, known-safe values excluded. ---
# The GitHub noreply address is the whole point of using a noreply address:
# it is designed to be public and it is what all commits already use.
check FAIL "email addresses" \
  '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' \
  "users\.noreply\.github\.com|noreply@anthropic\.com|@example\.(com|org)|@[a-z]+\.invalid|$EVIDENCE"

# A real tailnet is a name plus .ts.net. The repo's placeholders are excluded;
# anything else reaching this line is a real tailnet name and must not ship.
check FAIL "tailnet names" \
  '[A-Za-z0-9_.<>{}$-]+\.ts\.net' \
  "<tailnet>|CHANGE-ME|\{tailnet\}|\\\$tailnet|example\.ts\.net|$EVIDENCE"

# --- Judgement calls. Not secrets by default; the project must decide. ---
check REVIEW "hardware serial numbers" \
  '\b([Ss]erial|SERIAL|[Ss]/[Nn])[[:space:]]*[:=][[:space:]]*[A-Za-z0-9-]{6,}' \
  'CHANGE-ME|<|XXXX|redacted|REDACTED'

check REVIEW "absolute home paths" \
  '/(Users|home)/[a-z][a-z0-9_-]{1,31}/'

check REVIEW "private (RFC1918) addresses" \
  '\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b'

check REVIEW "tailnet (CGNAT) addresses" \
  '\b100\.([6-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b'

# Catch-all for things no pattern above describes. Expect false positives:
# checksums, hashes and base64 test data all look like this. That is fine --
# the job of this check is to make you look, not to be right.
check REVIEW "long high-entropy strings" \
  '\b[A-Za-z0-9+/]{48,}={0,2}\b'

# ---------------------------------------------------------------------------
# Step 4: verdict.
# ---------------------------------------------------------------------------
echo "======================================================================"
if [ "$CRITICAL" -gt 0 ]; then
  c_red " VERDICT: $CRITICAL critical class(es) matched. DO NOT PUBLISH."
  echo
  echo " Fix before pushing. History has never been pushed only once; after"
  echo " that, removing a secret is a coordination problem and a disclosure"
  echo " you cannot recall. If a credential was exposed, rotate it first --"
  echo " rewriting history is the second action, not the first."
  echo "======================================================================"
  exit 1
fi

if [ "$REVIEW" -gt 0 ]; then
  c_yel " VERDICT: no critical findings. $REVIEW class(es) need human judgement."
else
  c_grn " VERDICT: no critical findings and nothing flagged for review."
fi
echo
echo " This means the listed patterns did not match. It does not mean the"
echo " repository holds no secrets. Run an independent scanner as well and"
echo " compare -- two tools that agree are worth more than one that is"
echo " confident."
echo "======================================================================"
exit 0
