# ADR-030: The four-layer workspace, and where project ops records live

- **Status:** Accepted
- **Date:** 2026-09-10
- **Supersedes:** none — it closes ADR-029 §6 and refines ADR-029 §1
- **Superseded by:** none

## Context

ADR-029 decided a four-repository topology on a method/output boundary, and deliberately left one
question open in its §6: **where the Factory's own self-hosting ops records live.** Factory building
Factory has no separate project repository, so the 156 tickets, runs, reviews and releases produced
by dogfooding it had nowhere to go. They stayed in the knowledge base by default rather than by
decision.

Two further things were true on the day this ADR was written, and neither was survivable:

1. **The method layer existed twice.** Factory was extracted from the knowledge base with its
   history on 2026-09-10 and published, but never removed from the source. Ninety files existed in
   both places, and every shared file already differed, because Factory's copies had been
   anonymised for publication. Two live copies of the same method, diverging from the first day.

2. **The knowledge base held a product.** `03-projects/oncla/` was 159 tracked files of product
   spec, design and a React MVP — a different lifecycle, a different audience, and a different
   reason to exist from a note about epistemology.

The owner's framing, which this ADR records: separate concerns into **infrastructure**, an
**execution layer**, **projects**, and **knowledge**.

## Decision

### 1. Four layers, and `projects/` is one of them

ADR-029 named four repositories. This ADR names four **layers**, of which the project layer holds
many repositories rather than one:

| Layer | Where | Visibility | Holds |
|---|---|---|---|
| Infrastructure | `homelab` | public | The AI OS: routing, execution, interfaces, the node |
| Execution | `factory` | public | The AI harness: agents, roles, departments, skills, workflows |
| Projects | `projects/<name>` | private, one repository each | The product, plus its `ops/` |
| Knowledge | `brain` | private | Captures, processed knowledge, ideas, logs, and its own operating layer |

`projects/` is a plain directory, not a repository. Each project inside it is its own private
repository, per ADR-029 §1.

### 2. Every project carries its own `ops/`

A project repository holds two things that must not be confused:

- **the product** — what is being built;
- **`ops/`** — the Factory's operational artifacts *for that project*: tickets, runs, reviews,
  releases, approvals, context packs, interactions.

`ops/` is not part of the product. It is how the Factory works **on** the project, and it lives
beside the product rather than inside it.

This is the general rule that closes ADR-029 §6. The Factory's own self-hosting records are a
project's ops records like any other, so they live at `projects/factory/ops/` in a private
repository — even though that project's "product", the method, is published elsewhere.

### 3. The knowledge base holds knowledge and nothing else

`brain` keeps captures, processed knowledge, ideas, logs, and the operating layer that maintains
them (`.github/`, `scripts/`). It holds no method that Factory owns, and no project.

A tool that feeds ingestion is part of the knowledge base's operating layer, not a project. The
video-download pipeline moved to `scripts/` on that basis.

### 4. Records are not rewritten when paths move

Moving three subtrees out of the knowledge base broke roughly 300 links in session notes and the
append-only log. **Those were deliberately left broken**, and a translation table was added to
`05-logs/README.md` instead.

Live documents describe the present and were rewritten. Records say what was true when they were
written; editing them to look correct in hindsight destroys their value as evidence. This applies
`PROJECT.md` §11 to link maintenance.

### 5. Duplication is resolved in favour of the public copy

Where the same file existed in both the knowledge base and Factory, Factory's version — the
anonymised, published one — is canonical and the other is deleted.

Deletion is gated on a **counterpart existing at the mapped path**, never on content equality:
anonymisation guarantees the contents differ, so equality would be the wrong test and would have
blocked every deletion.

## Alternatives considered

**Leave the ops records in the knowledge base.** Zero work, and it is where they already were. It
perpetuates exactly the mixing this reorganisation exists to end, and it means the knowledge base
grows every time the Factory is run on anything.

**A single private `factory-ops` repository for all projects' ops records.** Simpler to create, but
it separates a project's operational record from the project it describes, so understanding a
ticket would mean opening two repositories. It also scales badly: one repository accumulating every
project's records reproduces the mixing problem at a different address.

**Put `ops/` inside the product tree.** Keeps one directory instead of two, but the product is what
ships and the ops record is not; conflating them means a product repository cannot be handed to
anyone without also handing over the record of how it was managed.

**One `projects` repository containing all projects.** Rejected for the reason ADR-029 §1 already
gave: projects have independent lifecycles and independent reasons to stay private.

**Rewrite the ~300 links in session notes.** Would remove every dangling link, at the cost of
editing 254 historical records to assert paths that did not exist when they were written, and at
real risk of mangling prose across 124 files. Rejected on `PROJECT.md` §11.

## Consequences

**Easier:** each layer has exactly one home, so "where does this go?" has an answer. Adding a
project is creating a repository, not negotiating a folder. The knowledge base shrank from 896
tracked files to 497 and now contains one kind of thing.

**Harder:** relative links cannot cross a repository boundary, so cross-layer references are now
URLs (to public repositories) or plain-text references naming the repository and path. That is
strictly worse than a working relative link, and it is the price of the split.

**Constrained:** the ADR-029 §5 boundary gate becomes more load-bearing, not less. Public and
private repositories now sit as siblings on one filesystem, which makes a stray copy between them
possible in a way it was not when they were separate concerns in separate places.

**Deferred:** nothing was cloned onto the reference node. The node still has no backup and an
unencrypted root filesystem, and putting private repositories on it is exactly the event ADR-015
was to be revisited before. That is Phase 18's decision, and this ADR does not pre-empt it.

**Still open from ADR-029 §6:** where session logs live once `05-logs/` outlives the repository it
was written in. This ADR closes the ops-records half of that section and leaves the session-log
half open.

## Validation / revisit trigger

Revisit if:

- a project turns out to need its ops records readable by someone who must not see the product, or
  vice versa — which would mean `ops/` needs to be a separate repository after all;
- the boundary gate fires on a real cross-copy between the public and private siblings, which would
  argue for keeping them on separate filesystems or separate machines;
- Phase 18's encryption decision makes the node's layout differ from the Mac's, in which case the
  layer model must be restated for the node rather than assumed to carry over.

The check that this decision is holding: the knowledge base contains no project and no Factory
method; each project repository contains exactly one product and one `ops/`; and no file exists in
two layers at once.
