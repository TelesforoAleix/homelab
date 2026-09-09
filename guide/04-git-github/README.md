# 04 — Git & GitHub Fundamentals

## Goal

Be able to operate this repository yourself: read what a commit actually is, understand why the
project's four merge commits exist, resolve a conflict without panic, recover work you thought you
destroyed, and — before publishing anything — audit what you are about to disclose.

By the end you should be able to look at `git log --graph` for this project and read the story of how
it was built, rather than trusting that something sensible happened.

## Why this matters

This repository had **37 commits before this phase started, and none of them were made by you.**
They were made on your behalf. The conventions in `CONTRIBUTING.md` were written at bootstrap and
followed by an agent. `AGENTS.md` calls the repository "the canonical project memory" — and you could
not independently audit it.

There is a second, blunter reason. Until this phase, `git remote -v` was **empty**:

```console
$ git remote -v
$
```

Thirty-seven commits, every ADR, every guide, every build log, and the only record of how the
reference node was built existed in one `.git` directory on one MacBook. No remote, no backup, no
second copy anywhere.

That is a bigger single point of failure than the one the risk register has been tracking. Losing the
single SSH key loses **access to a machine you could rebuild**. Losing this directory loses **the
knowledge of how to rebuild it**, plus the reasoning behind every decision in it.

### What we are not doing

Not a git textbook. The rule from Phase 02 applies again: **a concept earns a place only if it
explains something this project has already done, or will do by Phase 05.** So there is a lot about
merges, conflicts and history, and nothing about submodules, `git bisect`, or rebasing onto upstream
forks. There are no `foo`/`bar` example repositories — every example is this project's real history.

## Reference-build choices

**1. Learn from this repository's own history.** Four real phases, four `--no-ff` merges, a
documentation-correction branch, 25 `docs:` commits. You watched these being made. That is better
teaching material than anything invented.

**2. Practise destruction in a disposable clone.** Phase 02 established that anything capable of
destroying something gets rehearsed on a sandbox, never the real thing. The git equivalent is a local
clone:

```bash
git clone /Users/home/Code/homelab /tmp/git-lab
```

A local clone is complete, instant, and free to ruin. Phase 02's three tiers map directly:

| Tier | Meaning here | Examples |
|---|---|---|
| **1 — Free** | Read-only inspection of the real repository | `log`, `show`, `diff`, `status`, `reflog`, `cat-file` |
| **2 — Sandboxed** | Anything destructive, in the scratch clone | conflicts, `reset --hard`, `rebase`, recovery, planted secrets |
| **3 — Not this phase** | Irreversible | force-push to published `main`, rewriting published history, deleting the remote |

**3. Audit before publishing, not after.** This is the one ordering that cannot be relaxed, and §"The
audit" explains why.

---

## 1. What git actually stores

Most confusion about git comes from one wrong belief: that a commit is a *change*. It is not. A commit
is a **complete snapshot**, plus pointers to what came before it.

Ask git directly. `cat-file -p` prints any object in the database:

```console
$ git cat-file -p HEAD
tree ca959ae6bf8f372c66e6db193bd8dab900a7de9e
parent c680033f597313740f9c090bc51d5a5d1edafaa5
author Aleix Moreno <160921106+TelesforoAleix@users.noreply.github.com> 1788962361 +0200
committer Aleix Moreno <160921106+TelesforoAleix@users.noreply.github.com> 1788962361 +0200

feat: audit the full history and license the repository for publication
...
```

Four things, and that is the whole of it:

- **`tree`** — the snapshot: a listing of every file and directory at that moment.
- **`parent`** — the commit that came before. This is what makes history a chain.
- **`author` / `committer`** — who, and when.
- **the message.**

The diffs you see in `git show` are **computed on demand** by comparing a commit's tree with its
parent's. They are not stored. This is why `git log -p` can be slow on a big repository and why
switching branches is instant: git is swapping snapshots, not replaying changes.

A commit's name is a hash of its content — including its parent's hash. Change anything anywhere in
the history and every commit after it gets a new hash. **That is why rewriting published history is
so disruptive: it does not edit commits, it replaces them with different ones.**

