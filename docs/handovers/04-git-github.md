# Phase 04 Brief — Git & GitHub Fundamentals

- **Date:** 2026-09-09
- **Phase:** 04 — Git & GitHub Fundamentals
- **Author:** the Phase 04 context
- **Status:** Accepted, self-ratified under ADR-017
- **Previous handover:** [`02-linux-fundamentals-handover.md`](02-linux-fundamentals-handover.md)

## 0. Governance note

Under ADR-017 there is no Project Planning context to ratify this brief. It is written and committed
**before implementation begins**, which is the first of the three compensating controls ADR-017
makes mandatory. Its value is as a specification. A brief written afterwards would be a narrative.

This is the third consecutive phase to write its own brief first. The practice is now routine.

### Three scope decisions taken with the owner before writing

Asked and answered on 2026-09-09, because all three materially change what gets built:

1. **Visibility: public from the first push.** Not private-then-public-later, and not local-only.
   This is the most consequential of the three, because it converts a documentation exercise into an
   irreversible disclosure event and pulls a full-history secrets audit into the critical path.
2. **Licensing: MIT for code, CC BY-SA 4.0 for documentation.** Not a single MIT file. The
   repository is 79 Markdown files and 8 shell scripts; a code licence alone would misdescribe it.
   The cost is one extra paragraph explaining which licence covers what.
3. **Identity: `TelesforoAleix/homelab`.** Matches the local directory, `PROJECT.md`, and the default
   already assumed in `docs/reference/project-state.md`.

These close two of the four **known unknowns** carried since bootstrap — "public repository license"
and "final GitHub repository owner/name". `project-state.md` must be updated to say so.

### A note on sequencing

Phase 04 is being run in its numbered position, after Phase 02 and Phase 03. No renumbering.

## 1. Purpose

This repository has had 37 commits, four feature branches and four `--no-ff` merges since bootstrap.
None of that was taught. The conventions in `CONTRIBUTING.md` were written at bootstrap and have been
followed *by an agent*, on the owner's behalf, without the owner ever having resolved a conflict,
inspected a merge, or recovered a lost commit. The repository is the project's canonical memory
(`AGENTS.md`), and the owner cannot currently audit it independently.

This phase exists to close three gaps, in descending order of consequence:

1. **The project's entire memory exists on exactly one disk.** Thirty-seven commits, every ADR, every
   guide, every build log, and the only record of how the reference node was built, live in one
   `.git` directory on one MacBook with no remote and no backup. This is quietly the largest single
   point of failure in the project — larger than the single SSH key, because the SSH key only loses
   access to a machine that can be rebuilt, whereas this loses the *knowledge of how to rebuild it*.
2. **The owner cannot yet operate git without an agent.** Every phase from here on produces commits.
   Phase 05 onward will produce them faster.
3. **Publication is a security event that has not yet happened.** The repository was always intended
   to be public. It has never been audited as though it were about to be.

There is also a timing argument. **Nothing has ever been pushed**, so history is still private and
still cheap to rewrite. Every day the repository stays unpublished, that stays true; the moment it is
pushed, it stops. If the audit in §7.2 finds anything, this is the only phase in which fixing it is
free. That ordering — audit, then fix, then publish — is not negotiable within this phase.

## 2. Starting state

Verified from live output on 2026-09-09 at phase start.

### The repository

| Fact | Value |
|---|---|
| Path | `/Users/home/Code/homelab` |
| Branch | `main`, clean, 0 uncommitted changes |
| HEAD | `8e42570` — "Merge documentation currency pass for Phases 01-03" |
| Commits | **37** |
| Merge commits | 4 — `8e42570`, `0e26859` (Phase 02), `5804da6` (Phase 03), `77476eb` (Phase 01) |
| First commit | `c85ac11` — "chore: bootstrap Home Lab repository" |
| Local branches | `main`, `feature/01-ubuntu-server`, `feature/02-linux-fundamentals`, `feature/03-remote-access`, `docs/phase-01-03-currency` |
| Unmerged branches | **none** — all four are fully merged into `main` |
| **Remotes** | **none.** `git remote -v` is empty. Nothing has ever been pushed |
| Tags | **0** |
| Tracked files | 97 — 79 `.md`, 8 `.sh`, 2 `.yaml`, 2 `.json`, plus `.editorconfig`, `.gitignore`, a `.service`, a `.conf`, a `.txt` and one `.example` |
| Repository size | `.git` 2.2 MB; **453 loose objects, `size-pack` 0 bytes** — never packed or garbage-collected |
| Largest tracked file | `guide/02-linux-fundamentals/README.md`, 36 KB |
| Author identity | `Aleix Moreno <160921106+TelesforoAleix@users.noreply.github.com>` on **all 37** commits |
| Committer identity | identical on all 37 |
| `init.defaultBranch` | `main` |
| `pull.rebase` | unset |
| `commit.gpgsign` | unset — **no commits are signed** |
| Licence file | **none** |
| `.gitattributes` | **none** |
| `.github/` | contains only `README.md`, a placeholder saying templates and workflows come later |

