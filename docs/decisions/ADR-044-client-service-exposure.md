# ADR-044: A declared capability is not a granted authorization

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** none. **Extends** ADR-034 with a boundary it does not cover.
- **Superseded by:** none

## Context

ADR-034 defines what a Factory agent declares — portable **capabilities** — and what a backend
provides — concrete **tools** — with the mapping between them a human-approved security decision.

The target architecture adds a third thing it does not cover. Layer 4 routes work to **services**: web
research, knowledge retrieval, code execution, a specialist agent. A service is a long-lived provider
of a capability; a tool is a single callable action. ADR-034 is silent on services, and the obvious
failure is a tool registry quietly becoming a service registry.

The owner's example makes the gap concrete. Suppose one of the services is *restart the server*. An
agent in Factory might reasonably declare a server-management capability. **That must not make the
service reachable**, because the request is arriving from Factory — a client — and Factory has no
business restarting the machine it runs on, whatever its agents claim to be for.

## Decision

### 1. Two different questions, answered in two different places

> **Factory declares what an agent is for. Home Lab decides what it will do.**

| Question | Answered by | Scope |
|---|---|---|
| What is this agent permitted to attempt? | The agent's declared capabilities (ADR-034) | One agent |
| Which services can this **client** reach at all? | Home Lab's client exposure policy | Every request from that client |

A declared capability is a **statement of purpose**. It never grants anything.

### 2. Client exposure is checked first, and it is the stronger boundary

Every request carries the client it came from — attached by layer 1's runtime, never claimed by the
request (ADR-034 §11). Before any agent capability is considered, the request is checked against what
that client may reach.

**The two refusals are different and must say so.** *"Factory cannot reach this service"* is not the
same as *"this agent lacks that capability"*, and collapsing them into one message makes the boundary
impossible to reason about.

Checking exposure first also means an agent's declaration never even needs evaluating for a service
its client cannot touch.

### 3. System control is not reachable from work clients

Services that operate the machine — restart, power, storage, network, the encrypted volume — are not
exposed to Factory, or to any client whose job is doing work on projects.

This is not a statement about trust in Factory. It is that **a client which orchestrates autonomous
agents is the wrong place to accept an instruction that can take the system offline**, regardless of
what approval sits behind it.

### 4. Exposure is configuration, and a default of nothing

A client reaches the services it is explicitly granted. An unlisted service is a refusal, not an
omission — the same rule ADR-034 §14 applies to tools, and the same reason: a default that permits is
a boundary nobody notices is missing.

### 5. The service / capability / tool distinction is stated before layer 4 is built

| | Owned by | Granularity |
|---|---|---|
| **Capability** | Factory | What an agent is for. Portable. Grants nothing |
| **Service** | Home Lab | A long-lived provider, reachable or not per client |
| **Tool** | Home Lab | One callable action a service exposes |

Written down now because the cost of conflating them is paid later, when a registry has to be split
after things depend on it.

## Alternatives considered

**Rely on capability checks alone.** Rejected — it makes Factory's declarations load-bearing for
system safety, and Factory is fast-moving fork-and-customise software. ADR-027 rejected the same shape
for tools and this is the same argument one level up.

**Rely on approvals at the moment of action.** Rejected as the *only* control. Approval is a good last
gate and a poor first one: it puts the owner in the path of every refusal that should never have been
a question, and approval fatigue is how bad approvals get granted.

**One registry for services and tools.** Rejected. They have different lifetimes and different
authorization questions, and the merge is very hard to undo once anything depends on it.

## Consequences

**Easier.** Layer 4 has a boundary to enforce that does not depend on any client behaving well. New
clients start with no exposure, which is the safe direction.

**Harder.** There is a second policy to maintain, and it must not drift from the capability model.
Two refusal paths mean two sets of tests, each with its positive control.

**Constrained:** system-control services are unreachable from work clients regardless of capability,
approval or agent identity. Changing that is an amendment to this ADR, not a configuration change.

## Validation / revisit trigger

Each proved by attempt against a positive control:

1. A request from Factory naming a system-control service is **refused on client exposure**, and the
   refusal says so rather than reporting a missing capability.
2. The same service, invoked by a client that is exposed to it, **succeeds** — otherwise the refusal
   proves only that nothing works.
3. An agent declaring a capability its client cannot reach is refused **without** the capability being
   evaluated.
4. A service not listed for a client is refused **by default**, with no explicit deny rule present.

**Revisit if:** a legitimate case appears for a work client to reach system control, which would mean
§3 is too broad; or services and tools turn out to be the same granularity in practice, which would
mean §5 invented a distinction that does not pay for itself.
