# ADR-041: Change safety — the node has a console on demand

- **Status:** Proposed
- **Date:** 2026-09-11
- **Supersedes:** ADR-020 in full
- **Superseded by:** none

## Context

ADR-020 is titled *"Change safety policy for a console-less node"*. Its premise was that the node had
no console, so any change touching network, remote access, authentication, boot or the admin account
could lock the owner out permanently.

**The premise is false, and Phase 18 proved it.** The node always had a console: `getty@tty1` active,
connectors present, login authenticated at `seat0/tty1`. The Phase 18 handover records it plainly as
one of three of its own premises that turned out wrong. The monitor and keyboard are detached **by
choice**, and reattaching them is a minute's work.

`AGENTS.md` still states as fact: *"The reference node has no console."*

Two things follow. The rule has been applied at a severity the real risk does not justify, and it has
cost friction disproportionate to what it protects. And a document the project treats as authoritative
asserts something known to be untrue.

## Decision

### 1. State the recovery path accurately

The node is **headless by choice, with a console available on demand**. Connectors are present, the
getty is active, and console login has been tested as a recovery path. The monitor stays detached
because it is not needed, not because it cannot be attached.

`AGENTS.md` is corrected to say this.

### 2. Classification before change stays

Any change touching **network, remote access, authentication, boot, or the admin account** is still
classified before it is made. That habit is cheap and has caught real problems, and it is right for a
machine nobody is sitting in front of.

### 3. "Lockout-class" is redefined

It stops meaning *unrecoverable* and starts meaning:

> **Recovery requires physical access to the machine.**

That is a **cost, not a catastrophe** — a walk to the machine and a monitor. The controls scale to it:
such a change is made deliberately, with the recovery step known in advance, and preferably when the
owner can reach the machine. It does not need the ceremony of an operation that cannot be undone.

### 4. Genuinely unrecoverable operations keep the highest bar

Destroying the only copy of data, or an operation that cannot be reversed by any physical access,
keeps the strictest treatment. ADR-037's shrink is the current example: a `lvreduce` below the
filesystem size destroys the filesystem, and no console recovers from that. A verified restore
immediately beforehand is the control, not classification alone.

**The distinction this ADR draws is between "needs a walk" and "needs a backup".** ADR-020 treated
them the same, which is why it cost more than it protected.

## Alternatives considered

**Deprecate ADR-020 without replacing it.** Rejected. A deprecated decision with nothing in its place
leaves the next phase to invent a policy, and the classification habit is worth keeping.

**Amend ADR-020 in place.** Rejected by the project's own rule against rewriting accepted ADRs, and
because the premise sits in its title.

**Drop change classification entirely.** Rejected. The node is still headless in practice, the console
is still a deliberate trip, and a boot or authentication change that goes wrong still stops remote
work until someone acts.

## Consequences

**Easier.** Changes touching network and boot stop carrying worst-case ceremony. Work that was
deferred out of caution — ADR-037's shrink among it — becomes proportionate to plan.

**Harder, in the right place.** The distinction between "needs physical access" and "needs a backup"
has to be made honestly each time, which is a judgement rather than a checklist.

**Corrected:** `AGENTS.md` and `docs/standards/safe-changes-headless.md` must stop asserting the node
has no console. The standard's checklist stays; its premise changes.

**Preserved:** ADR-020 is not deleted. It records why the rule existed and what it cost, and Phase 18's
finding is more legible with the original in front of it.

## Validation / revisit trigger

1. Console login still works — re-tested when the monitor is next attached, not assumed from Phase 18.
2. `AGENTS.md` and the safe-changes standard state the recovery path accurately.
3. The next network-, boot- or authentication-touching change records its classification and its
   recovery step, and the recovery step is one someone could actually perform.

**Revisit if:** the node moves somewhere the owner cannot reach quickly, which restores ADR-020's
original premise; or a remote-hands arrangement replaces physical access, which changes what "physical
access" costs.