Commit subject prefixes actually used: `docs:` ×25, `fix:` ×3, `feat:` ×3, `config:` ×1, `chore:` ×1,
plus the 4 merges. The `CONTRIBUTING.md` prefix list is being followed.

### Local environment (MacBook)

| Fact | Value |
|---|---|
| git | 2.39.5 (Apple Git-154) |
| `gh` CLI | 2.90.0, at `/opt/homebrew/bin/gh` |
| `gh` authentication | **Already logged in** to github.com as **`TelesforoAleix`**, token in the macOS keyring |
| `gh` token scopes | `gist`, `read:org`, `repo`, `workflow` |
| `gh` git protocol | `https` |

The push is therefore **mechanically possible today**. Nothing technical is blocking it; the only
thing standing between this repository and publication is the audit in §7.2. That is the correct
order and this brief exists partly to keep it that way.

### Preliminary secrets sizing (not the audit)

A first pass across **all** 453 objects in history, counting blob hits only:

| Pattern | Blob hits |
|---|---|
| `BEGIN … PRIVATE KEY` | 0 |
| `ssh-ed25519 AAAA` | 0 |
| `ssh-rsa AAAA` | 0 |
| MAC address (`xx:xx:xx:xx:xx:xx`) | 0 |
| `tskey-` (Tailscale auth key) | 0 |
| the owner's personal email domain | 0 |
| `*.ts.net` | **59** |

The 59 `.ts.net` hits resolve to exactly three distinct strings, all placeholders:
`homelab.<tailnet>.ts.net` (55), `homelab.CHANGE-ME.ts.net` (14), `<tailnet>.ts.net` (12). **No real
tailnet name appears anywhere in history.** Phase 03's tightening held.

> This is a *sizing* pass, not the audit. It proves the obvious categories are clean and that the
> audit is unlikely to force a history rewrite. It does not discharge §7.2, which must run a broader
> pattern set and an independent second tool. A scan that only looks for what you already thought of
> is a scan that confirms your assumptions.

### The reference node

**Out of scope.** This phase does not touch the server. The end state recorded in
[`02-linux-fundamentals-handover.md`](02-linux-fundamentals-handover.md) §2 stands unmodified. The
Definition of Done's system-health item is still applied literally, by re-checking at phase close
(§8.14) — the point of that item is to catch damage a phase did not intend, and "I did not intend to
touch it" is exactly the claim it exists to test.

## 3. Learning objectives

By the end of this phase the owner should be able to explain, without an agent present:

1. **What a commit is** — a snapshot plus one or more parent pointers, identified by a hash over its
   content, *not* a diff. And why that makes a branch a 41-byte file rather than a copy.
2. **The three places a change can live** — working tree, index, `HEAD` — and why `git add -p` and
   `git restore --staged` exist.
3. **Why this project merges with `--no-ff`** and what a fast-forward would have destroyed. The four
   merge commits are the phase boundaries; a fast-forward would erase the fact that a phase happened.
   This is ADR-013 (`known-working main`) expressed in git.
4. **What a conflict actually is** — git showing both parents' versions of a region it will not guess
   about — what the `<<<<<<<`/`=======`/`>>>>>>>` markers delimit, and that resolution is ordinary
   editing followed by `git add`.
5. **Remotes and tracking branches** — that `origin/main` is a *local* cache of a remote ref,
   why `fetch` is safe and `pull` is not always, and what `push` actually transfers.
