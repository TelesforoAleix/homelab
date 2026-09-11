# ADR-038: Everything runs on the server; the MacBook is a client

- **Status:** Proposed
- **Date:** 2026-09-11
- **Supersedes:** ADR-035 §7's *"The first real Workbench runs on the MacBook"*. The rest of ADR-035
  stands. Extends ADR-023's no-listening-socket property into a bind policy.
- **Superseded by:** none

## Context

ADR-035 decided that Factory Workbench executes project operations and that its first real deployment
would be on the MacBook, with a homelab-hosted deployment as a later, Tailscale-only step. That was
written while ADR-032's content gate forbade project content on the node, so the laptop was the only
place the work could happen.

ADR-037 removes that constraint. With `brain` and the projects on the server, the reason to run
anything on the laptop disappears — and the target architecture calls Home Lab the **always-running**
central system, which a laptop that is closed half the time cannot be.

## Decision

### 1. Every component runs on the reference node

The harness, Factory Workbench, Factory itself, the projects and `brain` all run on the server, inside
the encrypted volume (ADR-037 §5).

**The MacBook is a client and a terminal, not a host.** It holds no part of the running system.

### 2. The harness binds loopback only

Every client of the harness is a **local process** on the same machine: Workbench, the scheduler, the
Telegram bot's integration. None of them needs a network interface.

So the harness listens on `127.0.0.1` and nothing else. This is a stronger position than a
tailnet-bound endpoint: nothing on any network, including the tailnet, can reach it at all.

### 3. Workbench binds loopback; the owner reaches it by SSH tunnel

The one thing needing remote reach is Workbench's **browser interface**, because the person is at the
MacBook and the page is on the server.

Workbench binds `127.0.0.1`, and the owner tunnels over Tailscale. A `LocalForward` line in
`~/.ssh/config` makes it automatic on every `ssh homelab` — configured once.

**This keeps the OS user boundary as the actual boundary**, which is what ADR-035 §7 assumed when it
said local Workbench needs no application login. Tailscale already authenticates the device; adding an
application login on top would be a second authentication system guarding the same door.

### 4. The tailnet-bound upgrade is documented, not taken

Binding the tailnet interface and adding application authentication and secure sessions remains the
path ADR-035 §7 described. It becomes worth taking when a device that **cannot tunnel** needs access —
a phone, or a second person. Not before, because it is new authentication code guarding something a
tunnel already guards.

**Public exposure remains out of scope** and would need its own decision.

### 5. The bot keeps its property; the rule becomes measurable

The Telegram bot long-polls and sends outbound. Notifying the owner is an outbound call to Telegram's
API, so **the bot still opens no listening socket** and ADR-023's property survives intact for it.

What changes is the rule the project measures itself against. *"There are no listening sockets"* was
true of a node running one bot and cannot survive a system with an endpoint. It becomes:

> **Every listening socket is accounted for and bound to a stated interface.**

Today that is: the harness on loopback, Workbench on loopback, SSH on the tailnet. Nothing on the
building LAN, which `ufw` already denies.

## Alternatives considered

**Keep Workbench on the MacBook.** Rejected. It splits the system across two machines, puts the client
where the data is not, and makes the central always-running system depend on a laptop being open.

**Bind the harness to the tailnet.** Rejected as unnecessary once every client is local. A listening
socket that nothing needs is surface for free.

**Bind Workbench to the tailnet now, with application authentication.** Rejected for now. It is real
code, guarding a door the SSH tunnel already guards, for a convenience that a one-line SSH config
entry provides.

**Run Workbench over X11 forwarding or a remote desktop.** Rejected: heavier than a tunnel and worse
in a browser.

## Consequences

**Easier.** One machine holds the system. Backups, encryption, audit and the scheduler all have one
home. The laptop can be closed, replaced or lost without the system stopping.

**Harder.** The node now runs a web service, and **Phase 13 hardening has not happened**. Loopback-only
binding keeps that manageable, but it is a reason to do the encryption first, services second, and not
to leave Phase 13 indefinitely.

**Newly required:** Python and Workbench's dependency on the node; an `~/.ssh/config` entry on the
MacBook; and Workbench must survive the volume being locked by refusing to start rather than starting
empty.

**Constrained:** no component may bind an interface that is not named in §5. Anything that wants to
must amend this ADR.

## Validation / revisit trigger

1. `ss -tlnp` on the node accounts for **every** listening socket, and each is on the interface §5
   names. Checked, not inferred from configuration.
2. The harness is unreachable from the MacBook **directly** over the tailnet — proved by attempt —
   and reachable through the tunnel.
3. Workbench started while the encrypted volume is locked **refuses with a reason**.
4. Closing the MacBook does not stop anything on the node.

**Revisit if:** a device that cannot tunnel needs Workbench, which takes the §4 upgrade; or a client
appears that genuinely is not local, which reopens §2.
