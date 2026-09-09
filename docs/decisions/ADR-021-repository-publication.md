# ADR-021: Publish the repository publicly, under a split licence

- **Status:** Accepted
- **Date:** 2026-09-09
- **Supersedes:** none
- **Superseded by:** none

## Context

From bootstrap until Phase 04 this repository had **no remote**. Thirty-seven commits — every ADR,
every guide, every build log, and the only record of how the reference node was built — existed in
one `.git` directory on one MacBook. `git remote -v` was empty. Nothing had ever been pushed.

That is a larger single point of failure than the one the risk register has been tracking. The
single SSH key with no backup loses *access to a machine that can be rebuilt*. Losing this directory
loses *the knowledge of how to rebuild it*, along with the reasoning behind every decision.

Two of the project's four standing known unknowns, carried since bootstrap in
`docs/reference/project-state.md`, were about this: "public repository license" and "final GitHub
repository owner/name". Both had to be answered before anything could be pushed.

The repository was also always *written* as a public artefact. `README.md` addresses people
reproducing the project, `CONTRIBUTING.md` exists, and `PROJECT.md` describes a reference
implementation others learn from. It had simply never been audited as though it were about to be
public.

### The asymmetry that drives the ordering

Publication is irreversible in a way that most decisions in this project are not:

- A public repository can be cloned, forked, cached and indexed within minutes.
- Deleting it afterwards removes your copy. It does not retract the disclosure.
- Rewriting history to remove a secret **before** the first push costs nothing at all. Afterwards it
  invalidates every clone, requires a forced update, and still does not un-disclose anything.

This is structurally similar to ADR-020's reasoning about a console-less node — some actions cannot
be walked back — but the mechanism is entirely different and the two must not be conflated. ADR-020
is about losing access to a machine. This is about losing control of information.

## Decision

1. **The repository is published publicly at `github.com/TelesforoAleix/homelab`,** public from the
   first push rather than private-then-public-later.

2. **Licensing is split by directory:**
   - **MIT** (`LICENSE`) for code: `scripts/`, `config/`, `infrastructure/`, `services/`,
     `experiments/`.
   - **CC BY-SA 4.0** (`LICENSE-docs`) for documentation: `guide/`, `docs/`, and the root Markdown
     files.

3. **A full-history secrets audit runs before the first push, and its result is committed.** This is
   binding on any future repository this project publishes, not just this one. Specifically:
   - The audit scans **objects reachable from all refs**, not the working tree, because
     `.gitignore` is not retroactive and a deleted secret is still in history.
   - **Two independent scanners** must run and their disagreements be recorded. One is
     `scripts/macos/scan-history.sh`, written to be read and understood; the other is a third-party
     tool (`gitleaks`).
   - Borderline categories get a **written, reasoned verdict**. Silence is not a verdict.

4. **If a credential is ever found after publication, rotation is the first action** and history
   rewriting the second. The order matters and is easy to get backwards.

## Alternatives considered

**Private now, public later.** Rejected. It gets the backup immediately with less exposure, which is
genuinely attractive — but it does not avoid the audit, it defers it. Flipping a repository to
public publishes its entire history at that moment, so the same work is required eventually, at a
point where it is easier to skip because the repository "already exists and is fine". Doing the
audit while it is still free is the whole argument.

**Private permanently.** Rejected as contradicting the project's stated purpose. `README.md` opens by
describing who the project is *for*, and it is not the owner alone.

**No remote at all — learn git locally.** Rejected. It would leave the project's entire memory on one
disk, and it would drop pull requests and releases from a phase whose roadmap entry names them.

**A single MIT licence.** Rejected, though it is the conventional choice and would have been simpler.
This repository is ~80 Markdown files and 8 shell scripts. MIT is written about software; applied to
a written guide it leaves attribution and derivative works ambiguous. Being accurate costs one extra
file.

**No licence yet.** Rejected. Absent a licence, default copyright reserves all rights, meaning nobody
may legally reuse anything — the exact opposite of what `README.md` invites. "No licence" is not a
neutral deferral; it is a restrictive choice made by accident.

**Rely on a third-party scanner alone.** Rejected. It would have been quicker and it is what most
projects do. Two things argued against it, both confirmed during Phase 04: `gitleaks` scanned 34 of
this repository's 38 commits, silently skipping every merge commit, because it scans diffs; and its
one reported finding was the word `RAG` in ordinary prose. A tool that misses a class of commits and
cries wolf on English needs a second opinion, and a project whose stated purpose is learning should
own a scanner it can read.

## Consequences

**Positive.**

- The project's memory now exists in more than one place. This is the first backup of any kind in the
  project's history.
- Two standing known unknowns are closed.
- The audit-before-push rule is now written down, so a future phase publishing something else does
  not have to rediscover the ordering under time pressure.
- The licence split makes reuse rights unambiguous for both halves of the repository.

**Negative, and accepted.**

- **History is now expensive to change.** Every commit is public. The freedom to rewrite that made
  this phase's audit cheap is spent.
- **The reference build is now described publicly in detail** — hardware, OS versions, software
  stack, network design, SSH policy. This is intentional and is what a reference implementation is
  for, but it is a real disclosure. It is safe because the controls are real: SSH is key-only,
  `PermitRootLogin no`, and nothing sensitive is committed.
- **Private (RFC 1918) and Tailscale (CGNAT) addresses are published,** having been adjudicated as
  non-secret. See the Phase 04 audit record. Neither is routable from the internet; the tailnet
  *name*, which is an account-linked identifier, remains redacted throughout.
- **The admin username `aleix` is public.** Acceptable only because SSH accepts no passwords. If
  password authentication were ever re-enabled, this changes from harmless to material — which is a
  concrete illustration that the sensitivity of a fact depends on the other controls around it.
- GitHub is now a dependency of the project's backup story. It is not the only copy — `git bundle`
  produces an offline single-file clone — but the phase should not pretend a hosted service is a
  complete backup strategy.

## Related

- **ADR-013** — `main` as a known-working state; the workflow this phase makes enforceable.
- **ADR-017** — self-contained sequential phases.
- **ADR-020** — irreversibility on a console-less node; related reasoning, different mechanism.
- **ADR-015 / ADR-016** — the unencrypted disk and the cleartext Wi-Fi passphrase are now publicly
  documented weaknesses. Both were already recorded; publication raises the cost of leaving them.