6. **That a pull request is not a git feature.** It is a GitHub product. Git has no concept of it.
   Knowing where the line is prevents a whole category of confusion.
7. **Tags and releases** — annotated vs lightweight, that a tag is a pointer to a commit, and that a
   GitHub Release is a GitHub object built on top of a tag.
8. **The `.gitignore` trap** — `.gitignore` only affects **untracked** files. Adding a
   already-committed secret to `.gitignore` does nothing at all. This is the single most commonly
   misunderstood thing in git and it is a security control in this repository.
9. **That publication is irreversible.** Deleting a public repository does not retract it: it may
   already be cloned, forked, cached or indexed. Rewriting history before the first push is free;
   after it, it is a coordination problem plus a disclosure you cannot recall.
10. **`git reflog`** — the mechanism that makes git safe to experiment with, and why "I lost a commit"
    is almost never true.

## 4. Functional objectives

What must work at phase close. Each maps to a validation check in §8.

1. A **full-history secrets audit** has run, with two independent tools, and its output is recorded —
   **before** any push. Findings, including "none", are recorded with the patterns searched.
2. **`LICENSE`** (MIT) and **`LICENSE-docs`** (CC BY-SA 4.0) exist, with a `README.md` section stating
   unambiguously which covers what.
3. The GitHub repository **`TelesforoAleix/homelab`** exists, is **public**, and carries the complete
   37-commit history with all four merge commits intact.
4. `main` on the remote and `main` locally point at the same commit, verified by hash.
5. **At least one pull request** has been opened, reviewed and merged — for this phase's own work,
   not a toy.
6. A **merge conflict has been deliberately created and resolved** by hand, in the scratch clone.
7. **Annotated tags** mark the completed phases, and **one GitHub Release** exists.
8. `.gitignore` has been reviewed against the real repository, tightened where needed, and the
   "already-tracked file is not protected" trap demonstrated with real output.
9. **Repository hygiene** is in place: description, topics, and a decision recorded on branch
   protection and on the default `main` branch's status.
10. A **recovery exercise** has been performed: a commit "lost" by `git reset --hard` and recovered
    via `git reflog`, in the scratch clone.
11. The repository has a **backup that is not the working copy** — at minimum the GitHub remote, plus
    a `git bundle` proving the owner can produce an offline single-file copy.

## 5. Decisions already fixed

Inherited, and not reopened by this phase:

| Source | Constraint |
|---|---|
| **ADR-013** | `main` represents a known-working state. Phase work happens on a branch and merges with `--no-ff`. |
| **ADR-017** | Self-contained sequential phases; brief committed before implementation; handover addressed to the next phase. |
| **ADR-020** | Change-safety standard for the console-less node. **Low relevance here** — this phase changes the repository, not the node — but see §9.1 for the *analogous* irreversibility argument, which is not the same thing and must not be conflated. |
| **`CONTRIBUTING.md`** | Branch names (`feature/`, `experiment/`, `docs/`) and optional commit prefixes. Already followed; this phase makes them understood rather than replacing them. |
| **`AGENTS.md`** | Never commit secrets, tokens, passwords, private keys, or personal data. |
| **Owner's standing constraint** | Never commit secrets, the Wi-Fi passphrase, or MAC addresses. |
| **`PROJECT.md` §11** | "Do not rewrite project history to make it look linear." See §5.1 — this needs stating precisely, because this phase may rewrite git history. |

### 5.1 The one place §11 and this phase could appear to collide

`PROJECT.md` §11 forbids rewriting **project history** to make it **look linear** — that is a rule
about narrative honesty. It requires that failures, reversals and wrong turns stay visible.

If the §7.2 audit finds a real secret, removing it from git history is a **security action**, not a
tidying action, and §11 does not forbid it. But §11 does govern how it is reported: the removal must
be recorded in the build log with the four elements §11 requires — assumption, what happened, what
was learned, what changed — naming the class of exposure and the remediation. Quietly rewriting
history and saying nothing would violate §11 exactly. Rewriting it and documenting it does not.

The sizing pass in §2 suggests this is unlikely to be needed. It is specified so that if it *is*
needed, the phase does not have to invent a policy under pressure.

## 6. Decisions still open

To be resolved inside the phase and recorded:

