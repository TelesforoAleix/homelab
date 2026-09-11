# ADR-031: Layer boundaries, per-artifact privacy, and standalone public repositories

- **Status:** Accepted
- **Date:** 2026-09-10
- **Supersedes:** the visibility tables in ADR-029 §1 and ADR-030 §1. It generalises ADR-027 §3 and
  leaves ADR-029 §2 intact — §2 was already right, and the tables did not follow it.
- **Superseded by:** none
- **Amended:** 2026-09-10, after the initial draft and before this ADR was merged — see below.

## Amendment, 2026-09-10

Four further decisions were taken later on the same day this ADR was drafted, while it was still
unmerged. They are recorded **in place** rather than in a successor ADR, because this document had
not yet entered the record: there is nothing to supersede. They are marked rather than applied
silently, because a document whose drafting is smoothed out afterwards is exactly the linear history
`PROJECT.md` §11 forbids.

| # | What changed | Where |
|---|---|---|
| 1 | The brain rename and extraction is **deferred as a whole operation** and coupled to the new ingestion pipeline and RAG system. The §5 end state is unchanged; only timing and sequencing change | §6 |
| 2 | The four restored knowledge-base skill files are **superseded legacy, not method** — they stay private | §6.1 |
| 3 | Agent manifests are **JSON**, not YAML. ADR-027 §2 decided five fields, not a serialisation | §11 |
| 4 | **One plan and one progress record, in homelab.** This *replaces* §9's "each repository's own build plan stays in that repository", and closes what §9 left open | §4, §9 |

Each amended section states what it originally said. The Alternatives and Consequences sections carry
amendment notes where a decision recorded there was reversed the same day.

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

**What §9's single plan does and does not mean here (amended 2026-09-10).** §9 now puts one roadmap
and one progress record in homelab. That governs **the owner's own system development** and nothing
else. It does not make Factory un-adoptable, and the two sections are read together as follows:

| Shipped by the public repository | Kept in homelab |
|---|---|
| The method, the contracts, the definitions, and a standalone quickstart | The owner's roadmap and the owner's progress record |

An adopter takes the method, the contracts and the definitions, and **writes their own plan**. What
Factory ships is the contract and the definitions — **never the owner's roadmap**. A plan is an
instance of using the method, not part of it; that is why centralising the plan and requiring
standalone adoptability are not in conflict.

### 5. The topology after this ADR

**This is the end state, and amendment 1 does not change it — it changes when the system arrives
here.** Today `brain` is still the existing private repository under its current name; the two rows
naming `brain` and `aleix-brain` below describe what they become when §6 runs.

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

### 6. The brain rename and split — deferred as a whole operation (amended 2026-09-10)

**What this section said when first drafted:** that the existing private `brain` is renamed
`aleix-brain` and becomes an archive, that its ~32 method files are extracted with `git-filter-repo`
into a new public `brain`, and that only the *ingestion timing* — when content moves in — was
deferred. That is, the rename and the extraction were near-term work with the content move left open.

**Amended the same day: the whole operation is deferred, not just the ingestion timing.**

- The existing private `brain` **stays as it is, under its current name, in active use.** No rename
  now. No extraction now. No content migration now.
- The new public repository — which will take the name `brain` — is **designed and built together
  with the new ingestion pipeline and the RAG system**, not before them. Content migrates at that
  point, into a structure that has actually been designed, rather than being lifted into a repository
  shaped around the old layout.
- **The end state in §5 is unchanged.** Only the timing and the sequencing change. The topology this
  ADR decides is still the topology being built toward.

The mechanics decided above remain the mechanics when this runs, and they are not reopened by the
deferral:

- the rename does not rewrite history and does not change the archive's visibility;
- extraction is a git operation (`git-filter-repo`), never a copy — the ADR-029 and ADR-030 §5
  precedent;
- content written into the new `brain` after the switch has **no version history**, mitigated only by
  the archive retaining everything up to the switch. Accepted, not overlooked.

**Preparation that stands.** The extraction plan at
`projects/factory/handovers/2026-09-10-brain-extraction-plan.md` (private) remains valid preparation
for when this runs, and is the document to start from rather than re-deriving the procedure.

