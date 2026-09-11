#!/usr/bin/env bash
#
# boundary-gate.sh -- refuse to let knowledge-shaped or output-shaped content
# sit in a public repository.
#
# WHY THIS EXISTS
#
#   ADR-029 §2 draws the line this project is organised around: method is
#   public, output is private. ADR-029 §5 then says something sharper -- that
#   the line is "enforced by a check, not by care":
#
#       "The public repositories fail their check if knowledge-shaped or
#        output-shaped content appears in them."
#
#   That check did not exist. On 2026-09-11 five knowledge-base files were
#   found sitting in the public Factory repository, having been swept there by
#   an extraction months earlier and noticed by a human reading a handover.
#   Care had been applied. Care was not enough.
#
#   ADR-031 made this more load-bearing rather than less: public and private
#   repositories are now siblings on one filesystem, which makes a stray copy
#   between them possible in a way it was not when they lived apart.
#
# WHAT "KNOWLEDGE-SHAPED" AND "OUTPUT-SHAPED" MEAN HERE
#
#   Knowledge-shaped: a processed note from the knowledge base. It carries a
#   distinctive YAML frontmatter vocabulary -- synthesis_debt, distilled_into,
#   actionability and friends -- that nothing else in this system uses.
#
#   Output-shaped: an operational record produced by running the Factory on a
#   project. Tickets, reviews, approvals, runs. By ADR-028 §1 the Factory is
#   stateless method and holds none of them; by ADR-030 §2 they live in
#   projects/<name>/ops/.
#
# THE FALSE POSITIVE THAT WOULD MAKE THIS USELESS
#
#   ADR-029's own tables list 00-inbox, 01-knowledge, 02-ideas and 05-logs.
#   ADR-030 §2 names ops/tickets. The guide discusses both. A substring search
#   for those paths fails the very documents that define the boundary.
#
#   Worse, Factory legitimately ships ops *templates* containing
#   `object_type: ticket`. A template is method. A record is output. They are
#   one character apart: TICKET-YYYY-0001 is a template, TICKET-2026-0001 is a
#   record.
#
#   So every check here matches on STRUCTURE -- frontmatter blocks, concrete
#   identifiers, file paths -- never on a word appearing somewhere in prose.
#   A detector that cries wolf teaches you to ignore it, which is worse than
#   having none.
#
# WHY HISTORY IS REPORTED BUT DOES NOT FAIL
#
#   Git keeps every version of every file. The five files removed from Factory
#   are gone from its tip and still in its history, and will be forever:
#   removing them needs a force-push, which branch protection blocks and which
#   breaks every existing clone.
#
#   Failing on history would mean this gate could never pass, which means it
#   would be disabled. So the tip FAILS and history REPORTS. That is a real
#   limitation and it is stated rather than hidden.
#
# WHAT IT DOES NOT CATCH -- read this part
#
#   1. A private paragraph pasted into an otherwise legitimate method file.
#      Path and frontmatter checks cannot see inside a file that is allowed to
#      exist. Nothing here substitutes for reading a diff.
#   2. Knowledge written in a shape this project has never used. These are the
#      signatures of the knowledge base as it exists today.
#   3. Content that is private for a reason nobody encoded -- a client name, an
#      unreleased product. That is judgement, and judgement is not automatable.
#   4. Binary files. Skipped, and counted.
#   5. The history scan matches on PATHS ONLY. The five files that prompted
#      this gate lived at agents/skills/*.md in Factory -- an ordinary method
#      path -- and were knowledge-shaped only in their content. A content-based
#      history scan, reading every blob the way scan-history.sh does, would
#      catch that class. It is not built yet, and that limitation is part of
#      why the working-tree scan is the one that fails.
#
#   A clean run means "none of these patterns matched". It does not mean the
#   repository is safe to publish. It means one specific class of mistake did
#   not happen.
#
# SELF-TEST
#
#   Run with --self-test and it plants known-bad files, confirms every check
#   fires on them, and confirms the known-good controls do NOT fire. CI runs
#   this before the real scan on every invocation, so the gate cannot rot into
#   something that always says "clean".
#
#   This project has recorded thirteen occasions where a check reported a
#   result it could not support. A detector that has only ever reported clean
#   is unvalidated.
#
# USAGE
#
#   ./scripts/boundary-gate.sh                  # scan this repo's working tree
#   ./scripts/boundary-gate.sh /path/to/repo    # scan another repo
#   ./scripts/boundary-gate.sh --history        # also report on git history
#   ./scripts/boundary-gate.sh --self-test      # prove the checks can fire
#
# EXIT CODES
#
#   0  no knowledge-shaped or output-shaped content in the working tree
#   1  something was found -- do not publish
#   2  the gate itself is broken (self-test failed)
#
set -uo pipefail