1. **Tag scheme.** Proposed: annotated tags `phase-01`, `phase-02`, `phase-03` on the four
   corresponding merge commits, applied retroactively, because this project's meaningful units are
   phases rather than software versions. Semantic versioning is the obvious alternative and is a poor
   fit — there is no released artefact to version. Decide and record.
2. **Which commit gets the GitHub Release**, and whether releases are per-phase from here on.
3. **Branch protection on `main`.** Available on free public repositories. A one-person project with
   an agent committing on its behalf is exactly the case where a rule that forbids direct pushes to
   `main` has value — but it also blocks the owner's own recovery. Decide, record the reasoning, and
   note that ADR-013 already asserts the *policy*; this would be the *enforcement*.
4. **Commit signing.** Currently unsigned. A public repository under a named identity makes signing
   meaningful. Likely deferred with a recorded reason rather than adopted here.
5. **Whether the reference node gets a clone of this repository.** Currently files are `scp`'d to the
   server one at a time. A clone would be more convenient and introduces a credential question on a
   machine with no console. **Presumption: out of scope**, recorded for Phase 05, which is the first
   phase that would genuinely benefit.
6. **Whether the stale merged branches are deleted.** Four local branches are fully merged. Deleting
   them is normal hygiene; keeping them is a visible record of the phase structure. Decide once and
   record — this is a small decision that is worth making explicitly because the answer differs
   between projects.
7. **Whether `.github/` gains issue templates or a workflow.** Presumption: **no**. `AGENTS.md`
   forbids adding infrastructure because it is common rather than needed, and there is no CI to run.
   Record the refusal so a later phase does not assume it was overlooked.

## 7. Implementation scope

Expected work. Exact commands emerge during execution.

### 7.1 The practice environment — a scratch clone

Phase 02 established that anything capable of destroying something gets rehearsed on a disposable
copy. The direct analogue here is a **local scratch clone**:

```
git clone /Users/home/Code/homelab <scratchpad>/git-lab
```

A local clone is cheap, complete, and utterly disposable. All destructive and exploratory practice —
conflicts, `reset --hard`, `rebase`, `reflog` recovery, force-pushing between the clone and its
origin — happens there. The real repository sees only ordinary, reviewed work.

Mapped onto Phase 02's tiers, so the method carries forward rather than being reinvented:

| Tier | Meaning here | Examples |
|---|---|---|
| **1 — Free** | Read-only inspection of the real repository | `log`, `show`, `diff`, `status`, `reflog`, `cat-file`, `ls-files` |
| **2 — Sandboxed** | Anything destructive, in the scratch clone | conflict creation and resolution, `reset --hard`, `rebase`, `revert`, recovery, force-push |
| **3 — Not this phase** | Irreversible or out of scope | force-push to published `main`, history rewrite after publication, deleting the remote, granting collaborator access |

### 7.2 The audit — before anything is pushed

This is the gate. Nothing is pushed until it has run and its output is recorded.

- Write **`scripts/macos/scan-history.sh`**: a readable, hand-rolled scan across every object in
  `git rev-list --all`, not just the working tree. It is a teaching artefact as much as a control —
  the owner must be able to read it and understand what it does and does not cover. It must state
  its own limits in its header, as `preflight.sh` does.
- Pattern classes: private keys; SSH public keys; MAC addresses; Wi-Fi passphrases and `psk`
  fields; Tailscale auth keys and real tailnet names; API tokens (`ghp_`, `gho_`, `github_pat_`,
  `sk-`, `xoxb-`); the owner's personal email addresses; hardware serial numbers; absolute paths
  containing the owner's home directory; and high-entropy strings as a catch-all.
- **Run one independent third-party scanner as a cross-check** (`gitleaks` is the obvious choice).
  Two tools that disagree is a finding worth recording; two tools that agree is worth more than one
  tool that is confident. This mirrors `download-ubuntu-iso.sh`, which verifies two ways for the same
  reason.
- **Make an explicit, recorded judgement on the borderline categories** rather than leaving them
  implicit: the LAN address `192.168.1.57` (RFC 1918), the tailnet address `100.71.62.71` (CGNAT,
  reachable only inside the tailnet), the username `aleix`, and the hostname `homelab`. These are
  already committed and are arguably not secrets. Say so deliberately, with reasoning, or remove
  them — but do not publish having never considered them.
