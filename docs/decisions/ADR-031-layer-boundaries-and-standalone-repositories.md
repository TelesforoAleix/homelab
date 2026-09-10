# ADR-031: Layer boundaries, per-artifact privacy, and standalone public repositories

- **Status:** Accepted
- **Date:** 2026-09-10
- **Supersedes:** the visibility tables in ADR-029 §1 and ADR-030 §1. It generalises ADR-027 §3 and
  leaves ADR-029 §2 intact — §2 was already right, and the tables did not follow it.
- **Superseded by:** none

## Context

ADR-027, ADR-028, ADR-029 and ADR-030 were written on the same day and each answered a different
question: how an agent is declared, how a project carries its own state, which repositories exist,
and what the four layers are. An alignment session held on 2026-09-10 read them together and found
three things that only become visible when the four are read as one system.

**The first is that ADR-027 §3 was written too narrowly.** It says "Factory declares; homelab
enforces" about the tool vocabulary. That sentence is not really about tools. It is the ownership
rule for the whole system, and it was recorded as if it were a detail of manifest loading.

**The second is that the word "tools" is doing three jobs at once**, and the resulting confusion has
already cost time: ADR-027 §2's manifest has both a `skills:` field and a `tools:` field, and nothing
in the ADR says how to tell which of the two a given thing is.

**The third is that repository boundaries were used as privacy boundaries.** ADR-029 §2 states the
rule correctly — *method public, output private* — and then ADR-029 §1 and ADR-030 §1 both put the
knowledge base wholly on the private side. Not because its method is private; because its method and
its content happened to share a repository. Measurement on the day: of 499 tracked files in `brain`,
464 are private content (`01-knowledge`, `05-logs`, `00-inbox`, `02-ideas`) and roughly 32 are method
(`.github/` skills, evals, templates, the metadata schema, the source taxonomy, and `scripts/`). A
repository-level visibility decision made those 32 files private by adjacency.

**ADR-029's own revisit trigger has fired.** It said to revisit if *"a fifth kind of content appears
that fits none of the four repositories."* Knowledge-base *method* is that fifth kind: it is not the
runtime, not the operating model, not a project, and not knowledge content. This ADR is that revisit.

## Decision

### 1. The boundary rule, stated for the whole system

ADR-027 §3 generalises. It was written about tools; it governs everything:

> **Factory declares. Homelab enforces. Projects accumulate. Brain supplies.**

| Layer | Owns | Meaning |
|---|---|---|
| Factory | the nouns and the rules | What a ticket is, what states it has, what the approval levels are, what a reviewer may not do |
| Homelab | the verbs and the refusals | Executing, and denying |
| Projects | the records | What actually happened, per project |
| Brain | the raw material | What is known, and where it came from |

Factory is **fully operational as a specification** and never executes. That is not a gap in Factory
to be closed later; it is what Factory is. The same asymmetry ADR-027 §3 gives as its reason applies
whole: enforcement written into the thing being enforced is not a contract.

### 2. The test that separates a tool from a skill

> **If it can be refused, it's homelab. If it can only be followed, it's factory.**

A **tool** is a capability the runtime can deny at dispatch. A **skill** is a procedure that grants
no privilege, so there is nothing to deny.

Three different things share the name "tools", and they do not live in the same place:

| The thing | Where it lives | Contract |
|---|---|---|
| The tool vocabulary and its capability levels | `homelab` | ADR-027 §3, §5 |
| The tool implementations | `homelab`, behind `Router.dispatch()` | ADR-027 §4 |
| Skills | `factory`, as the `skills:` manifest field | ADR-027 §2 |

### 3. Privacy is per-artifact, not per-repository

ADR-029 §2 already says *method public, output private*. This ADR makes the unit of that decision the
**artifact**, not the repository, and supersedes the ADR-029 §1 and ADR-030 §1 visibility tables
accordingly.

The refinement, in two parts:

- **Secrets and regenerable local configuration** are gitignored with a committed `.example`
  alongside them. This is the pattern homelab already runs at small scale —
  `services/telegram-bot/allowlist.example` is committed and the real allowlist never is.