### A merge commit is the one with two parents

```console
$ git cat-file -p 0e26859 | head -3
tree b3ebec282ec92c8e9e451091e55b868b354f9470
parent 5804da6639f5d4081538ab53e8b7c699bcda2956
parent 109561d77af1f3c62f5631af5e641b6c0309a279
```

Two `parent` lines. That is the entire definition of a merge commit. Readably:

```console
$ git log -1 --format='commit  %h%nparents %p%nsubject %s' 0e26859
commit  0e26859
parents 5804da6 109561d
subject Merge Phase 02: operating the reference node
```

The first parent is where `main` was; the second is the branch that was merged in.

---

## 2. The three places a change can live

```
working tree  ──git add──▶  index (staging)  ──git commit──▶  HEAD (history)
```

- **Working tree** — the files on disk. What your editor sees.
- **Index / staging area** — what will go into the *next* commit. This is the step people skip and
  then find confusing.
- **HEAD** — the tip of the current branch: what is already committed.

The index exists so you can commit *part* of your work. `git add -p` walks you through each change
and asks whether to stage it — genuinely useful when you fixed two unrelated things and want two
commits.

Undoing at each level:

| You want to | Command |
|---|---|
| Unstage a file, keep the edits | `git restore --staged <file>` |
| Throw away edits to a file | `git restore <file>` *(destructive)* |
| See what is staged | `git diff --staged` |
| See what is not staged | `git diff` |

---

## 3. Branches, and why this project merges with `--no-ff`

A branch is a **file containing one commit hash**. That is all it is:

```console
$ cat .git/refs/heads/main
8e42570e79858901c992b31d5477333c662c1c1e
```

Forty-one bytes. This is why branching is instant and why you should branch freely.

`CONTRIBUTING.md` sets the names this project uses:

| Prefix | For |
|---|---|
| `feature/<name>` | unfinished implementation work |
| `docs/<name>` | documentation-only work |
| `experiment/<name>` | exploratory work that may be discarded |

### Fast-forward versus `--no-ff`

If `main` has not moved since you branched, git can merge by just **sliding the branch pointer
forward**. That is a *fast-forward*, and it leaves no merge commit — the history looks as though the
work was always on `main`.

This project refuses that, deliberately. Every phase merges with `--no-ff`, which forces a merge
commit even when a fast-forward was possible:

```console
$ git log --oneline --merges
8e42570 Merge documentation currency pass for Phases 01-03
0e26859 Merge Phase 02: operating the reference node
5804da6 Merge Phase 03: remote access on the reference node
77476eb Merge Phase 01: Ubuntu Server on the reference node
```

**Those four commits are the project's phase boundaries.** A fast-forward would have erased the fact
that a phase happened as a distinct unit of work. This is ADR-013 — `main` as a known-working state —
expressed in git: each merge commit is a point where the whole system was verified.

Note also the order. `5804da6` (Phase 03) comes *before* `0e26859` (Phase 02), because Phase 03 was
run first by choice. The history records what happened, not what the numbering suggests. That is
`PROJECT.md` §11 in practice: **do not rewrite history to make it look linear.**

---

## 4. Conflicts

A conflict is not an error. It is git declining to guess.

Git merges automatically when two branches changed *different* regions. When they changed the **same
lines**, it stops and shows you both, because picking one is a decision only you can make.

Created deliberately in the scratch clone — two branches editing line two of the same file:

```console
$ git merge side-branch
Auto-merging conflict-demo.txt
CONFLICT (content): Merge conflict in conflict-demo.txt
Automatic merge failed; fix conflicts and then commit the result.
```

What git writes into the file:

```text
line one
<<<<<<< HEAD
line two, edited on main
=======
line two, edited on side-branch
>>>>>>> side-branch
line three
```

Reading the markers:

- `<<<<<<< HEAD` to `=======` — **your** side, the branch you are on.
- `=======` to `>>>>>>> side-branch` — **their** side, the branch being merged in.

Git also keeps all three versions accessible while the conflict is open, which is far more useful
than most people realise:

