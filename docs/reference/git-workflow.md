# Git Workflow Reference

Operational counterpart to [`guide/04-git-github/README.md`](../../guide/04-git-github/README.md).
The guide explains *why*; this file is what you reach for mid-task.

Grouped by the question being asked, like
[`linux-command-reference.md`](linux-command-reference.md).

- **Repository:** `github.com/TelesforoAleix/homelab` — **public** (ADR-021)
- **Default branch:** `main`, kept known-working (ADR-013)
- **Merges:** always `--no-ff`, so each phase boundary survives as a merge commit

---

## Running a phase, start to finish

The sequence every phase from 04 onward follows.

```bash
# 1. Start from a clean, current main
git switch main
git pull

# 2. Branch. Names are set by CONTRIBUTING.md.
git switch -c feature/05-docker

# 3. FIRST TASK: write the brief, and commit it before implementing (ADR-017)
git add docs/handovers/05-docker.md
git commit -m "docs: prepare the Phase 05 (Docker) brief"

# 4. Implement, committing in coherent steps
git add -A && git commit

# 5. Push and open a pull request
git push -u origin feature/05-docker
gh pr create --base main --head feature/05-docker --title "..." --body "..."

# 6. Merge, KEEPING the merge commit
gh pr merge --merge

# 7. Tag the completed phase and push the tag
git switch main && git pull
git tag -a phase-05 -m "Phase 05 complete: Docker & Docker Compose"
git push origin --tags
```

`--merge`, never `--squash`. Squashing collapses a phase into one commit and destroys the history
this project keeps deliberately.

---

## "What is the state of things?"

| Question | Command |
|---|---|
| What has changed, and what is staged? | `git status` / `git status --short` |
| What are the unstaged edits? | `git diff` |
| What will the next commit contain? | `git diff --staged` |
| Which branch am I on, and is it tracking? | `git status -sb` |
| Is my branch behind the remote? | `git fetch && git status` |
| What branches exist? | `git branch -a` |
| Which branches are fully merged? | `git branch --merged main` |
| Which are **not**? | `git branch --no-merged main` |

`origin/main` is a **local cache**. It only updates on `fetch` or `pull`. If it looks stale, it is.

---

## "What happened, and when?"

| Question | Command |
|---|---|
| Recent history | `git log --oneline -20` |
| The shape of history | `git log --graph --oneline --all` |
| Where are the phase boundaries? | `git log --oneline --merges` |
| What did this commit change? | `git show <hash>` |
| …just the file list | `git show --stat <hash>` |
| **When did this text enter the repo?** | `git log -S '<string>' --all` |
| Who last touched each line? | `git blame <file>` |
| What is this commit, as an object? | `git cat-file -p <hash>` |
| What did this file look like then? | `git show <hash>:<path>` |

`git log -S` is the one to remember. It finds commits that changed the number of occurrences of a
string — the fastest way to answer "when did this get here?" and the first tool to reach for if a
secret is ever suspected.

---

## "I need to undo something"

Ordered by how much they destroy. Read the whole row before running it.

| Want | Command | Destroys? |
|---|---|---|
| Unstage a file, keep edits | `git restore --staged <file>` | no |
| Discard edits to a file | `git restore <file>` | **yes — uncommitted work** |
| Change the last commit message | `git commit --amend` | rewrites that commit |
| Add a forgotten file to the last commit | `git add <f> && git commit --amend --no-edit` | rewrites that commit |
| Undo a commit, keep the changes staged | `git reset --soft HEAD~1` | no |
| Undo a commit, keep changes in the tree | `git reset HEAD~1` | no |
| Undo a commit and the changes | `git reset --hard HEAD~1` | **yes** — recoverable via reflog |
| Undo a **published** commit | `git revert <hash>` | no — makes a new commit |
| Abandon a merge in progress | `git merge --abort` | no |

**Never `--amend` or `reset` a commit that has been pushed.** Both replace commits with different
hashes. Use `git revert`, which records the reversal as new history rather than pretending the
mistake never happened — which is also what `PROJECT.md` §11 requires.

---

## "I lost work"

Usually false. Git records every movement of `HEAD`.

```bash
git reflog                      # every position HEAD has held
git reset --hard <hash>         # go back to one
git reflog show <branch>        # per-branch history
```

Caveats: the reflog is **local and private** (never pushed, never cloned), and it only covers things
that were **committed**. Uncommitted work destroyed by `git restore` is genuinely gone.

Commit early. Commits are cheap and recoverable; working trees are not.

---

## "There is a conflict"