**Its finding about the GitHub rename hazard is carried forward here, because a deferred plan is a
plan nobody is reading:** renaming a repository leaves a GitHub **redirect** at the old name, and
that redirect **dies the moment a new repository claims the old name under the same owner**. From
that moment `.../brain.git` resolves to the *public* repository, so any clone anywhere still carrying
`origin = .../brain.git` is one `git push` away from publishing the private notes, with no undo. The
hazard is **dormant only while nothing claims the old name** — which is precisely the state this
deferral keeps the system in, and precisely the state that ends on the day Phase 21 runs.

#### 6.1 The four restored knowledge-base files are superseded legacy, not method (added 2026-09-10)

`idea-logger`, `session-archiver`, `task-tracker` and the orchestrator README — restored to
`brain/.github/skills/` on branch `fix/restore-brain-knowledge-skills` — describe **processes that
predate the new design and will be replaced by it**.

They are therefore **not method to be published** under §3, and **not live content**. They stay
private in `brain`. Whether they are discarded or reprocessed is decided by the new-brain design
(§6), not before it.

Recorded because it is a classification question two earlier working sessions answered differently:
being restored to a `.github/skills/` path is not what makes a file method. Method is a procedure
someone else could adopt; these describe a workflow this project is replacing.

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

**One plan and one progress record, both in homelab (amended 2026-09-10).**

> **What this said when first drafted, replaced rather than deleted:** *"**Each repository's own
> build plan stays in that repository.** Factory's existing `roadmap.md` V0–V4 series remains
> Factory's."* — followed by *"Not decided here: Factory currently runs a **parallel governance
> system** of its own — `roadmap.md` and the Locked Decisions in `progress.md` — which overlaps
> homelab's. The boundary between the two is not fully drawn, and this ADR does not draw it."*

**Everything is managed through one internal system: homelab.** One `ROADMAP.md`, one progress
record. Factory's `roadmap.md` and the Locked Decisions in `progress.md` are **superseded**.
Retiring them — deciding what content survives into homelab's plan and what was already dead — is
work that belongs to **Phase 20**, the Factory rewrite, because that is the phase already reading
Factory's content end to end.

The overlap the first draft declined to draw a boundary through is not resolved by drawing one. It is
resolved by there being **one system**: two live plans for the same work is how two plans disagree.
This was left open in the first draft, on the reasoning recorded under Alternatives, and **closed the
same day** — the owner's decision, not a finding, and the first draft's reasoning is left standing
above rather than edited to agree with the outcome.

**This does not narrow §4.** The single plan governs *the owner's own* system development. What
Factory ships to an adopter is the contract, the method and the definitions, never the owner's
roadmap; an adopter writes their own plan. See §4, which states the split explicitly.

### 10. This ADR is ADR-029's revisit, and it says so

ADR-029's revisit trigger — *"a fifth kind of content appears that fits none of the four
repositories"* — fired. Knowledge-base method is that fifth kind. Recording that explicitly matters
more than the outcome: a revisit trigger that fires and is not named as having fired is a trigger
nobody will trust the next time.

### 11. Agent manifests are JSON (added 2026-09-10)

**ADR-027 §2 illustrates the five-field manifest in YAML. It decided five fields, not a
serialisation.** The serialisation is decided here: **agent manifests are JSON.**

Three reasons, in the order they were given:

1. **JSON is what the models handle natively.** A manifest is written and read by models more often
   than by hand; that is the owner's stated reason and it is the deciding one.
2. **The zero-third-party-dependency constraint.** The Telegram bot has held that constraint since
   Phase 07 (`bot.py:21-26`). Python's standard library ships `json` and **no YAML parser**, so YAML
   means either a dependency in the one service that talks to the internet, or a hand-rolled parser
   in the process that enforces authorisation. Both are worse than the format preference is worth.
3. **It costs nothing to reverse in the cheap direction.** If YAML is ever wanted for Factory-side
   ergonomics, the conversion belongs on the Factory side, where a dependency enforces nothing.

**ADR-027 is not edited.** It is accepted and merged, and `docs/decisions/README.md` forbids
rewriting an accepted ADR. This section is where the serialisation is decided; ADR-027 §2's YAML
example is an illustration of the field set and should be read as one.

`docs/handovers/19-tool-vocabulary.md` §6.5 carried this as a *recommendation* while it was open. It
now states it as decided, citing this section.

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