```console
$ git show :1:conflict-demo.txt   # the common ancestor
line two
$ git show :2:conflict-demo.txt   # ours (main)
line two, edited on main
$ git show :3:conflict-demo.txt   # theirs (side-branch)
line two, edited on side-branch
```

The ancestor is the one that resolves arguments: it tells you what **each side changed**, not just
what each side says.

### Resolving

There is no special command. You edit the file until it is correct — deleting all three marker lines
— then:

```bash
git add conflict-demo.txt
git commit          # message is pre-filled
```

`git status` tracks it for you:

```console
$ git status --short
UU README.md
```

`UU` means "both sides modified". And the escape hatch, which is why practising in a clone is safe:

```bash
git merge --abort   # forget the whole thing, back to before the merge
```

---

## 5. `.gitignore` does not protect a committed secret

This is the single most misunderstood thing in git, and in this repository it is a **security
control**, so it gets its own section and a full worked example.

**`.gitignore` only stops git tracking files it is not already tracking. It is not retroactive, and
it never removes anything.**

Watch it fail. All output below is real, from the scratch clone:

```console
$ echo "SECRET_TOKEN=pretend-this-is-real" > oops.env
$ git add oops.env && git commit -m "accidentally commit a secret"
```

Now you notice, and do the instinctive thing:

```console
$ echo "oops.env" >> .gitignore
$ git add .gitignore && git commit -m "add oops.env to .gitignore"
```

Everything *looks* fine:

```console
$ git status --short
$                       # silence. nothing wrong, apparently.
```

But:

```console
$ git ls-files | grep oops.env
oops.env                # STILL TRACKED. .gitignore did nothing.

$ git log --oneline -S 'SECRET_TOKEN' --all
3d06f66 accidentally commit a secret
```

The actual fix for tracking is `git rm --cached`, which stops tracking without deleting your file:

```console
$ git rm --cached oops.env && git commit -m "stop tracking oops.env"
$ git ls-files | grep -c oops.env
0
```

**And the secret is still in history:**

```console
$ git log --oneline -S 'SECRET_TOKEN' --all
37fdc6a stop tracking oops.env
3d06f66 accidentally commit a secret
```

Removing a file from the tip does not remove it from history. Anyone who clones gets every version of
every file ever committed. This is why the audit below scans **objects**, not files — and why, if a
real credential is ever exposed, **rotating it comes first** and rewriting history second.

`git log -S <string>` is the tool for this question. It searches for commits that changed the number
of occurrences of a string — the fastest way to ask "when did this text enter the repository?"

---

## 6. Remotes and publication

A remote is a named URL. `origin` is a convention, not a keyword.

```console
$ git remote -v
origin  https://github.com/TelesforoAleix/homelab.git (fetch)
origin  https://github.com/TelesforoAleix/homelab.git (push)
```

The thing worth internalising: **`origin/main` is a local cache**, not a live view of the server. It
updates only when you `fetch` or `pull`. If it looks stale, it is stale.

| Command | Does |
|---|---|
| `git fetch` | Download new commits, update `origin/*`. **Changes nothing of yours.** Always safe. |
| `git pull` | `fetch` **plus** merge into your branch. Can conflict. |
| `git push` | Upload your commits. |
| `git push -u origin <branch>` | Push and remember the pairing, so later `git push` needs no arguments. |

When unsure, `fetch` then look, then decide. `pull` is two operations wearing one name.

### Publication is irreversible

Publishing is the one action in this phase that cannot be undone:

- A public repository can be cloned, forked, cached and indexed within minutes.
- Deleting it later removes **your** copy. It does not retract the disclosure.
- Rewriting history to remove a secret **before** the first push costs nothing. Afterwards it
  invalidates every clone, needs a forced update, and still un-discloses nothing.

This is the same shape as ADR-020's reasoning about the console-less node — some actions have no
undo — but a completely different mechanism. ADR-020 is about losing access to a machine. This is
about losing control of information. Do not merge the two in your head; the precautions differ.

**The consequence is an ordering rule: audit, fix, then publish. Never the other way round.**

---

## 7. The audit

Before the first push, run `scripts/macos/scan-history.sh`. It scans **every blob reachable from
every ref** — which is exactly the set `git push` transfers.