```bash
git status                      # UU = both sides modified
git show :1:<file>              # the common ancestor
git show :2:<file>              # ours
git show :3:<file>              # theirs
# edit the file, delete all three marker lines
git add <file>
git commit
```

Escape hatch: `git merge --abort`.

The ancestor (`:1`) is the one that settles arguments — it shows what *each side changed*, not merely
what each side now says.

---

## "Is it safe to publish?"

**Before any first push of any repository** (ADR-021):

```bash
git bundle create backup.bundle --all     # back up first
git bundle verify backup.bundle

bash scripts/macos/scan-history.sh        # ours: every blob, all refs
gitleaks git --log-opts="--all" -c .gitleaks.toml --redact
```

Exit 0 from `scan-history.sh` means no critical class matched. It does **not** mean there are no
secrets. Both scanners run, and disagreements get recorded.

Known limits, both confirmed on 2026-09-09:

- **gitleaks skips merge commits** — it scans diffs. It saw 34 of this repository's 38 commits.
- **`scan-history.sh` only knows the patterns it was given**, and only scans objects reachable from a
  ref. That is the right scope for a push, but not for what is on your disk.

If a credential is ever found **after** publication: **rotate it first.** Rewriting history is the
second action and does not un-disclose anything.

---

## "Where has the disk gone?" (inside `.git`)

| Question | Command |
|---|---|
| How big is the object database? | `git count-objects -vH` |
| Pack the loose objects | `git gc` |
| What are the biggest objects? | `git rev-list --objects --all \| git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \| sort -k3 -rn \| head` |

---

## Tags and releases

```bash
git tag -n                                   # list, with messages
git tag -a phase-05 -m "Phase 05 complete"   # ANNOTATED -- always use -a
git push origin --tags                       # tags are NOT pushed by git push
gh release create phase-05 --title "..." --notes "..."
```

This project tags **phases**, not versions — there is no released artefact to version. Lightweight
tags (`git tag <name>`, no `-a`) store only a pointer, with no tagger, date or message; avoid them
for anything meaningful.

---

## GitHub via `gh`

| Task | Command |
|---|---|
| Repository overview | `gh repo view` |
| …in the browser | `gh repo view --web` |
| Open a pull request | `gh pr create --base main --head <branch>` |
| List / view PRs | `gh pr list` / `gh pr view <n>` |
| Merge, keeping the merge commit | `gh pr merge <n> --merge` |
| Who am I, and with what scopes? | `gh auth status` |

`gh auth status` also prints the token's scopes. The token is a live credential in the macOS keyring;
it is never in the repository, and `scan-history.sh` looks for `ghp_`/`gho_` patterns in case.

### Adding a scope

When `gh` reports that an operation needs a scope, it names the **broadest** one that would work.
Check whether a narrower child scope covers what you actually need first:

```bash
gh auth refresh -h github.com -s read:user -s user:email
```

On 2026-09-09 `gh` suggested `-s user` for reading 2FA status and email visibility. `user` is a
parent scope that also grants `user:follow` — write access that can follow and unfollow people as
you. `read:user` and `user:email` are both read-only and were sufficient. Scopes accumulate and are
rarely reviewed afterwards, so the moment of adding one is the only moment you are likely to think
about it.

Scopes in use: `gist`, `read:org`, `read:user`, `repo`, `user:email`, `workflow`.

---

## Conventions in force

From `CONTRIBUTING.md`, and unchanged by Phase 04:

| Branch prefix | For |
|---|---|
| `feature/<name>` | unfinished implementation work |
| `docs/<name>` | documentation-only work |
| `experiment/<name>` | exploratory work that may be discarded |

Commit prefixes are **suggested, not mandatory**: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
`test:`. Actual usage across the first 38 commits: `docs:` ×25, `fix:` ×3, `feat:` ×3, `config:` ×1,
`chore:` ×1, plus 4 merges.

---

## What this project deliberately does not do

Recorded so a later phase does not assume it was overlooked:

- **No branch protection on `main`.** ADR-013 states the policy; nothing enforces it. A one-person
  project where an agent commits on the owner's behalf is a reasonable case *for* it — revisit when
  a second contributor exists.
- **No commit signing.** All 38 commits are unsigned.
- **No CI, no GitHub Actions, no issue templates.** There is nothing to run. `AGENTS.md` forbids
  adding infrastructure because it is common rather than needed.
- **No clone of this repository on the reference node.** Files are `scp`'d. A clone would put a
  credential on a console-less machine; Phase 05 is the first phase that would genuinely benefit.
