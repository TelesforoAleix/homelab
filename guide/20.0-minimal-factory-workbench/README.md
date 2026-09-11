# Phase 20.0 — Minimal Factory Workbench

**What was built:** software that runs a project's operating records, living in the
[`factory`](https://github.com/TelesforoAleix/factory) repository. This is the first phase whose
deliverable is not in this repository, and the first one that produced running code rather than a
document or a configured service.

## What a Workbench is, and why Factory needed one

Factory is a *method*: what a ticket is, what states it has, who may approve what. Until this phase
it was method only — a person or a coding agent read the prose and did the work by hand, editing YAML
files in an editor.

That mostly worked, and it had one real problem: **writing a valid record is deterministic work that
was being done probabilistically.** A model asked to create a ticket will usually produce a valid
one. "Usually" is the wrong standard for the thing that records who approved what.

So Workbench does the deterministic half. It creates and validates records, manages the workflow, and
refuses what the rules say to refuse. It does **not** do AI work — that goes to a configured
*adapter*, which might be a subscription CLI, an API key, or eventually homelab.

## The one boundary that matters

> **Workbench holds no backend credential, no model registry, and no tool implementation.**

This is worth understanding rather than just obeying, because it is the line that keeps the whole
architecture honest.

Factory is public and meant to be adopted by other people. If Workbench held homelab's credentials
or knew homelab's tools, then using Factory would mean having homelab — and homelab is one person's
private infrastructure. The adapter boundary is what lets someone else run Factory through Codex,
or Claude Code, or an API key, or nothing at all.

There is a second reason, and it is the older one: **enforcement written into the thing being
enforced is not a contract.** Factory declares what work is; something else decides whether it may
happen.

## How it fits together

```text
  you, in a browser              you, in a terminal
        │                               │
        │ HTTP (127.0.0.1 only)         │
        ▼                               ▼
   local server  ──────────────▶  the engine  ──────▶  ops/ records + git
                                       │
                                       ▼
                              execution adapter  ──▶  AI work (or a fake)
```

**Everything that writes goes through the engine.** The server does not write records; it translates
a click into an engine call. That is why the CLI and the dashboard cannot disagree — there is only
one implementation of "what a valid write is", and a test compares their output byte for byte.

If you ever find a write that the dashboard can do and the CLI cannot, something has gone wrong at
the level of the design, not the code.

## Running it

```bash
pip install pyyaml

python3 acceptance/synthetic_project.py      # watch the whole loop run
python3 -m workbench.cli init ~/projects/thing --project-id THING --title "Thing"
python3 -m workbench.cli --project ~/projects/thing serve
```

`serve` binds `127.0.0.1` and has no password. **That is deliberate, and it is safe for exactly one
reason:** the operating system already separates users on your own machine, so a login would add
ceremony without adding a boundary. It also means the thing must never be exposed publicly, because
then the boundary really would be missing. It refuses to bind anything but loopback.

## Checking the credential boundary yourself

You do not have to take the boundary on trust. From the Factory repository:

```bash
grep -rn "api_key\|token\|secret\|password" workbench/    # expect: nothing that holds one
python3 -m unittest discover -s tests -v                  # 41 tests
lsof -nP -iTCP:8765 -sTCP:LISTEN                          # expect 127.0.0.1, nothing else
```

The last one matters more than it looks. Configuration that *says* `127.0.0.1` and a process that
*listens on* `127.0.0.1` are different claims, and only the second one is evidence.

## Why every refusal has a control

Each rule Workbench enforces is tested twice: once by breaking it, and once with the **byte-identical
case that should succeed**.

The reason is a failure mode that looks like success. Suppose the approval check has a typo and
throws on every input. The "refused" test passes. The rule appears enforced. It is actually broken in
the worst possible direction, because now nothing can be approved and the first person to hit it will
work around it rather than report it.

> **An authorisation check that has only ever permitted is unvalidated** — and one that has only ever
> refused is broken.

## The approval mechanism, which is subtler than it sounds

An approval is bound to **one immutable action, including its revision**. Approving a merge of
`feature/x` does not approve a merge of `feature/x` after two more commits land.

This is done by hashing the action, its target and every material input into a fingerprint. The
approval stores the fingerprint; the fingerprint is recomputed at the moment of action. If anything
material changed, the hashes differ and the approval stops binding.

The test for it does the thing that actually happens in real life: approve, then push one more
commit, then try to merge. It refuses, and it says *why* — `revision changed since it was granted`.

**Approving a pull request is not the same as approving a revision.** A PR can gain commits after
you look at it. This is the mechanism that closes that gap.

## Two bugs worth keeping

Both were found by running the thing, not by reading it.

**`git rev-parse --abbrev-ref HEAD` fails on a repository with no commits.** It is the standard way
to ask "what branch am I on" and it does not work in the one state every new project passes through.
`git branch --show-current` answers in both states.

**A `git reset --hard` deleted an approval record.** A project keeps `ops/` in the same repository as
its product code. Switching the main checkout to a feature branch took the live `ops/` directory
along with it, and resetting that checkout destroyed records written since the last commit.

The fix is a *worktree*: product work happens in a separate directory on its own branch, and the main
checkout never leaves `main`. The accepted acceptance steps said "feature branch **or** disposable
worktree" from the start — the reason only became clear after the records were gone.

The general lesson is the one this project keeps relearning: **operational records and the product's
version control are not the same system, and git commands that are safe on code are destructive on
state.**

## What this phase did not do

- **No real execution adapter.** Only a deterministic fake. That means the adapter interface is
  *unproved* — it has one implementation, and an interface with one implementation is a guess.
- **Pull requests are not exercised.** GitHub mode exists; the acceptance run uses a disposable local
  bare repository, which needs no credentials and no network.
- **Factory's content is not migrated.** That is Phase 20 proper, and it runs after the homelab AI
  foundation exists.
