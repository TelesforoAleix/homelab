# Constraint Review — do our accepted decisions still serve the target architecture?

- **Written:** 2026-09-11
- **Status:** Analysis. **Decides nothing.** Every accepted ADR below remains in force until a
  successor ADR changes it.
- **Companion to:** [`target-architecture.md`](target-architecture.md)

## Why this review exists

The target architecture describes what the system should be. Most of our accepted decisions were
taken for a smaller system — a node, a bot, a model helper — and several of them now constrain layers
that did not exist when they were written.

A constraint written for a bot is not automatically wrong for a harness. But it is not automatically
right either, and the difference matters most now, while nothing has been built on top of it.

**The test applied to each:** does this decision still protect what it was written to protect, and is
that protection still worth what it costs the architecture?

---

## A. ADR-032 §2 — the content gate

**Says.** Until encryption is revisited and executed, the node must not hold the knowledge base, any
project repository, product source or `ops/` record — *including a derived index or embedding*.

**Costs the architecture.** Layers 5 and 6 cannot do their job on the node. And the collision is
sharper than "one phase is blocked":

> The target says Home Lab is **always running** and **holds the knowledge**.
> The gate says the knowledge cannot be on the machine that is always running.

Every workaround inherits that contradiction. Running the harness on the MacBook puts the knowledge
on a laptop that is closed half the time, which is not an always-running central system — it is a
personal tool with a server attached.

**Is the protection still right?** The protection is real: an unencrypted disk in a shared building,
on a machine with no attached monitor. Nothing about that has changed.

**But "revisit" was deferred, not answered.** Phase 18 measured the ground and stopped:

- the console exists and works, so **passphrase-at-boot is viable**;
- the TPM is 2.0 and enrolment works, but only against the **SHA-1** bank;
- the volume group has **zero free extents**, so an encrypted volume has nowhere to live.

**Verdict: the gate is correctly placed and should not be loosened. The decision it defers should be
taken.** Routing around it produces a system that contradicts its own definition. The honest options
are a reinstall with full-disk encryption, adding storage for an encrypted volume, or accepting that
the knowledge layer lives elsewhere permanently — and the third is a different architecture, not a
workaround.

**Question for the owner: 1, 2.**

---

## B. ADR-025 §8 — what may leave the machine

**Says.** The question, plus the literal output of `/status`. Nothing else. *"Widening this requires
its own ADR."*

**Costs the architecture.** Layer 6's entire job is deciding what the model sees, and under §8 the
answer is "almost nothing". No retrieved document, no file, no repository content, no assembled
context.

**Is the protection still right?** Yes, and the reasoning is worth keeping: journal lines are written
by other software, some of it network-reachable, so feeding them to a model means unbounded host data
leaving, *selected by whatever can write a log line rather than by the owner*. That argument survives
completely.

**But §8 is an enumeration where the architecture needs a policy.** A list of two permitted items
cannot express "project files the work item names, at a stated revision, with provenance, to an
approved provider". Extending the list item by item would mean an ADR per content type forever.

**Verdict: supersede, with a policy that preserves §8's reasoning.** The successor states *classes*
of content, who selects them, to which providers, under what approval — and keeps the rule that
content selected by something other than the owner or an approved agent never leaves. ADR-033 §6
already names this as the immediate next decision.

**Question for the owner: 3.**

---

## C. ADR-025 §9 — owner-initiated only

**Says.** Every model call traces to a message the owner just sent. Superseded by ADR-026 on
2026-09-10: subscription providers may serve unattended calls **as an accepted risk**, per provider.

**Costs the architecture.** Nothing directly — it is already lifted. But the thing it substituted for
is still unanswered: **the licensing question**. §9 existed to keep subscription usage shaped like a
human using their own subscription interactively.

The scheduler makes this heavier, not lighter. "Always running, wakes on a schedule" is precisely the
pattern §9 was written to avoid, and the accepted risk scales with how much autonomous work we do.

**Verdict: not wrong, but the interim is load-bearing and should be made deliberate.** There is a
clean rule available now that did not exist when §9 was written, because ADR-033 settled a metered
provider:

> **Unattended work runs on metered inference. Subscription inference serves attended work.**

A paid API has no licensing ambiguity. That converts an accepted risk into a routing rule the model
selector can enforce structurally — and it gives layer 7 a real input it does not currently have.

**Question for the owner: 4.**

---

## D. ADR-020 — change safety on a "console-less node"

**Says.** The node has no console, so any change touching network, remote access, authentication,
boot or the admin account must be classified before it is made.

**The premise is now false.** Phase 18 found the node always had a console — `getty@tty1` active,
connectors present, login authenticated at `seat0/tty1`. The monitor and keyboard were then removed,
so the node is physically headless, but the console *capability* exists and has been tested as the
recovery path.

`AGENTS.md` still states flatly: *"The reference node has no console."*

**Costs the architecture.** Little directly, but it distorts risk judgement in every phase that reads
it. A change that is lockout-class with no recovery path is a different decision from one where
recovery means walking to the machine with a monitor.

**Verdict: the rule stands; the premise must be corrected.** Classification before change is right for
a headless node regardless. Amend the premise and `AGENTS.md` so the recovery path is stated
accurately, and keep the classification requirement exactly as it is.

---

## E. ADR-023 — the bot has no listening socket

**Says.** The Telegram bot long-polls, so it opens no listening socket. `ss -tln` was byte-identical
to phase start.

**Costs the architecture.** The harness is an **always-listening endpoint**. It will be the node's
first real listening service, and the property ADR-023 protected cannot be preserved as stated.

**Is the protection still right?** The intent was to add no network-facing surface. That intent is
right and achievable; the specific mechanism — never listen — is not, once other machines and clients
must reach the system.