> **Reversed the same day (amendment 4, 2026-09-10).** The rejection above is left as written because
> it is what the first draft reasoned. It was wrong about the available move: the question was read
> as *where does the boundary fall*, which genuinely needed evidence, when the answer available
> without evidence was *there is no boundary because there is one system*. §9 now decides that.
> Recorded rather than deleted, per `PROJECT.md` §11.

**Defer only the ingestion timing, and do the rename and extraction now (the first draft's §6).**
Rejected by amendment 1 on the day: it builds the new public repository around the shape of the
current one, and then the ingestion design — which has not been done yet — either accepts a structure
chosen for it or reshapes a repository that already has history. It also arms the GitHub redirect
hazard (§6) months before anything needs it armed, for no gain in the meantime.

## Consequences

**Easier:** "which repository does this belong in?" becomes a question about one artifact rather than
a negotiation about a directory. The knowledge base's method becomes usable by other people. The tool
versus skill question has a one-sentence answer that can be applied without reading four ADRs.

**Harder / newly required:** three public repositories now need standalone quickstarts, and none has
one. That is new documentation debt created by this decision, not discovered by it.

**Newly required, when §6 runs (amended 2026-09-10):** a rename of a repository that other things
already reference. Every reference to `brain` in the private knowledge base and in the four preceding
ADRs will then point at either the archive or the new public repository, and which one is meant
depends on the date the reference was written. Records are not rewritten (`PROJECT.md` §11,
ADR-030 §4); live documents are. **Until §6 runs, `brain` means what it has always meant** — the
existing private repository under its current name — and no reference needs disambiguating yet.

**Accepted, not mitigated:** content written into the new `brain` after the switch has no version
history (§6).

**Constrained:** Factory cannot be rewritten until homelab publishes its tool vocabulary, which makes
one homelab deliverable the critical path for the whole method layer.

**Newly required by amendment 4:** Phase 20 now also has to retire Factory's `roadmap.md` and the
Locked Decisions in `progress.md` into homelab's single plan, deciding per item what survives. That
is work the first draft of §9 did not create.

**Deferred (amended 2026-09-10):** the brain rename and method extraction **as a whole operation**,
coupled to the new ingestion pipeline and RAG system (§6) — this replaces the narrower deferral of
only the ingestion timing; and the dashboard/control-plane move from Factory to homelab, which was
agreed but has **never had an ADR** and depends on Factory's post-rewrite schema.

**No longer deferred:** the Factory-versus-homelab governance boundary. §9 decides it — one system,
in homelab.

**Still open from ADR-030:** where session logs live once `05-logs/` outlives the repository it was
written in. This ADR does not answer the question, and after amendment 1 it does not rename the
repository either — so the question stays exactly where ADR-030 left it, with no new pressure on it.

## Validation / revisit trigger

Revisit if:

- the §2 test — *refusable means homelab* — proves ambiguous for a real capability, which would mean
  the tool/skill split needs a third category rather than a sharper test;
- an artifact appears whose privacy cannot be decided per-artifact because its value depends on
  sitting next to private content, which would mean §3 is too fine-grained;
- the standalone requirement in §4 turns out to be unachievable for one of the three public
  repositories without duplicating the other two.

**Validation required before this ADR is considered implemented**, each proved against a positive
control rather than observed to pass. **Items 1–3 concern §6, which amendment 1 defers as a whole
operation: they are the gate on the day Phase 21 runs, not outstanding work now.** Item 4 is
Phase 19's and is due now.

1. Each of the three public repositories has a **quickstart that works standalone**, executed from a
   clean clone with no sibling repository present. Two of the three exist today; the third is created
   by §6 and is validated when it is.
2. The new public `brain` contains **no file from `01-knowledge`, `05-logs`, `00-inbox` or
   `02-ideas`** — checked by the ADR-029 §5 boundary gate, which must itself be validated against
   planted content before it is trusted.
3. `aleix-brain` has the **same commit count and the same tracked-file list** after the rename as
   before it — proving the history was not rewritten.
4. A capability classified as a skill is confirmed to have **nothing the runtime could refuse**, and
   one classified as a tool is confirmed to be **refusable at dispatch** — the §2 test applied to a
   real pair rather than asserted.