- **Content of lasting value** gets its own private repository, because it is not regenerable and an
  `.example` cannot stand in for it.

### 4. Each public layer must be independently adoptable

Someone must be able to take `factory` plus a knowledge base, without `homelab`, and run them on
their own infrastructure. Someone else must be able to take `homelab` alone.

This has been a stated requirement since the layers were named. This ADR makes it a **validation
criterion**: each public repository needs a quickstart that works standalone. **None currently has
one.**

### 5. The topology after this ADR

Three public **method** repositories, each of which stands alone:

| Repository | Visibility | Holds |
|---|---|---|
| `homelab` | public | The runtime |
| `factory` | public | The operating model |
| `brain` | public | Knowledge-base method — **new; does not yet exist** |

Plus N private **content** repositories:

| Repository | Visibility | Holds |
|---|---|---|
| `aleix-brain` | private | The existing private knowledge base, renamed from `brain` |
| `projects/<name>` | private, one each | The product, plus its `ops/` (ADR-030 §2) |

### 6. The brain rename and split

The existing private `brain` repository — 404 commits, 499 tracked files — is **renamed
`aleix-brain`** and becomes an archive. Its history is **not** rewritten and its visibility does
**not** change.

Its ~32 method files (`.github/` skills, evals, templates, the metadata schema, the source taxonomy;
`scripts/`) are extracted with `git-filter-repo` into a **new public repository taking the name
`brain`**. This is the ADR-030 §5 precedent applied again: extraction with git operations, not
copying.

Long term, `brain` becomes the working knowledge base — public method plus gitignored private
content, per §3 — and `aleix-brain` remains the archive.

**Recorded explicitly as an accepted consequence:** content written into the new `brain` after that
switch has **no version history**. The mitigation is that `aleix-brain` retains everything up to the
switch. This is accepted, not overlooked.

**The ingestion timing is deliberately deferred** — when content moves into the new `brain` is not
decided here.

### 7. Factory is rewritten in a dedicated phase

Factory's **content is kept**. Its markdown-heavy **format is discarded**: it was designed for a
different environment than the one it now has to run in.

**Nothing is to be written into the current format.**

**Prerequisite:** homelab must first publish its named tool vocabulary and capability levels, so the
rewrite has something to compose against. ADR-027 §3 puts the vocabulary in homelab, and ADR-027 §5
makes an unknown tool name a hard load failure — which means a rewrite done before the vocabulary
exists would either name tools that cannot load or invent a vocabulary in the wrong repository.

### 8. Project documentation stays in the project repository

This restates ADR-028 §2 — *"a project repository must be readable on its own"* — as a rule about
documentation specifically.

Only what **generalises** reaches the knowledge base, and it gets there through the existing
`ops/learning/` promotion path rather than by being written there in the first place.

The test: **would this help someone who does not have this project?**

### 9. Governance split

**Contracts between layers live in homelab**, because homelab is what enforces them. ADR-027,
ADR-028, ADR-029, ADR-030 and this ADR are all of that kind.

**Each public repository additionally carries a normative specification of the contract it must
satisfy**, so that it is usable standalone per §4. Homelab holds the decision and its reasoning; the
repository holds the format.

**Each repository's own build plan stays in that repository.** Factory's existing `roadmap.md`
V0–V4 series remains Factory's.

Not decided here: Factory currently runs a **parallel governance system** of its own — `roadmap.md`
and the Locked Decisions in `progress.md` — which overlaps homelab's. The boundary between the two is
not fully drawn, and this ADR does not draw it.

### 10. This ADR is ADR-029's revisit, and it says so

ADR-029's revisit trigger — *"a fifth kind of content appears that fits none of the four
repositories"* — fired. Knowledge-base method is that fifth kind. Recording that explicitly matters
more than the outcome: a revisit trigger that fires and is not named as having fired is a trigger
nobody will trust the next time.

## Alternatives considered

