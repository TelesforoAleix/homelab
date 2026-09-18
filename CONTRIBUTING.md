# Contributing

> **Version one closed on 2026-09-18 and is no longer accepting routine feature or documentation
> contributions.** The repository remains public as a reference. A critical security or factual
> correction should first explain why the historical repository must be reopened; see ADR-052.

Home Lab is a reference implementation and learning project. Any exceptional correction should
preserve its clarity, reproducibility and historical accuracy.

## Before contributing

Read:

- `PROJECT.md`
- `AGENTS.md`
- relevant ADRs in `docs/decisions/`
- relevant guide/project documentation

## Branches

- `main` — known-working state
- `feature/<short-name>` — unfinished implementation work
- `experiment/<short-name>` — exploratory work that may be discarded
- `docs/<short-name>` — documentation-only work when useful

## Commit guidance

Prefer small commits that explain one coherent change. Suggested prefixes are optional, not mandatory:

- `feat:` new behavior
- `fix:` bug fix
- `docs:` documentation
- `chore:` maintenance/bootstrap
- `refactor:` structural change without intended behavior change
- `test:` validation/tests

## Documentation expectations

When implementation changes behavior or setup, update the relevant documentation in the same body of work.

Human learning explanations belong in `guide/`.

Operational truth belongs in `docs/`.

## Architectural changes

Create or update an ADR when a decision is durable, cross-cutting, costly to reverse, security-relevant, or meaningfully changes architecture.

Do not edit an accepted ADR to pretend a past decision never existed. Supersede it with a new ADR when appropriate.

## Secrets

Never commit:

- `.env` files containing credentials
- API keys/tokens
- passwords
- SSH private keys
- Tailscale auth keys
- bot tokens
- private personal documents/data

Use `.env.example` files or documented secret names instead.

## Tags and releases

Phases are tagged, not versions — there is no released artefact to version. Use **annotated** tags
(`git tag -a phase-05 -m "..."`), which record tagger, date and message; lightweight tags store only
a pointer. Tags are not pushed by `git push`; push them with `git push origin --tags`.

## Merging

Merge pull requests with `--merge`, never `--squash`. Squashing collapses a phase into a single
commit and destroys the phase boundaries this project keeps deliberately (ADR-013).

## Before publishing anything

Any repository this project publishes gets a full-history secrets audit **before** its first push,
not after (ADR-021). See `docs/reference/git-workflow.md`.

## Pull-request completion check

Before merging to `main`, verify applicable items from the Definition of Done in `PROJECT.md` and ensure `main` remains a known-working state.