```console
$ bash scripts/macos/scan-history.sh
Objects reachable from all refs: 397
Of which file contents (blobs):  220
Binary blobs skipped:            0
Blobs actually searched:         220  (1351206 bytes)

Pattern classes
---------------
  private keys                       clean
  SSH public keys                    clean
  Tailscale auth keys                clean
  ...
  private (RFC1918) addresses        40 matches -- review
          38 192.168.1.57
```

Two rules that came out of building it, both learned the hard way (see the experience section):

**Run two independent scanners.** This project uses its own script plus `gitleaks`. They disagreed in
both directions, which was more informative than agreement: gitleaks flagged the word `RAG` in
ordinary prose as an API key, and gitleaks **scanned 34 of this repository's 38 commits** because it
scans diffs and skips merge commits. Two tools built on different assumptions are wrong in different
places.

**Adjudicate the borderline categories in writing.** The scan flags things that may or may not be
secret; only you can decide. This project's verdicts, recorded in the build log:

| Finding | Verdict | Why |
|---|---|---|
| `192.168.1.57` and similar | publish | RFC 1918, not routable from the internet |
| `100.71.62.71` and similar | publish | Tailscale CGNAT, reachable only inside the tailnet |
| `/home/aleix/` | publish | **conditional** — harmless only because SSH takes no passwords |
| SHA256 checksums | publish | checksums exist to be published |
| the **tailnet name** | **withhold** | an account-linked identifier — redacted as `<tailnet>` throughout |

Note the pair: the tailnet **address** is published, the tailnet **name** is not. And note that the
username verdict is explicitly conditional. **The sensitivity of a fact depends on the controls around
it, not on the fact.** If password authentication were ever re-enabled, a published admin username
would change from harmless to material.

### Before anything risky, take a bundle

`git bundle` writes an entire repository into one file. It is the correct offline backup and the best
answer to "what if I break something":

```console
$ git bundle create backup.bundle --all
$ git bundle verify backup.bundle
The bundle records a complete history.
```

303 KB for this whole project. You can `git clone backup.bundle` from it like any remote.

---

## 8. Pull requests

**A pull request is not a git feature.** Git has no concept of one. It is a GitHub product built on
top of two ordinary things: a branch, and a merge.

Knowing where that line falls prevents a lot of confusion — `git pull-request` does not exist, and no
amount of reading git's manual will explain PR review, because it is not in there.

What a PR adds is a place to review before merging, and a durable record of *why* a change was
accepted. For a one-person project with an agent committing on its behalf, the second is the real
value: the PR description is where the reasoning lives.

```bash
git push -u origin feature/04-git-github
gh pr create --base main --head feature/04-git-github --title "..." --body "..."
gh pr view --web        # look at it
gh pr merge --merge     # --merge keeps the merge commit; --squash and --rebase do not
```

Use `--merge`, not `--squash`. Squashing would collapse a phase into one commit and discard exactly
the history this project keeps on purpose.

---

## 9. Tags and releases

A **tag** is a name for a commit. A **release** is a GitHub page built on a tag.

Two kinds of tag, and the difference matters:

| Kind | Command | Stores |
|---|---|---|
| Lightweight | `git tag phase-01` | just a pointer |
| **Annotated** | `git tag -a phase-01 -m "..."` | pointer **plus** tagger, date, message — a real object |

Use annotated tags for anything meaningful. They can be signed, they record who tagged and when, and
`git describe` prefers them.

This project tags **phases**, not versions. There is no released artefact to version, and semantic
versioning would be pretending otherwise. The meaningful unit here is "the state at which a phase was
declared complete", which is exactly what the four merge commits are.

Tags are not pushed by `git push`. Push them explicitly:

```bash
git push origin --tags
```

---

## 10. Recovery: the reflog

Almost every "I lost work" in git is false. Git records **every movement of `HEAD`** in the reflog,
including the ones you made by accident.

Destroyed and recovered, in the scratch clone:

```console
$ git commit -m "work I would hate to lose"
$ git rev-parse HEAD
ab3c7862fdbff49c83561e4bf78cbf59d7d1e6ca

$ git reset --hard HEAD~1
$ ls valuable.txt
ls: valuable.txt: No such file or directory
```