SELF_TEST=0
SCAN_HISTORY=0
TARGET="."
for arg in "$@"; do
    case "$arg" in
        --self-test) SELF_TEST=1 ;;
        --history)   SCAN_HISTORY=1 ;;
        -h|--help)   sed -n '2,110p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           TARGET="$arg" ;;
    esac
done

RED=''; GRN=''; YEL=''; OFF=''
if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'; fi

FAILURES=0
REVIEWS=0
SKIPPED=0

fail_hit()   { printf '%s  FAIL  %s%s\n' "$RED" "$1" "$OFF"; FAILURES=$((FAILURES+1)); }
review_hit() { printf '%s  REVIEW%s %s\n' "$YEL" "$OFF" "$1"; REVIEWS=$((REVIEWS+1)); }
heading()    { printf '\n== %s\n' "$1"; }

# ---------------------------------------------------------------------------
# The signatures.
#
# Kept as data, near the top, because this list is the whole judgement of the
# script and anyone auditing it should not have to read the logic to find it.
# ---------------------------------------------------------------------------

# Frontmatter keys distinctive to the knowledge base. Deliberately excludes
# generic ones like `type`, `status`, `created`, `related` and `tags`, which
# any document might carry. Two or more of these together is not a coincidence.
KB_KEYS='synthesis_debt|distilled_into|actionability|market_signals|source_url|source_type|coverage|confidence'

# Operational object types, from Factory's own ops templates.
OPS_TYPES='ticket|approval|review_record|task|interaction|learning_candidate|founder_inbox_item|run|release|context_pack'

# A CONCRETE identifier -- a real year, not the YYYY placeholder a template
# carries. This single distinction is what separates method from output.
OPS_ID='(TICKET|APPROVAL|REVIEW|TASK|INTERACTION|LEARN|INBOX|RUN|RELEASE|GOAL|FEATURE|CP)-(19|20)[0-9]{2}-[0-9]{4}'

# Directories that only ever exist inside the private knowledge base or a
# project's ops tree. Matched as PATH COMPONENTS of a file, never as prose.
KB_DIRS='00-inbox|01-knowledge|02-ideas|03-projects|04-agents|05-logs'
OPS_DIRS='ops/(tickets|runs|reviews|approvals|releases|inbox|interactions|learning|context-packs|goals|features|archive|dashboard-state)'

# Paths that existed only in the private vault before the 2026-09-10 split.
# These leaked into the public Factory repo once already, in prose links.
VAULT_PATHS='03-projects/ai-development-team|04-agents/'

# ---------------------------------------------------------------------------

is_text() { file -b --mime "$1" 2>/dev/null | grep -q 'charset=binary' && return 1 || return 0; }

# Does this file carry >= 2 knowledge-base frontmatter keys inside a real
# frontmatter block? Prose mentioning `source_url` in a sentence will not match,
# because the match is anchored and confined to the block.
has_kb_frontmatter() {
    awk -v keys="$KB_KEYS" '
        NR==1 && $0 != "---" { exit 1 }
        NR==1 { inblock=1; next }
        inblock && $0 == "---" { exit (n >= 2 ? 0 : 1) }
        inblock && $0 ~ "^(" keys "):" { n++ }
        NR > 60 { exit 1 }
    ' "$1"
}

# An ops RECORD: declares an object_type AND carries a concrete identifier.
# A template declares the type but its id is a YYYY placeholder.
is_ops_record() {
    grep -qE "^object_type: *($OPS_TYPES)" "$1" 2>/dev/null || return 1
    grep -qE "^id: *$OPS_ID" "$1" 2>/dev/null
}

