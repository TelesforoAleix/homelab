# ADR-029: Repository topology and the method/output boundary

- **Status:** Accepted
- **Date:** 2026-09-10
- **Supersedes:** none
- **Superseded by:** none

## Context

This repository has been public since Phase 04 (ADR-021). Alongside it, the owner keeps a private
repository holding 865 markdown files that mixes three different kinds of thing:

| Kind | Where it lives today | What it is |
|---|---|---|
| Knowledge | `00-inbox`, `01-knowledge`, `02-ideas`, `05-logs` | Personal knowledge base, 683k words |
| Method | `03-projects/ai-development-team` (The Factory), `04-agents/`, `.github/` skills | A reusable AI development operating system — roles, departments, skills, workflows |
| A product | one project directory | 257 design files plus ~2,900 TypeScript files under an `mvp/` subtree |

These have different lifecycles, different reasons to stay private, and different audiences. The
Factory's own README states it is not built for any single project and is reusable across projects;
measurement supports that — `04-agents/` is 30 files of which only 3 name a specific project.

The owner's framing, which this ADR records:

- **Factory is the AI harness** — agents, skills, workflows. It evolves fast and is **method**.
- **Homelab is the AI OS** — model routing, context assembly, execution, interfaces. More stable.
- **What comes out of operating that system is output**, and output is private.

Both halves of the system are intended to be public. What must not be public is the knowledge, the
products, and the operational records of running it on real work.

## Decision

### 1. Four repositories

| Repository | Visibility | Holds |
|---|---|---|
| `homelab` | **public** | The AI OS: tool vocabulary, capability levels, model registry, routing, context assembly, executors, interfaces, guide, ADRs |
| `factory` | **public** | The AI harness: agent, skill and workflow definitions; roles; departments; templates; role registry |
| `brain` | **private** | The knowledge base — what remains once Factory and the product leave |
| *(product)* | **private** | Product spec and TypeScript codebase, named by its own project |

Future projects get their own private repositories on the same rule.

### 2. The boundary is method versus output

**Method is public. Output is private.**

The test, applied to any file: *would this be useful to someone who has none of the owner's
knowledge, projects, or history?*

- A role specification saying a reviewer cannot approve its own work — **method**, public.
- Ticket `TICKET-2026-0009` recording that a reviewer approved a specific piece of work —
  **output**, private.

This scales the pattern the homelab repository already uses in miniature: `allowlist.example` is
committed, the real allowlist never is.

### 3. Operational records follow the project they were produced for

`03-projects/ai-development-team/ops/` currently holds 22 tickets, runs, reviews and approvals from
The Factory being operated on itself. Those are output and **do not go public** with the method
that produced them. Where exactly they land is deliberately left open — see §6.

### 4. The public repositories ship examples, never samples

Where a public repository needs to demonstrate working with knowledge or project data, it ships a
**synthetic corpus written for the purpose**. It never ships a subset of real notes, however
harmless the subset looks.

### 5. The boundary is enforced by a check, not by care

Phase 04 established a full-history secrets audit with a scanner validated against planted secrets.
That gate is extended: the public repositories fail their check if knowledge-shaped or
output-shaped content appears in them.

The project has recorded nine instances of a check reporting a result it could not support. So this
gate must be validated the same way as the secrets scanner — **plant a positive case and confirm it
fires** — before it is trusted. A detector that has only ever reported "clean" is unvalidated.

### 6. Deliberately left open

Two questions are not decided here, because deciding them now would be guessing:

- **Where The Factory's self-hosting ops records live.** By ADR-028 they are project output, but
  Factory-building-Factory has no separate project repository. Either a private `factory-ops`
  repository or the knowledge base.
- **Where session logs live** once `05-logs/` outlives the repository it was written in — the
  knowledge base, or the project each session touched.

Both are decided during the split itself, with the files in front of us.

## Alternatives considered

**Keep everything in the private brain repository.** Least disruption. Rejected: it makes The
Factory permanently unpublishable, which contradicts the owner's intent that it be the reusable,
shareable half of the system.

**Two repositories — public homelab, private brain.** The shape the earlier integration handover
proposed. Rejected once the owner clarified that Factory is a public harness rather than private
content; the handover's split was drawn as "capability versus content", which puts the method layer
on the wrong side.

**Three repositories, with Factory inside homelab.** Rejected: the two evolve at different speeds by
design. Factory is expected to change constantly as agents and skills are added; homelab is meant to
be the stable substrate. Merging them couples a fast-moving catalogue to a slow-moving runtime.

**A single public monorepo for homelab plus factory.** Rejected for the same reason, and because it
would make the dependency direction ambiguous. ADR-027 depends on Factory declaring and homelab
enforcing; separate repositories make that direction visible.

## Consequences

**Easier:** The Factory becomes publishable and reusable by others. Each repository can be cloned
onto the node independently and at different times. The public/private question has a single answer
per repository rather than per directory.

**Harder:** cross-repository links. The knowledge base currently links to Factory files by relative
path, and those links break at the split. A link-repair pass is part of the work, and
`scripts/wiki_health_check.py` is the existing tool for finding what broke.

**Newly required:** a secrets and boundary audit before the first push of each new public
repository, following the Phase 04 precedent.

**Operationally significant:** the working tree is not the repository. `03-projects/youtube-download/`
holds 6.5 GB of gitignored video and the product's `mvp/` subtree holds `node_modules`. Tracked content
across the whole brain is roughly 20 MB. **The split must be done with git operations, never by
copying directories.**

**Deferred:** whether the product's design documents and its codebase eventually separate from each other.
They move together for now.

## Validation / revisit trigger

Revisit if:

- a fifth kind of content appears that fits none of the four repositories;
- the method/output test in §2 proves ambiguous in practice often enough to need refining;
- The Factory turns out to carry more project-specific coupling than the 3-of-30 measurement
  suggests, making publication harder than expected.

**Validation required before the split is considered complete:** the boundary check in §5 validated
against planted content; no `ops/` record or product-specific file present in either public
repository; `wiki_health_check.py` run before and after, with the link breakage accounted for rather
than merely observed.