Gone from the branch and from disk. But:

```console
$ git reflog -5
fc76617 HEAD@{0}: reset: moving to HEAD~1
ab3c786 HEAD@{1}: commit: work I would hate to lose
fc76617 HEAD@{2}: reset: moving to HEAD
fc76617 HEAD@{3}: commit: edit line two on main
b9287b1 HEAD@{4}: checkout: moving from side-branch to main
```

`HEAD@{1}` is the commit that was just thrown away. Recovering it is one command:

```console
$ git reset --hard ab3c7862fdbff49c83561e4bf78cbf59d7d1e6ca
$ cat valuable.txt
important work
```

The hash matches exactly. Nothing was lost, because **a commit is not deleted when a branch stops
pointing at it** — it is merely unreferenced, and git keeps unreferenced objects for around 90 days
before garbage collection.

This is what makes git safe to experiment with. Two caveats:

- The reflog is **local and private**. It is not pushed and not cloned. Your reflog cannot rescue
  someone else's mistake.
- It only covers things that were **committed**. Uncommitted changes destroyed by `git restore` or
  `git reset --hard` are genuinely gone. Commit early; commits are cheap and recoverable, working
  trees are not.

---

## 11. What is actually inside `.git`

Before this phase, this repository had never been garbage-collected: 453 loose objects, zero packs.
Every object was its own file on disk.

```console
$ git count-objects -vH
count: 512
size: 2.30 MiB
in-pack: 0
packs: 0

$ git gc
$ git count-objects -vH
count: 5
size: 20.00 KiB
in-pack: 507
packs: 1
size-pack: 340.02 KiB
```

2.30 MiB to 340 KiB. Git stores objects loose for speed while you work, then packs them with delta
compression — storing similar objects as differences from one another. Note the irony worth
remembering: git does not store commits as diffs, but it *does* compress storage using diffs. The
data model and the storage format are separate things.

`git gc` runs automatically now and then. You rarely need to call it.

---

## 12. Repository hygiene

Small things, done once:

- **A description and topics** so the repository is findable and its purpose is obvious.
- **Delete merged branches** — or keep them deliberately. This project keeps the phase branches,
  because they are a visible record of the phase structure and they cost nothing.
- **Licence.** Not optional. Without one, default copyright reserves all rights, so nobody may
  legally reuse anything — the opposite of what this repository's README invites. "No licence" is not
  a neutral deferral; it is a restrictive choice made by accident.

This project uses two: **MIT** for `scripts/` and other code, **CC BY-SA 4.0** for `guide/`, `docs/`
and the root Markdown. About 80 files of prose and 8 shell scripts; MIT is written about software, and
applying it alone to a written guide leaves attribution and derivative works ambiguous. See ADR-021.

---

## 13. How to verify it worked

```bash
git rev-parse main && git rev-parse origin/main    # must be identical
git rev-list --merges --count origin/main          # phase boundaries survived
gh repo view --json visibility,url
git tag -n                                          # annotated tags with messages
bash scripts/macos/scan-history.sh                  # exit 0 = no critical findings
git bundle verify backup.bundle
```

---

## 14. What can go wrong

| Symptom | Cause | Fix |
|---|---|---|
| `git status` clean but a secret is still tracked | `.gitignore` is not retroactive | `git rm --cached <file>`; the history still holds it |
| Pushed a secret | history is public now | **Rotate the credential first.** History rewriting is second |
| `git push` rejected, "fetch first" | remote moved on | `git fetch`, look, then merge or rebase |
| Merge produced no merge commit | fast-forward | `git merge --no-ff` |
| Tags missing on GitHub | `git push` does not push tags | `git push origin --tags` |
| "I lost a commit" | branch moved, commit still exists | `git reflog`, then `git reset --hard <hash>` |
| Scanner reports clean | may mean it searched nothing | check *how much* it searched; see below |

---

## 15. What the reference build actually hit

Four failures. All are recorded in
[`docs/build-log/2026-09-09-phase-04-audit.md`](../../docs/build-log/2026-09-09-phase-04-audit.md);
the two that generalise beyond git are worth reading even if you never publish anything.