scan_tree() {
    local root="$1"
    local found_any=0
    # `f` and `rel` MUST be local. Without that they leak into the caller, and
    # the self-test harness -- which also uses `f` -- had its variable silently
    # emptied, so its cleanup ran `rm -f ""` and every fixture accumulated.
    # The negative controls then failed against leftovers from the positives.
    local f rel is_template

    heading "Working tree: $root"

    while IFS= read -r f; do
        rel="${f#"$root"/}"

        # Skip our own fixtures and anything git ignores.
        case "$rel" in
            .git/*|*/.git/*) continue ;;
            scripts/boundary-gate.sh) continue ;;
        esac

        if ! is_text "$f"; then SKIPPED=$((SKIPPED+1)); continue; fi

        # --- path-shaped: a file living at a knowledge or ops address --------
        # Matched on directory components of the file's own path. A document
        # that merely *mentions* 01-knowledge is not at that path.
        if printf '%s' "$rel" | grep -qE "(^|/)($KB_DIRS)/"; then
            fail_hit "$rel — sits at a knowledge-base path"
            found_any=1; continue
        fi
        # A path under templates/ is SCAFFOLDING, and scaffolding necessarily
        # mirrors the layout it scaffolds: ADR-028 §2 gives every project a
        # project-workspace/ containing an empty ops/ skeleton. Exempting the
        # PATH check here is required; the CONTENT checks below still apply, so
        # a real record hidden under templates/ is still caught.
        case "$rel" in templates/*|*/templates/*) is_template=1 ;; *) is_template=0 ;; esac

        if [ "$is_template" -eq 0 ] && printf '%s' "$rel" | grep -qE "(^|/)$OPS_DIRS/"; then
            fail_hit "$rel — sits at a project ops path (ADR-028 §1: Factory holds no records)"
            found_any=1; continue
        fi

        # --- content-shaped --------------------------------------------------
        case "$rel" in
            *.md|*.markdown)
                if has_kb_frontmatter "$f"; then
                    fail_hit "$rel — carries knowledge-base frontmatter"
                    found_any=1; continue
                fi ;;
        esac
        case "$rel" in
            *.yaml|*.yml|*.json)
                # No templates/ exemption here, deliberately. A template's id is
                # the YYYY placeholder, which OPS_ID already refuses, so the
                # exemption bought nothing -- and it would have let a genuine
                # record hide under templates/ untouched.
                if is_ops_record "$f"; then
                    fail_hit "$rel — is an operational record, not a template"
                    found_any=1; continue
                fi ;;
        esac

        # --- review-only: private vault paths referenced in prose ------------
        if grep -qE "$VAULT_PATHS" "$f" 2>/dev/null; then
            review_hit "$rel — references a private vault path"
        fi
    done < <(cd "$root" && git ls-files -z 2>/dev/null | tr '\0' '\n' | sed "s|^|$root/|")

    [ "$found_any" -eq 0 ] && printf '%s  clean%s\n' "$GRN" "$OFF"
    return 0
}

scan_history() {
    local root="$1"
    heading "History (report only — see the header for why this cannot fail)"

    local hits=0
    # Local for the same reason as in scan_tree. `path` additionally collides
    # with a special variable in zsh, where it is tied to $PATH.
    local path

    # Deduplicated: git stores one object per *version*, so an unchanged file
    # repeats once per commit that touched its tree. The question asked here is
    # "did this path ever exist", which is asked once.
    while read -r path; do
        [ -n "${path:-}" ] || continue
        # templates/ is scaffolding, exempt for the same reason as in scan_tree.
        case "$path" in .git/*|templates/*|*/templates/*) continue ;; esac
        if printf '%s' "$path" | grep -qE "(^|/)($KB_DIRS)/" \
        || printf '%s' "$path" | grep -qE "(^|/)$OPS_DIRS/"; then
            printf '  once present: %s\n' "$path"
            hits=$((hits+1))
        fi
    done < <(cd "$root" && git rev-list --objects --all 2>/dev/null | awk 'NF==2 {print $2}' | sort -u)

    if [ "$hits" -eq 0 ]; then
        printf '%s  no knowledge or ops paths anywhere in history%s\n' "$GRN" "$OFF"
    else
        printf '\n  %s such path(s) exist in history and cannot be removed without a\n' "$hits"
        printf '  force-push. Recorded, not failed. See the header.\n'
    fi
}

self_test() {
    heading "Self-test — the checks must fire on planted content"
    local tmp ok=0 bad=0
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    (cd "$tmp" && git init -q . && git config user.email t@t && git config user.name t)

    check() { # name, expect-fire(1/0), path
        local before=$FAILURES
        local f="$tmp/$3"
        mkdir -p "$(dirname "$f")"
        cat > "$f"
        (cd "$tmp" && git add -A >/dev/null 2>&1)
        FAILURES=0; REVIEWS=0
        scan_tree "$tmp" >/dev/null 2>&1
        local fired=$(( FAILURES > 0 ? 1 : 0 ))
        if [ "$fired" -eq "$2" ]; then
            printf '%s  ok  %s%s\n' "$GRN" "$1" "$OFF"; ok=$((ok+1))
        else
            printf '%s  BROKEN  %s — expected fire=%s, got %s%s\n' "$RED" "$1" "$2" "$fired" "$OFF"; bad=$((bad+1))
        fi
        rm -f "$f"; (cd "$tmp" && git add -A >/dev/null 2>&1)
        FAILURES=$before
    }

    # --- positives: these MUST fire ---
    check "knowledge note by frontmatter" 1 "docs/note.md" <<'EOF'
---
type: source
status: distilled
synthesis_debt: none
distilled_into: somewhere
---
Body.
EOF

    check "file at a knowledge path" 1 "01-knowledge/whatever.md" <<'EOF'
Nothing special in the body.
EOF

    check "ops record by concrete id" 1 "agents/TICKET-2026-0001.yaml" <<'EOF'
object_type: ticket
id: TICKET-2026-0001
status: inbox
EOF

    check "ops record at an ops path" 1 "ops/tickets/x.yaml" <<'EOF'
anything: at all
EOF

    # --- negatives: these MUST NOT fire ---
    check "an ADR that discusses the boundary" 0 "docs/decisions/ADR-999.md" <<'EOF'
# ADR-999
The knowledge base holds 00-inbox, 01-knowledge, 02-ideas and 05-logs.
Records live in ops/tickets and ops/reviews. See source_url and coverage.
EOF

    check "an ops TEMPLATE with a placeholder id" 0 "templates/ops/ticket.yaml" <<'EOF'
template_version: "0.1"
object_type: ticket
id: TICKET-YYYY-0001
EOF

    check "ordinary doc with a frontmatter block" 0 "docs/normal.md" <<'EOF'
---
title: A normal document
status: draft
created: 2026-09-11
---
Body.
EOF

    check "template scaffolding at an ops path" 0 "templates/project-workspace/ops/tickets/README.md" <<'EOF'
Tickets for this project go here. This directory is scaffolding, not a record.
EOF

    # The hole the templates/ exemption used to leave open. This control exists
    # because the exemption was widened for scaffolding, and a widened exemption
    # is exactly where a real record would slip through.
    check "a REAL record hidden under templates/" 1 "templates/ops/sneaky.yaml" <<'EOF'
object_type: ticket
id: TICKET-2026-0007
status: in_progress
EOF

    printf '\n  %s passed, %s broken\n' "$ok" "$bad"
    [ "$bad" -eq 0 ] || return 1
    return 0
}

# ---------------------------------------------------------------------------

command -v git >/dev/null || { echo "git not found"; exit 2; }

if [ "$SELF_TEST" -eq 1 ]; then
    if self_test; then
        printf '\n%sSelf-test passed — the gate can fail, and does not fail on method.%s\n' "$GRN" "$OFF"
        exit 0
    fi
    printf '\n%sSELF-TEST FAILED. The gate is broken; its verdicts mean nothing.%s\n' "$RED" "$OFF"
    exit 2
fi

TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "no such directory"; exit 2; }
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $TARGET"; exit 2; }

printf 'Boundary gate (ADR-029 §5) — %s\n' "$TARGET"
scan_tree "$TARGET"
[ "$SCAN_HISTORY" -eq 1 ] && scan_history "$TARGET"

printf '\n== Result\n'
printf '  %s failure(s), %s for review, %s binary file(s) skipped\n' "$FAILURES" "$REVIEWS" "$SKIPPED"

if [ "$FAILURES" -gt 0 ]; then
    printf '\n%sDo not publish. Knowledge-shaped or output-shaped content is in the tree.%s\n' "$RED" "$OFF"
    exit 1
fi
printf '\n%sNo knowledge-shaped or output-shaped content in the working tree.%s\n' "$GRN" "$OFF"
printf 'That is one class of mistake ruled out. It is not a guarantee — read the header.\n'
exit 0
