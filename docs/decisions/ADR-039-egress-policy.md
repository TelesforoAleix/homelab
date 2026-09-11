# ADR-039: What may leave the machine — a policy, not a list

- **Status:** Proposed
- **Date:** 2026-09-11
- **Supersedes:** ADR-025 §8. The rest of ADR-025 stands, including §1's credential boundary.
- **Superseded by:** none

## Context

ADR-025 §8 permits exactly two things to leave the machine: the question, and the literal output of
`/status` — hostname, uptime, load, memory, disk. *"Widening this requires its own ADR."* ADR-033 §6
named this as the immediate next decision, because a gateway carrying assembled context is exactly
that widening.

The reasoning behind §8 is worth restating, because it survives completely:

> journal lines are written by other software, some of it reachable from the network, so feeding them
> to a model would mean an unbounded amount of host data leaving the machine, **selected by whatever
> could write a log line rather than by the owner**.

That is not an argument against content leaving. It is an argument against content leaving that
**nobody chose**.

The problem with §8 is its form. It is an enumeration, and the architecture needs to send assembled
context — files a work item names, retrieved knowledge, search results. Extending a list of two items
one content type at a time would mean an ADR per content type forever.

## Decision

### 1. Classification is by whose data it is, not what kind of file it is

| Class | May leave |
|---|---|
| The **owner's own** material — notes, code, documents, gathered and processed research | **Yes**, to approved providers |
| **Third-party or personal data** — anything belonging to someone who is not the owner | **No**, without a new decision |
| **Secrets** — credentials, keys, tokens | **Never**, under any classification |

This holds because of what the system actually contains today: the owner's own scripts and notes,
general knowledge gathered from public sources, and fabricated demo data. There are no customers and
no third-party personal data. The owner already accepts this material reaching a model provider.

**The day third-party personal data enters the system, this tightens in exactly one place** rather
than everywhere. That is the point of classifying by subject rather than by file type.

### 2. Selection must be deliberate

Content leaves only when the **owner** or an **approved agent acting on a work item** selected it.

This is ADR-025 §8's reasoning, preserved as a rule rather than as a list. Content chosen by anything
that merely *can write* — a log line, an inbound message, a fetched page — never leaves on that basis.
Automatic inclusion of logs, journals, unit files, configuration or allowlists remains forbidden.

### 3. Provenance travels with anything assembled

Every item in an assembled context carries where it came from, when, and at what revision. Without
that, §1's classification cannot be checked after the fact and §2's selection cannot be audited.

### 4. Approved providers are a configured list

Content leaves to providers the owner has approved, not to whatever a component happens to call. A
provider that is not on the list is a refusal.

## Alternatives considered

**Extend §8's list item by item.** Rejected — an ADR per content type, and the list would never
describe an assembled context.

**Classify by sensitivity label on each file.** Rejected. The Phase 19 design review started down
this path and the owner stopped it as scope drift; it requires labelling everything correctly forever,
and the failure mode is silent.

**Allow anything the owner's account can read.** Rejected: that is precisely §8's original warning,
restated as a permission.

## Consequences

**Easier.** Layer 6 can assemble real context. The harness becomes possible at all.

**Harder.** Every assembly path must carry provenance, and "who does this belong to" must be
answerable for anything retrieved — which is a design requirement on the knowledge layer, not only on
egress.

**Constrained:** secrets never leave regardless of classification; automatic inclusion of host data
remains forbidden; the provider list is configuration, and an unapproved provider is a refusal.

**Newly required:** a recorded trigger. When the system first holds data belonging to someone who is
not the owner, §1 must be revisited **before** that data is stored, not after.

## Validation / revisit trigger

Each proved by attempt against a positive control:

1. An assembled context containing a token-shaped string is **refused**, and the identical context
   without it is sent.
2. Host data not selected by the owner or a work item — a journal line, a unit file — **cannot** reach
   an assembled context by any automatic path.
3. A call to a provider not on the approved list is **refused**.
4. Every item in a sent context has provenance recorded.

**Revisit when:** the system holds third-party or personal data — before it is stored; a provider is
added; or the owner's assessment in §1 changes.
