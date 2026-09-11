# ADR-042: Home Lab is public and readable, not packaged for adoption

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** ADR-031 §4, as it applies to `homelab`. Its application to `factory` is unchanged.
- **Superseded by:** none

## Context

ADR-031 §4 requires each public layer to be independently adoptable — *"Someone else must be able to
take `homelab` alone"* and run it on their own infrastructure — and makes a working standalone
quickstart a validation criterion.

For **Factory** that is clearly right. Factory is method, it is fork-and-customise software, and
Phase 20.0 discharged the criterion by running the whole loop from a clean clone with nothing else
installed.

For **homelab** it is the least examined constraint the project holds, and possibly the most
expensive. Adoptability is an abstraction tax paid at every layer: configuration for things there is
exactly one of, indirection around the owner's own inference sources, and a knowledge layer that must
work for a knowledge base that is not the owner's.

And the thing being described is not a thing a stranger installs. A personal AI operating system that
holds *your* knowledge, routes to *your* inference sources and enforces *your* budgets is not a
product; it is an installation.

## Decision

### 1. `homelab` is public and readable. It is not packaged to run standalone

Someone can read the repository, understand how it was built, and **adapt it to their own setup** —
with AI help, which is the normal way this now happens. There is no requirement that it run out of
the box on someone else's machine, and no standalone quickstart is owed.

What it does owe a reader: enough explanation that the *how* and the *why* are recoverable, which is
already the AI-generated-work standard in `AGENTS.md`.

### 2. Factory's standalone adoptability is unchanged

ADR-031 §4 continues to apply to `factory` in full, and it is already satisfied.

### 3. Configuration is the seam

| Published in `homelab` | Not published |
|---|---|
| Method, tools, services, scripts | Actual inference sources, budgets, preferences |
| Configuration **examples** — `.example` files showing shape and intent | The owner's real configuration values |

A reader sees *"here is where configuration goes, here is an example of it"* and never the owner's
values. This is the mechanism that makes §1 workable: the repository stays honestly complete without
publishing an installation.

Some of what is published is directly usable on its own — configuring a subscription CLI on a server
is an example. That is a welcome side effect, not a requirement.

### 4. Knowledge tools are public; the knowledge is not

`homelab` holds the knowledge **tools, methods and services** — ingestion, retrieval, assembly, the
contracts they satisfy. **`brain` holds the knowledge itself**, in its own location on the server,
inside the encrypted volume (ADR-037 §5).

This is the per-artifact privacy rule of ADR-031 §3 applied to the one case that was still ambiguous.
It also means the knowledge layer can be read, understood and reused by someone whose knowledge base
is entirely different — which is a better kind of adoptability than packaging would have produced.

### 5. Secrets are unchanged

No secret in the repository, in `ops/`, in prompts, in logs or in browser storage. That was never a
consequence of adoptability and does not move with it.

## Alternatives considered

**Keep ADR-031 §4 as written and pay the tax.** Rejected. It would shape every layer around a user
who does not exist, and the project has already spent time on abstraction whose only justification was
this clause.

**Make `homelab` private.** Rejected. ADR-021 published it deliberately, and the method is the part
worth publishing. This ADR narrows what publication *obliges*, not whether to publish.

**Ship an installer and accept the tax.** Rejected for now. If people genuinely want to run it, that
is evidence worth having first — and it would be a distribution decision, not an architectural one.

## Consequences

**Easier.** Layers can be built for one installation. Inference sources, budgets and storage paths can
be concrete, with examples published rather than abstractions maintained.

**Harder, mildly.** Every configurable thing now needs an `.example` counterpart kept in step with the
real one, and a drifted example is worse than none.

**Constrained:** the method stays public and readable; secrets stay out; `brain`'s content stays
private regardless of where its tools live.

**Gives up:** the claim that someone can take `homelab` and run it. That claim was never tested and
was not going to be met.

## Validation / revisit trigger

1. A reader who is not the owner can follow the repository and explain how a layer works — the
   readability claim, checked by someone other than the author.
2. `grep` for the owner's real configuration values in the public repository finds **nothing**.
3. Every configuration file has a current `.example` counterpart, and a test or check catches drift.
4. `brain`'s content appears nowhere in `homelab` — the ADR-029 §5 boundary gate already checks this.

**Revisit if:** someone actually wants to run this and says so, which makes packaging a real question
rather than a hypothetical; or the configuration seam stops being sufficient to keep values out.