**Verdict: extend, do not discard.** The successor states a **bind policy**: loopback by default,
tailnet-only where remote access is needed, never the shared LAN, never public. It interacts with
ADR-019 (tailnet), the `ufw` rules already in place, and Phase 13. The measurable property becomes
"every listening socket is accounted for and bound to a stated interface" rather than "there are
none".

**Question for the owner: 5.**

---

## F. ADR-031 §4 — homelab must be independently adoptable

**Says.** *"Someone else must be able to take `homelab` alone"* and run it on their own
infrastructure. Made a validation criterion: each public repository needs a standalone quickstart.

**Costs the architecture.** This is the least examined constraint and possibly the most expensive.
Adoptability is an abstraction tax paid at every layer: configuration for things we have exactly one
of, indirection around our own inference sources, and a knowledge layer that must work for a
knowledge base that is not ours.

For **Factory** the requirement is clearly right — it is method, it is fork-and-customise, and
Phase 20.0 proved it by running from a clean clone.

For **homelab** the case is much weaker. A personal AI operating system that holds *your* knowledge,
routes to *your* inference sources and enforces *your* budgets is not a thing a stranger installs.

**Verdict: challenge it.** The defensible version is narrower — **the method is public and
readable; the system is not packaged for adoption.** That keeps ADR-021's publication decision and
ADR-029's method/output boundary intact while removing an abstraction tax on every layer.

**Question for the owner: 6.**

---

## G. ADR-017 — self-contained sequential phases

**Says.** Phases are self-contained and sequential. There is no separate planning context. Each phase
writes its own brief and records cross-phase changes as ADRs.

**Costs the architecture.** Governance — identity, budgets, approvals, audit, trust state — runs under
all nine layers. In a strictly sequential model a cross-cutting concern is either built once and early
against requirements nobody has yet, or rebuilt in every phase that needs it.

There is already evidence of the strain: approvals, budgets, audit and identity were implemented in
Phase 20.0 inside Factory Workbench, and the same concerns appear again in the Phase 23 brief for the
harness. Two implementations of "what an approval is" is the same failure as two YAML parsers.

**Verdict: amend, narrowly.** Sequential phases stay. Add that **cross-cutting concerns are built once
as a shared contract and consumed by later phases**, and that a standing architecture document is a
legitimate artifact rather than the separate planning context ADR-017 abolished. This review and the
target architecture are already that artifact; the rule should catch up with the practice.

**Question for the owner: 7.**

---

## H. ADR-033 §5 — the spend governor

**Says.** Four windows (hour, day, week, month), separate attended and unattended budgets, checked
before the call, persisted, failing closed.

**Costs the architecture.** Nothing — it is a floor, not a ceiling. But it was specified before
decomposition existed, and **decomposition multiplies calls**: one request becoming nine steps is nine
calls against a budget shaped for one.

**Verdict: stands; extend at implementation.** Add per-request and per-step envelopes that nest inside
the global windows, so a decomposed request cannot consume a day's budget by splitting itself. That is
an extension of §5, not a contradiction of it.

---

## I. ADR-034 — agents, capabilities and tools, but not services

**Says.** Factory agents declare portable capabilities; backends provide concrete tools; mappings
between them are human-approved security decisions.

**Costs the architecture.** Layer 4 routes to **services** — web research, knowledge retrieval, code
execution, a specialist agent. A service is a long-lived provider of a capability; a tool is a single
callable action. ADR-034 covers agents, capabilities and tools, and is silent on services.

**Verdict: a gap, not an error.** It will be filled correctly by whichever phase builds layer 4,
provided the distinction is stated before then rather than discovered by conflating the two. The risk
is a tool registry quietly becoming a service registry.

---

## Summary

| | Constraint | Verdict |
|---|---|---|
| A | ADR-032 §2 — content gate | **Correctly placed. Take the deferred decision** rather than routing around it |
| B | ADR-025 §8 — egress | **Supersede** with a policy that preserves its reasoning |
| C | ADR-025 §9 — owner-initiated | Lifted already; **make the interim deliberate** — unattended runs metered |
| D | ADR-020 — console-less node | **Rule stands, premise is false.** Correct it, and `AGENTS.md` |
| E | ADR-023 — no listening socket | **Extend** to a bind policy |
| F | ADR-031 §4 — homelab adoptable | **Challenge.** Likely narrow to "public and readable, not packaged" |
| G | ADR-017 — sequential phases | **Amend** for cross-cutting concerns and a standing architecture document |
| H | ADR-033 §5 — spend governor | Stands; **extend** with nested per-request envelopes |
| I | ADR-034 — services | **Gap.** State the service/tool distinction before layer 4 is built |

**Unchanged and not challenged:** ADR-011 (privilege separation), ADR-025 §1 (credential boundary),
ADR-026 §4 (the agent declares a need), ADR-013, ADR-021, ADR-029 §2, ADR-030.

## Questions this review cannot answer

1. **Encryption.** Reinstall with full-disk encryption, add storage for an encrypted volume, or accept
   that knowledge lives off the node permanently? The third is a different architecture.
2. If knowledge must live off the node for now, **is "always running" still a requirement**, or does it
   become a target for after encryption?
3. **What classes of content may leave the machine**, to which providers, under what approval?
4. **Should unattended work run exclusively on metered inference**, leaving subscriptions for attended
   work?
5. **Which interface should the harness listen on** — loopback only with clients tunnelling, or
   tailnet?
6. **Does homelab need to be adoptable by anyone else**, or only public and readable?
7. Should **cross-cutting governance be built once as a shared contract**, and where does it live —
   given one implementation already exists inside Factory Workbench?
