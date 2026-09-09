# Phase 04 Handover — Git & GitHub Fundamentals

- **Date:** 2026-09-09
- **From:** Phase 04 phase context
- **To:** Phase 05 — Docker & Docker Compose
- **Brief:** [`04-git-github.md`](04-git-github.md), committed before implementation per ADR-017

## Outcome

**Complete.** All eleven functional objectives met. The repository is public, its history was audited
before the first push, and the reference node was not touched.

## What the next phase inherits

> Read this section first. Under ADR-017 there is no planning context to reconcile any of it; if it
> is not written here, it is lost.

### 1. ⚠️ ADR-020 applies to Phase 05 in full. Phase 04 was a holiday from that risk.

Phase 02's handover already flagged this, and it must not get lost in the gap between two phases:

**Docker rewrites `iptables` rules and creates bridge interfaces, on a machine reachable only over
the network, with no console.** By the definition in
[`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md) that is
**lockout-class** — it touches the network path both of your access routes depend on.

Phase 04 ran entirely on the MacBook. It changed no services, ran no privileged commands on the node,
and needed no part of ADR-020. **That is not the normal case and Phase 05 is not like it.**

Before installing Docker:

- Run `scripts/macos/preflight.sh`, from the Mac, which proves both routes from outside.
- Have two sessions open, one idle, as the way back.
- Classify the change *before* typing it. Classification is the control; the checklist only helps
  once you have noticed it applies.
- Remember `eno1` is still unused, so both routes share one Wi-Fi adapter. Docker breaking the
  network does not break one route, it breaks both.

### 2. The repository is public, and history is no longer cheap to change

**`github.com/TelesforoAleix/homelab`** — public since 2026-09-09 (ADR-021).

| Fact | Value |
|---|---|
| Visibility | **PUBLIC** |
| Default branch | `main` |
| Commits on `main` at handover | **43** (37 at first push, plus Phase 04's own work and its merge) |
| Merge commits preserved | **4/4** — verified after the push |
| Tags | `phase-01`, `phase-02`, `phase-03`, `phase-04` — annotated |
| Licences | MIT (`LICENSE`), CC BY-SA 4.0 (`LICENSE-docs`) |
| Branch protection | **none** — see §5 |

**What changed for you.** Before this phase, history could be rewritten for free because nothing had
ever been pushed. That is spent. From now on:

- **A secret committed and pushed is a disclosure, not a mistake you can quietly amend.**
- **If a credential is ever exposed, rotate it first.** Rewriting history is the second action and
  does not un-disclose anything — the repository may already be cloned, forked or indexed.
- Never `--amend`, `reset` or force-push a commit that has been pushed. Use `git revert`, which is
  also what `PROJECT.md` §11 requires: record the reversal, do not pretend the mistake never existed.

### 3. The audit's findings, and the verdicts you must not silently re-decide

Two independent scanners over all 220 blobs reachable from every ref. **No secrets were found and
none had to be removed.** Full record in
[`docs/build-log/2026-09-09-phase-04-audit.md`](../build-log/2026-09-09-phase-04-audit.md).

Four borderline classes were adjudicated in writing. These are now the project's standard; if Phase
05 changes one, it changes it deliberately and records why:

| Finding | Verdict | Reasoning |
|---|---|---|
| RFC 1918 addresses (`192.168.1.57`, `.112`) | **publish** | Not routable from the internet |
| Tailscale CGNAT addresses (`100.71.62.71`, `100.69.244.33`) | **publish** | Reachable only inside the tailnet, which is authenticated by device key |
| Home paths / the username `aleix` | **publish — conditionally** | See below |
| SHA256 checksums | **publish** | Checksums exist to be published |
| **The tailnet *name*** | **WITHHELD** | An account-linked identifier. Redacted as `<tailnet>` throughout, and `verify-remote-access.sh` strips it |

**The conditional verdict is the one that can go stale.** Publishing the admin username is harmless
*because SSH accepts no passwords* (ADR-018: `publickey` only, no keyboard-interactive,
`PermitRootLogin no`). It is half of a credential pair whose other half cannot be guessed. **If any
phase ever re-enables password authentication, this adjudication becomes wrong** and a published
username becomes material. The sensitivity of a fact depends on the controls around it.

Note the pair that shows the distinction: the tailnet **address** is published, the tailnet **name**
is not.

### 4. The workflow you are expected to follow

Documented in [`docs/reference/git-workflow.md`](../reference/git-workflow.md). In short:

```bash
git switch main && git pull
git switch -c feature/05-docker
# FIRST: write and commit the brief, before implementing (ADR-017)
git push -u origin feature/05-docker
gh pr create --base main --head feature/05-docker
gh pr merge --merge          # --merge, NEVER --squash
git tag -a phase-05 -m "..." && git push origin --tags
```

`--squash` would collapse the phase into one commit and destroy the phase boundary. `git push` does
not push tags.

**Nothing enforces any of this.** It is convention plus this document. See §5.

### 5. Decisions taken, so you do not re-decide them by accident

Each was considered and declined *with a reason*, not overlooked:

| Decision | Outcome | Why, and when to revisit |
|---|---|---|
| **Branch protection on `main`** | **Not enabled** | ADR-013 states the policy; nothing enforces it. A rule forbidding direct pushes to `main` would also block the owner's own recovery on a one-person project. Revisit when a second contributor exists. |
| **Commit signing** | **Not adopted** | All commits unsigned. Meaningful for a public repository under a named identity; deferred rather than done badly. |
| **CI / GitHub Actions / issue templates** | **Not added** | There is nothing to run. `AGENTS.md` forbids adding infrastructure because it is common rather than needed. |
| **A clone of this repository on the node** | **Not created** | Files are still `scp`'d. A clone puts a credential on a console-less machine. **Phase 05 is the first phase that would genuinely benefit** — decide it on its merits, and note that a deploy key or read-only clone is a smaller step than full write access. |
| **Merged branches deleted** | **Kept** | `feature/01-…`, `feature/02-…`, `feature/03-…`, `docs/phase-01-03-currency` remain. They are a visible record of the phase structure and cost nothing. |
| **Tag scheme** | **Phases, not semver** | There is no released artefact to version. |

### 6. Open risks carried forward

Unchanged by this phase unless noted.

| Risk | Owner |
|---|---|
| **Single SSH key, no backup, no console.** Still the most consequential item | Phase 13 |
| No firewall; `:22` open on the LAN and answering | Phase 13 |
| No encryption at rest (ADR-015); Wi-Fi passphrase cleartext | Phase 13 — **Phase 10 must revisit ADR-015 first** |
| Node key expiry deliberately disabled (ADR-019) | Phase 13 must revisit on its merits |
| Wi-Fi is a single point of failure for **both** access routes; `eno1` present, unused | Not owned by any phase — **and it bites hardest in Phase 05** |
| The volume group has no free extents | Not owned by any phase — **relevant to Phase 05:** Docker images and volumes consume the root LV, which cannot be grown by `lvextend` |
| 2016 firmware | Phase 13, low priority |
| **New:** GitHub 2FA status unverified — the `gh` token lacks the `user` scope | Owner |

**Do not let "backup" look solved.** Phase 04 gave the *repository* an offsite copy. **The reference
node still has no backup of any kind.** If the SSD fails, the machine is rebuilt from the guide.
That is survivable by design, and it is not a backup story.

### 7. Two things Phase 05 should expect to matter

- **Docker consumes the root LV, which cannot be grown.** 232 G, 4% used today. Images, volumes and
  build cache all land there and the volume group has no free extents, so `lvextend` is not
  available. Watch it, and learn `docker system df` / `docker system prune` early rather than after
  it fills.
- **`vm.swappiness` is still 60** — inherited from Phase 01 and flagged there as a Phase 05 trigger.

## What was implemented

A full-history secrets scanner written to be read; two licences and the ADR explaining the split; the
repository's first publication and its first backup of any kind; a pull request, four annotated tags
and a release; a guide taught entirely from this repository's own history; and an operational
workflow reference. The reference node was not touched.

## Validation performed

All sixteen checks from the brief's §8.

| Check | Result |
|---|---|
| Full-history scan across all refs | 220 blobs, 1,351,206 bytes searched — **0 critical** |
| Independent scanner (gitleaks 8.30.1) | **0** after one prose false positive adjudicated |
| **Scanner validated against planted secrets** | **6/6 caught**, exit 1 — see Problems |
| Borderline categories adjudicated in writing | 4 classes, §3 above |
| `git bundle verify` | "The bundle records a complete history" (303 KB) |
| Licences present and scoped | `LICENSE`, `LICENSE-docs`, README states the split by directory |
| Repository is public | `gh repo view` → `visibility: PUBLIC`, `isPrivate: false` |
| **`main` == `origin/main`** | `8e42570…` both sides — byte-identical |
| **All four merge commits survived the push** | `git rev-list --merges --count origin/main` → **4** |
| Commit count on `origin/main` | 37 at first push |
| Pull request opened and merged | [#1](https://github.com/TelesforoAleix/homelab/pull/1), merged with `--merge` |
| Conflict created and resolved by hand | Markers captured verbatim; `:1`/`:2`/`:3` stages shown; resolved and committed |
| Annotated tags | `git cat-file -t phase-02` → `tag` (an object, not a pointer); all four on the remote |
| `.gitignore` trap demonstrated | `git ls-files` proved the file still tracked after `.gitignore`; 0 after `git rm --cached`; secret **still** in history |
| Reflog recovery | `reset --hard` then recovered — hash matched exactly |
| **Node health, checked last** | `systemctl is-system-running` → `running`, 0 failed units, both SSH routes up |

## Problems / failures / lessons

Four, all recorded in the build log. **All four are the same failure family** — a check that reports
success by returning nothing:

| Phase | Check | Failure |
|---|---|---|
| 03 | `sshd -T` | Read the config file, not the running daemon |
| 02 | `who` | Zero sessions, exit 0, on a machine with six |
| 04 | binary detection | Skipped all 213 blobs and reported all 16 classes clean |
| 04 | **private-key pattern** | **Could not run at all, and reported clean** |

The fourth is the one to carry forward. The pattern begins with dashes (`-----BEGIN … PRIVATE KEY`),
so grep parsed it as command-line options and exited 2; `2>/dev/null` discarded the error and the
code treated exit 2 exactly like exit 1. **The most important class in the scanner was silently
dead** — and would have stayed dead until the day it mattered.

It was found only by **planting six fake secrets in the scratch clone and checking the scanner
fired.** Five were caught; the private key was not.

> **A detector that has only ever reported "clean" is unvalidated.** It has been shown it can say
> *fine*. It has never been shown it can say *not fine*. Plant a positive case somewhere disposable
> and make it fire.

That generalises well beyond git — to monitoring, alerting and health checks, and most sharply to
backups: a backup you have never restored is not a backup, for exactly this reason. **Phase 05 will
add health checks and Phase 13 will add backups. Both should validate against a positive case.**

Also recorded: the scanner matched its own documentation twice — first `*.ts.net` as literal pattern
text in this phase's own brief, then, more seriously, **the build log's own record of the
planted-secret test tripped all six CRITICAL classes on published `main`**. Nothing real was
disclosed, but the gate was left permanently red, which is how a control stops being one. The
evidence is now written in a form that cannot be mistaken for the thing it describes, and **the audit
now runs at phase close as well as before the push**. Also: gitleaks silently skipped all four merge
commits; and `README.md` still announced Phase 00 as the current status, three phases later,
corrected an hour before publication.

**One honest ordering note.** The private-key bug was found *after* the repository was pushed, not
before. The re-audit with the working scanner returned the same verdict, so the publication decision
stands — but the phase's own rule was "audit, then publish", and the audit that gated the push was
partly broken. The result was right; the proof was not. Recorded in that order rather than the
flattering one.

## Deviations from phase brief

1. **`.gitleaks.toml` was added**, which the brief did not anticipate. One adjudicated allow-list
   entry for a prose false positive, because a scanner that always reports the same known-false
   result trains its reader to ignore it.
2. **`README.md` required more than a licence section.** Its "Current status" was three phases
   stale. Fixed, and recorded as a finding against the Phase 03 documentation currency pass, which
   checked `docs/` and `guide/` but never the front door.
3. **GitHub 2FA could not be verified.** The `gh` token lacks the `user` scope. Recorded as
   *unknown* rather than assumed, and the token's scope was deliberately **not** expanded for a
   convenience check.
4. **The scanner's validation step was added.** The brief specified running two scanners; it did not
   specify proving either could detect anything. It should have.

## Open issues / technical debt

- **GitHub 2FA status unverified.** Owner action; needs `gh auth refresh -h github.com -s user`, or
  a look at the account settings page.
- **Nothing enforces the workflow.** No branch protection, no signing, no CI.
- **`scan-history.sh` only knows the patterns it was given.** Its header says so. It scans objects
  reachable from a ref — right for a push, not a full account of what is on disk.
- **The reference node still has no backup.** Increasingly conspicuous; now the only unbacked-up
  half of the project.
- **`eno1` still unused**, so both access routes still share one Wi-Fi adapter.
- **The volume group has no free extents** — and Phase 05 is about to start writing images to it.

## ADRs

| ADR | Status | Note |
|---|---|---|
| **ADR-021** — repository publication, visibility and licensing | **Accepted** | Binds any future repository this project publishes: audit before push, two scanners, written adjudications |
| ADR-013 — known-working `main` | Referenced | The four merge commits are this ADR expressed in git |
| ADR-017 — self-contained sequential phases | Followed | Brief committed as `c680033` before implementation |
| ADR-018 / ADR-020 | Referenced | ADR-018 is load-bearing for the username adjudication; ADR-020 was not needed this phase and **is needed next** |

## Tested versions

| Component | Version |
|---|---|
| git (MacBook) | 2.39.5 (Apple Git-154) — behind upstream; ships with Xcode CLT |
| GitHub CLI (`gh`) | 2.90.0 |
| gitleaks | 8.30.1 |

Nothing is version-critical. Two behaviours would need reproducing on other versions: BSD `grep`
rejecting a leading-dash pattern without `-e`, and gitleaks skipping merge commits.

## Costs

**0 DKK**, recorded as an explicit zero. GitHub public repositories are free — but so are private
ones, **so cost did not drive the visibility decision** and the ledger says so, to stop a future
reader inferring a constraint that did not exist. `gitleaks` is free and open source.
Reference-build running total unchanged at **899 DKK (~121 EUR)**.

## Recommended roadmap changes

Actioned directly, since ADR-017 leaves no recipient:

1. **Phase 04 marked complete** in `ROADMAP.md`, with what it deliberately did not adopt listed
   inline so later phases cannot assume oversight.
2. **Phase 05 must apply ADR-020 explicitly** — carried into §1 above rather than left implicit.
3. **The repository's public status added to `project-state.md`**, with the consequence that a new
   secret is now a disclosure rather than an amendable mistake.

No phase renumbering required.

## Definition of Done

- [x] Functional objective works — all eleven in §4 of the brief
- [x] Configuration/setup is reproducible — `scan-history.sh` runs from the repository; every
      publication step expressed as a `gh`/`git` command rather than a click
- [x] Validation/tests have passed — all sixteen checks, with captured output
- [x] Important security implications were considered — the audit gated the push; four categories
      adjudicated in writing; the conditional verdict flagged as conditional
- [x] Relevant repository files are committed
- [x] Human-facing guide is updated — `guide/04-git-github/README.md`
- [x] Project/internal documentation is updated — state, stack, costs, roadmap, changelog, build log,
      handovers index, contributing, scripts README, workflow reference
- [x] ADRs created or updated — ADR-021 accepted; four declined decisions recorded with reasons
      rather than left silent
- [x] Actual costs recorded — explicit 0 DKK, with the non-obvious reasoning
- [x] Problems, failed approaches and lessons recorded — four, including a scanner bug found only by
      planting secrets, and the honest note that it was found after the push rather than before
- [x] Tested versions recorded
- [x] No unexplained critical AI-generated component remains — `scan-history.sh` documents what it
      does **not** catch, in its header, before what it does
- [x] `main` represents a known-working state — after `--no-ff` merge of `feature/04-git-github`
- [x] System reports no failed units and no degraded state — verified **last**
- [x] Structured handover written, stating what Phase 05 inherits