**1. The scan reported all sixteen classes clean because it had searched nothing.** The first run
printed `Binary blobs skipped: 213` out of 213 blobs. Every blob was classified binary, the corpus
was empty, and every class reported clean because there was nothing to search. The cause: the binary
test was `grep -qU $'\x00'`, and **a NUL byte cannot survive being passed to grep as a pattern** —
arguments are C strings, so the pattern arrived empty, and an empty pattern matches everything.

**2. The scanner matched its own documentation.** Two CRITICAL "tailnet name" findings turned out to
be `*.ts.net` appearing as literal pattern text in this phase's own brief, committed an hour earlier.
Fixed by requiring a real hostname before `.ts.net`, which tightens the check — not by excluding the
file, which would have weakened it.

**3. gitleaks silently skipped every merge commit.** It reported `34 commits scanned`. The repository
had 38 commits and exactly 4 merges. It scans diffs, and a merge commit has no diff of its own.
Nothing was missed here, because `--no-ff` merges of already-scanned branches add no content — but if
someone had resolved a conflict *inside* a merge commit, that resolved content would exist only
there.

**4. The private-key check could not run, and reported clean.** The most important lesson in the
phase, and it was only found by deliberately planting fake secrets in the scratch clone and checking
that the scanner fired. Five of six were caught. The private-key class — the one that exists to catch
an actual SSH key — said `clean`. A PEM header starts with dashes, so **grep parsed the pattern as
command-line options**:

```console
$ grep -n -E "$pat" keytest.txt
grep: unrecognized option `-----BEGIN [A-Z ]*PRIVATE KEY-----'
$ echo $?
2
```

Two mistakes compounded: the pattern needed `-e`, and `2>/dev/null` discarded the error while the
code treated **grep exit 2 (error)** exactly like **exit 1 (no match)**. A check that could not run
reported that it had run and found nothing.

### The pattern across four phases

| Phase | Check | How it failed |
|---|---|---|
| 03 | `sshd -T` | Read the config file, not the running daemon |
| 02 | `who` | Reported zero sessions, exit 0, on a machine with six |
| 04 | binary detection | Skipped all 213 blobs, reported clean |
| 04 | private-key pattern | Could not run at all, reported clean |

Every one of them **fails by returning nothing and looking like success.** `scripts/README.md`
already carried the rule — *a check that cannot determine an answer must say unknown, never a
plausible-looking zero* — and the fourth was written by the same hand that wrote the rule, one phase
earlier. Knowing a failure mode does not confer immunity to it.

**The habit worth taking from this phase:**

> A detector that has only ever reported "clean" is unvalidated. It has been shown it can say *fine*;
> it has never been shown it can say *not fine*. Plant a positive case somewhere disposable and make
> it fire.

That applies far beyond git — to monitoring, alerting, backups and health checks. A backup you have
never restored is not a backup, for exactly the same reason.

One more, of a different kind: the `README.md` on this repository's front page still announced
**"Phase 00 — Repository Bootstrap"** as the current status, three phases later. A documentation
currency pass one phase earlier had checked `docs/` and `guide/` and never looked at the front door.
It was corrected an hour before the repository became public.

---

## Command summary

| Question | Command |
|---|---|
| What is this commit, really? | `git cat-file -p HEAD` |
| What is the shape of history? | `git log --graph --oneline --all` |
| Where are the phase boundaries? | `git log --oneline --merges` |
| What changed, and is it staged? | `git diff` / `git diff --staged` |
| When did this text enter the repo? | `git log -S '<string>' --all` |
| Is this file actually tracked? | `git ls-files \| grep <name>` |
| Stop tracking without deleting | `git rm --cached <file>` |
| What are the two sides of this conflict? | `git show :2:<file>` / `git show :3:<file>` |
| Get me out of this merge | `git merge --abort` |
| I destroyed something | `git reflog`, then `git reset --hard <hash>` |
| Back everything up to one file | `git bundle create backup.bundle --all` |
| Is it safe to publish? | `bash scripts/macos/scan-history.sh` |
| What is in `.git`? | `git count-objects -vH` |