**Leave the visibility tables alone and treat brain's method as private.** Zero work, and it is the
status quo. Rejected: it makes ADR-029 §2 false in practice while true on paper, and it forecloses
§4 — a knowledge base whose method is private cannot be adopted by anyone.

**Publish brain's method by copying the ~32 files into a new repository.** Simpler than
`git-filter-repo`, and it loses every commit that produced them. Rejected on ADR-029's own
"git operations, never copying" consequence and ADR-030 §5's precedent.

**Rewrite `brain`'s history to remove the private content, then flip the existing repository
public.** It would keep one repository and one history. Rejected outright: rewriting the history of a
repository containing 464 files of private content in order to publish it is the highest-risk
possible way to cross a privacy boundary, and a missed file is unrecoverable once pushed. Renaming to
an archive and extracting forward keeps the private repository private by construction.

**Keep Factory's markdown format and migrate it incrementally.** Attractive because nothing stops
working mid-way. Rejected: incremental migration means continuing to write into the format being
discarded, which is exactly what §7 forbids, and the volume grows faster than the migration.

**Rewrite Factory first and derive homelab's tool vocabulary from what the rewrite turns out to
need.** Rejected: it puts the vocabulary's design in the repository that does not enforce it, which
is the alternative ADR-027 already rejected outright.

**Draw the Factory-versus-homelab governance boundary now, in this ADR.** Rejected as guessing. The
overlap is real but its shape is not yet known, and this project's recorded failure mode is documents
asserting more than they can support.

## Consequences

**Easier:** "which repository does this belong in?" becomes a question about one artifact rather than
a negotiation about a directory. The knowledge base's method becomes usable by other people. The tool
versus skill question has a one-sentence answer that can be applied without reading four ADRs.

**Harder / newly required:** three public repositories now need standalone quickstarts, and none has
one. That is new documentation debt created by this decision, not discovered by it.

**Newly required:** a rename of a repository that other things already reference. Every reference to
`brain` in the private knowledge base and in the four preceding ADRs now points at either the archive
or the new public repository, and which one is meant depends on the date the reference was written.
Records are not rewritten (`PROJECT.md` §11, ADR-030 §4); live documents are.

**Accepted, not mitigated:** content written into the new `brain` after the switch has no version
history (§6).

**Constrained:** Factory cannot be rewritten until homelab publishes its tool vocabulary, which makes
one homelab deliverable the critical path for the whole method layer.

**Deferred:** the ingestion timing for the new `brain` (§6); the Factory-versus-homelab governance
boundary (§9); and the dashboard/control-plane move from Factory to homelab, which was agreed but has
**never had an ADR** and depends on Factory's post-rewrite schema.

**Still open from ADR-030:** where session logs live once `05-logs/` outlives the repository it was
written in. This ADR renames that repository without answering the question.

## Validation / revisit trigger

Revisit if:

- the §2 test — *refusable means homelab* — proves ambiguous for a real capability, which would mean
  the tool/skill split needs a third category rather than a sharper test;
- an artifact appears whose privacy cannot be decided per-artifact because its value depends on
  sitting next to private content, which would mean §3 is too fine-grained;
- the standalone requirement in §4 turns out to be unachievable for one of the three public
  repositories without duplicating the other two.

**Validation required before this ADR is considered implemented**, each proved against a positive
control rather than observed to pass:

1. Each of the three public repositories has a **quickstart that works standalone**, executed from a
   clean clone with no sibling repository present.
2. The new public `brain` contains **no file from `01-knowledge`, `05-logs`, `00-inbox` or
   `02-ideas`** — checked by the ADR-029 §5 boundary gate, which must itself be validated against
   planted content before it is trusted.
3. `aleix-brain` has the **same commit count and the same tracked-file list** after the rename as
   before it — proving the history was not rewritten.
4. A capability classified as a skill is confirmed to have **nothing the runtime could refuse**, and
   one classified as a tool is confirmed to be **refusable at dispatch** — the §2 test applied to a
   real pair rather than asserted.