- Take a **`git bundle`** of the full history before any operation that could alter it. A bundle is a
  single-file clone, which is both the correct backup and a good lesson.

### 7.3 Licensing

- `LICENSE` — MIT, covering `scripts/`, `config/`, `infrastructure/`, `services/` and any other code.
- `LICENSE-docs` — CC BY-SA 4.0, covering `guide/`, `docs/`, and the root Markdown files.
- A **Licence** section in `README.md` stating the split in two sentences, with the boundary drawn by
  directory so it is unambiguous. Copyright line: `Aleix Moreno`.
- Note in the build log *why* a split was chosen, so it reads as a decision rather than an accident.

### 7.4 Publication

- Create `TelesforoAleix/homelab` as **public**, with a description and topics.
- Push `main` and establish upstream tracking.
- Verify the GitHub account's own security posture before the repository is public: **2FA enabled**,
  and the "keep my email address private" / "block command line pushes that expose my email" settings
  checked. The commits already use the noreply address, but the setting is what keeps that true.
- Decide the fate of the four merged local branches (§6.6) and whether they are pushed.
- Apply the tag scheme and cut one Release.

### 7.5 The learning work

Exercises against the real history where reading suffices, and in the scratch clone where changing
is required. The syllabus is the roadmap line, taken literally:

**commits** · **branches** · **merges** · **pull requests** · **conflict handling** ·
**tags/releases** · **`.gitignore`** · **repository hygiene**

The strongest available teaching material is this repository's own history: four real phases, a
documentation-correction branch, 25 `docs:` commits and 4 deliberate `--no-ff` merges. Explain git
using commits the owner watched being made, not an invented `foo/bar` repository — this is the same
principle that made Phase 02's guide work.

Specific exercises expected to earn their place:

- Read a real merge commit with `git show --stat` and `git log --graph`, and identify both parents.
- Demonstrate the `.gitignore` trap: commit a file, add it to `.gitignore`, prove with `git status`
  and `git ls-files` that it is still tracked, then fix it properly with `git rm --cached`.
- Create a genuine conflict in the scratch clone by editing the same lines on two branches.
- `git reset --hard` a commit away, then recover it from the reflog.
- Inspect a commit as an object: `git cat-file -p HEAD` to show the tree, parent and author lines.
- Run `git gc` and observe 453 loose objects become a pack — a concrete answer to "what is `.git`".

### 7.6 Documentation

- `guide/04-git-github/README.md` — the main human-facing deliverable, with real captured output.
- `docs/reference/git-workflow.md` — the operational counterpart: the commands this project actually
  uses, in the order a phase uses them, as `linux-command-reference.md` is for the shell.
- Update `CONTRIBUTING.md` where the phase's decisions change it (tags, releases, branch fate).

## 8. Validation / tests

Every check produces real output, recorded. Nothing is marked passing without it.

1. `scan-history.sh` runs across all objects in `git rev-list --all` and its output is captured.
2. The independent third-party scanner runs; agreement or disagreement with (1) is recorded.
3. Borderline categories (§7.2) have a written, reasoned verdict — not silence.
4. `git bundle verify` succeeds on the pre-publication bundle.
5. `LICENSE` and `LICENSE-docs` exist; `README.md` states the split; the boundary is by directory.
6. `gh repo view TelesforoAleix/homelab` reports the repository exists and `visibility: public`.
7. `git rev-parse main` and `git rev-parse origin/main` return the **same hash**.
8. `git log --oneline --merges` on the pushed repository still shows **all four** merge commits —
   proving the phase history survived publication intact.
9. `git rev-list --count origin/main` returns the expected commit count.
10. One pull request exists in a merged state, referencing this phase's work.
11. A conflict was created and resolved in the scratch clone, with the marker text captured before
    resolution and the resolved result shown after.
12. `git tag -n` lists the annotated tags with their messages; `gh release view` shows the Release.
13. The `.gitignore` trap is demonstrated with `git ls-files` output proving a `.gitignore`d file was
    still tracked, and proving it was not after `git rm --cached`.
14. **`ssh homelab` still works and `systemctl is-system-running` reports `running` with 0 failed
    units** — applied literally per the Definition of Done, precisely because this phase believes it
    did not touch the node.
