# The repository's front page was a placeholder for five phases

**Date:** 2026-09-09
**Found by:** the owner, looking at the repository on GitHub
**Severity:** Every visitor since publication saw a two-line placeholder instead of the project.

## What was wrong

`.github/README.md` existed, created during the Phase 00 bootstrap, containing:

```markdown
# GitHub Configuration

GitHub-specific templates, workflows, and repository automation can be introduced in later phases
when justified.
```

GitHub resolves a repository's front page in this order:

```text
.github/README.md   →   README.md   →   docs/README.md
```

The **first** match wins. So the root `README.md` — the one describing the project, the reference
build, the philosophy, the phase status and the licences — **was never rendered on the repository
page at all.** Anyone arriving at `github.com/TelesforoAleix/homelab` saw a note about GitHub
templates and nothing else.

This was true from Phase 04, when the repository was published, through Phase 09.

## Why nothing caught it

Phase 04's Definition of Done covered publication thoroughly on the axis it was worried about:
a two-scanner full-history secrets audit ran before the first push, and licences were chosen and
recorded (ADR-021). What it did not include was **looking at the result the way a visitor sees it.**

The checks asked "is it safe to publish?" and answered correctly. Nobody asked "does the published
thing present itself?" — and the local `README.md` renders perfectly in an editor, in
`docs/`-relative link checks, and in every view except the only one that matters.

That is a variant of a failure this project has recorded nine times in a different register: a check
that reports a confident result about something adjacent to the actual question. Here the checks were
right and the question was incomplete.

## The fix

`.github/README.md` deleted. There is nothing else in `.github/`, so the directory goes with it;
it can be recreated when there is an actual workflow or issue template to put in it, which is what
the placeholder was reserving space for. Reserving space with a file named `README.md` is the one
name that has a side effect.

## Lessons

- **A file named `README.md` is not inert.** Several tools and platforms assign it meaning by
  location, and `.github/` is one of the places where that meaning includes "replace the front page".
  A placeholder is still a document with precedence.
- **Publishing is not finished when the push succeeds.** The artefact has a rendered form, and the
  rendered form is the deliverable. Look at the public URL as a stranger would, once, after
  publishing.
- **A correct check can answer the wrong question.** Phase 04 verified that publication was *safe*.
  It never verified that it was *legible*.