15. The reflog recovery exercise shows the commit hash before loss and after recovery, matching.
16. `git status` on `main` is clean at phase close and `main` is a merge of the feature branch.

## 9. Security considerations

### 9.1 Publication is irreversible, and that is this phase's central risk

ADR-020 exists because the reference node has no console: certain changes cannot be undone remotely.
Publication has a structurally similar property and a completely different mechanism, so it gets its
own reasoning rather than borrowing ADR-020's checklist:

- A public repository can be cloned, forked, cached and indexed within minutes.
- Deleting it afterwards removes *your* copy. It does not retract the disclosure.
- Rewriting history to remove a secret **before** the first push costs nothing. Afterwards it costs a
  forced update, invalidates every clone, and still does not un-disclose anything.

Therefore the audit precedes the push, unconditionally, and the audit's output is committed.

### 9.2 A secret found after publication is a rotation problem, not a git problem

If the audit had missed something and it were found later, removing it from history would be the
*second* action. The first would be revoking or rotating the exposed credential. Worth stating in the
guide, because the instinct is the wrong way round.

### 9.3 What this repository legitimately discloses

Publishing this repository intentionally reveals: the reference node's hardware and OS versions, the
software stack, the network design at a conceptual level, the SSH policy, and the fact that a
Tailscale tailnet exists. That is the point of a reference implementation, and none of it is a
credential. The audit's job is to confirm the boundary was not crossed — not to relitigate whether
the project should be public.

### 9.4 The `gh` token is a live credential

The authenticated token carries `repo` and `workflow` scopes and lives in the macOS keyring. It is
not in the repository and must never be. `scan-history.sh` searches for `gho_`/`ghp_` patterns for
exactly this reason.

### 9.5 `.gitignore` is not retroactive

Restating it here because it is a security control and not merely a convenience: the `.gitignore`
patterns added in Phase 03 protect against *future* mistakes only. Any secret already committed is
already in history and `.gitignore` will never touch it. This is why §7.2 scans objects, not files.

### 9.6 No destructive operations on the reference node

This phase runs no privileged commands on the server, changes no services, and touches no
authentication. If that changes, ADR-020 applies in full.

## 10. Repository changes expected

| Path | Change |
|---|---|
| `docs/handovers/04-git-github.md` | **This brief** — committed first |
| `LICENSE` | New — MIT |
| `LICENSE-docs` | New — CC BY-SA 4.0 |
| `README.md` | New Licence section; repository URL once it exists |
| `scripts/macos/scan-history.sh` | New — full-history secrets scan |
| `scripts/README.md` | New row for the scan script; any convention learned |
| `guide/04-git-github/README.md` | New — the phase guide |
| `guide/README.md` | Phase 04 entry |
| `docs/reference/git-workflow.md` | New — operational command reference |
| `docs/decisions/ADR-021-…` | New — repository publication, visibility and licensing |
| `docs/build-log/2026-09-09-phase-04-*.md` | New — problems, failures, lessons |
| `docs/handovers/04-git-github-handover.md` | New — addressed to Phase 05 |
| `docs/handovers/README.md` | Two new rows |
| `docs/reference/project-state.md` | Phase 04 status; two known unknowns closed; repository location |
| `docs/reference/software-stack.md` | Git and `gh` move from Planned to Active with tested versions |
| `docs/reference/costs.md` | Phase 04 section — expected explicit zero |
| `CONTRIBUTING.md` | Tags, releases, branch fate where decided |
| `ROADMAP.md` | Phase 04 marked complete |
| `CHANGELOG.md` | Phase 04 entry |
| `.gitignore` | Tightened only if the review finds a real gap |
| `.github/README.md` | Updated only if §6.7 is decided against the presumption |

`MANIFEST.md` remains untouched — it is the frozen bootstrap record.

## 11. Guide documentation required

`guide/04-git-github/README.md`, following the pattern set by Phases 01–03:

- Explains git using **this repository's own history**, with real captured output.
- Covers the eight roadmap topics in the order they become useful, not alphabetically.
- Includes a **reference-build experience** section recording what actually went wrong.
- Names the `.gitignore` trap and the irreversibility of publication as the two things most worth
  remembering.
- Written for the owner: business and technical background, comfortable with computers, not a
  systems engineer.

## 12. Project documentation required

As listed in §10. Specifically:

- `project-state.md` must record the repository's public URL and **close two known unknowns**.
- `software-stack.md` must record git 2.39.5 and `gh` 2.90.0 as tested, with the note that Apple Git
  is somewhat behind upstream — relevant if a later phase needs a newer feature.
- `costs.md` must record an explicit zero rather than omitting the phase.

## 13. ADRs required / possible

| ADR | Status | Subject |
|---|---|---|
| **ADR-021 — repository publication, visibility and licensing** | **Required** | Public from first push; MIT + CC BY-SA 4.0 split; `TelesforoAleix/homelab`; the audit-before-push ordering as a binding rule for any future repository this project publishes. Records the alternatives — private-then-public, single MIT licence, no licence — and why each was rejected. |
| Branch protection / signing | **Possible** | Only if adopted. If deferred, record the deferral in the handover rather than creating an ADR for a non-decision. |
| Server clone of the repository | **Not this phase** | Carried to Phase 05 per §6.5. |

## 14. Costs

**Expected: 0 DKK.** GitHub public repositories are free, and so are private ones — cost is not what
drove the visibility decision, and the ledger should say so to prevent a future reader inferring a
constraint that did not exist. No new subscriptions. `gitleaks`, if used, is free and open source.

Reference-build running total expected to remain **899 DKK (~121 EUR)**.

## 15. Definition of Done

The project-wide checklist from `PROJECT.md` §12, applied **literally, item by item**:

- [ ] Functional objective works — all eleven in §4
- [ ] Configuration/setup is reproducible — `scan-history.sh` runs from the repository; every
      repository-side step is a recorded command, not a click, wherever `gh` can express it
- [ ] Validation/tests have passed — all sixteen checks in §8, with captured output
- [ ] Important security implications were considered — §9, and the audit ran **before** the push
- [ ] Relevant repository files are committed
- [ ] Human-facing guide is updated — `guide/04-git-github/README.md`
- [ ] Project/internal documentation is updated — state, stack, costs, roadmap, changelog, build log,
      handovers index, contributing
- [ ] ADRs created or updated — ADR-021; any deferral recorded rather than silently dropped
- [ ] Actual costs recorded — explicit zero, with the reasoning in §14
- [ ] Problems, failed approaches and lessons recorded — including my own errors, per `PROJECT.md` §11
- [ ] Tested versions recorded — git, `gh`, and any scanner used
- [ ] No unexplained critical AI-generated component remains — `scan-history.sh` commented for a
      reader who must be able to judge what it does *not* catch
- [ ] `main` represents a known-working state — after `--no-ff` merge of `feature/04-git-github`
- [ ] System reports no failed units and no degraded state — checked **last**, per §8.14
- [ ] Structured handover written, stating what Phase 05 inherits

## 16. Return handover requirements

The handover at `docs/handovers/04-git-github-handover.md` is addressed to **Phase 05 — Docker &
Docker Compose** and must state:

1. **The repository's public URL**, and that history is now published and therefore no longer
   cheaply rewritable. Any future secret is a rotation problem first (§9.2).
2. **The audit's actual findings**, including the borderline verdicts of §7.2, so Phase 05 knows what
   the standard was and does not re-decide it silently.
3. **The workflow Phase 05 is expected to follow** — branch, PR, `--no-ff` merge, tag — and whether
   branch protection now enforces it or merely documents it.
4. **The unresolved items from §6**, each with a decision or an explicit deferral and an owner.
5. **A prominent reminder that ADR-020 applies to Phase 05 in full.** Docker rewrites `iptables`
   rules and creates bridge interfaces on a machine with no console. Phase 02's handover already
   flagged Phase 05 as the first phase where the standard genuinely bites; this handover must not let
   that get lost between two phases. Phase 04 was a holiday from that risk. Phase 05 is not.
6. **The open risks carried forward**, unchanged unless this phase closed one: the single SSH key
   with no backup, no firewall, no encryption at rest, no free extents in the volume group, `eno1`
   unused, and the absence of any backup story for the *node* — which this phase fixes for the
   repository only, and it must say so plainly rather than letting "backup" look solved.
7. **Whether the reference node gets a clone** (§6.5), which Phase 05 is the first to actually want.
