# ADR-020: Change safety policy for a console-less node

- **Status:** Superseded
- **Date:** 2026-09-09
- **Supersedes:** none
- **Superseded by:** **ADR-041** (2026-09-11), in full. **This ADR's premise is false**: Phase 18
  found the node always had a console — `getty@tty1` active, login authenticated at `seat0/tty1`.
  The classification habit survives in ADR-041; what changes is that "lockout-class" means *recovery
  requires physical access* rather than *unrecoverable*. **Kept as written** — it records why the rule
  existed and what it cost.

## Context

Phase 03 removed the reference node's monitor, keyboard and DisplayPort→HDMI cable. All six DRM
connectors report `disconnected`. The node is genuinely headless.

This closed a real risk and created a different one. Phases 01 and 03 both used the attached console
as their ultimate fallback, and both **sequenced their riskiest steps around it**: Phase 01 installed
the operating system with a monitor in front of it, and Phase 03 deliberately deferred removing the
console until after key-only SSH had been proved from a second machine. Neither phase wrote that
reasoning down as a rule, because in both cases the fallback was sitting on the desk.

From Phase 02 onward it is not. A change that breaks networking, `sshd`, authentication or boot is no
longer a walk to the monitor; it is a physical reattachment of hardware from a drawer. The recovery
is entirely possible, but it is no longer free and no longer instant.

Two further facts sharpen this:

- **There is one SSH key and no backup.** The Phase 03 handover names it as the most consequential
  item on its debt list. Loss of remote access is not softened by a second credential.
- **Both access routes share a single Wi-Fi adapter.** `ssh homelab` (Tailscale) and `ssh
  homelab-lan` (LAN) are independent above the link and identical below it. Losing Wi-Fi loses both
  at once. `eno1` is present and unused; no phase owns wiring it.

Phase 03 also supplied the concrete failure this decision is built around. It wrote a correct
key-only SSH configuration, `sshd -T` reported `passwordauthentication no`, and the running server
went on accepting passwords — because Ubuntu's `ssh.socket` uses `Accept=no` and one long-running
daemon serves every connection from the configuration it parsed at start. Every check performed
agreed with the operator. The system disagreed.

The lesson generalises well beyond `sshd`: **a configuration file is not a control until the process
holding it has re-read it**, and the way to find that out is to ask the running system rather than
the file.

## Decision

Adopt [`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md) as a
**project standard binding on every phase from 02 onward**, and on any change made to the reference
node outside a phase.

The standard has two halves, and the first matters more:

1. **Classification.** A change is *lockout-class* if it touches network, remote access,
   authentication, boot, or the admin account. This is a named category, checked before typing.
2. **A procedure for lockout-class changes**: a second idle session held open; both access routes
   proved with `BatchMode=yes` beforehand; the format's own validator run; the rollback typed out
   unexecuted; `reload` preferred to `restart`; the **running system** verified from the other
   machine; and a third fresh connection plus a clean `systemctl --failed` before standing down.

Three supporting commitments:

- `AGENTS.md` references the standard in its operating rules, so a future phase context inherits it
  by reading the file it is already required to read.
- `scripts/server/preflight.sh` mechanises the parts a machine can check.
- Phase handovers state whether the standard was applied, and to what.

We also **name the classification step as the primary control**. Most lockouts are not caused by
skipping a safety step. They are caused by not noticing that a safety step applied.

## Alternatives considered

- **Leave it as prose in the Phase 03 handover.** Rejected. The reasoning was already written there
  and it is excellent, but a handover is read once by the next phase and then becomes history. This
  constraint applies to Phase 05's Docker work and Phase 13's firewall work just as much, and
  neither will re-read a Phase 03 document.

- **Reattach the console for risky work.** Rejected as the standing answer, though it remains a
  legitimate choice for a specific high-risk change — and the standard says so. Making it routine
  would undo Phase 03's outcome, and "go and get the monitor" is exactly the step that gets skipped
  when the change looks small.

- **Forbid lockout-class changes entirely until Phase 13 adds a recovery path.** Rejected as
  unworkable. Phase 05 must configure Docker's networking; Phase 13 must configure a firewall, which
  is the most lockout-prone change in the whole roadmap. A procedure is needed either way.

- **Rely on out-of-band management (IPMI/iDRAC/AMT).** Not available. The M700 Tiny is consumer-grade
  hardware with 2016 firmware; Intel AMT is not provisioned and provisioning it would add a remote
  management surface with a poor security history to a node that currently has none.

- **Write the script and skip the document.** Rejected, and this is the reason `preflight.sh` is
  explicitly secondary. A script can check that two routes are up and count sessions. It cannot
  notice that the change you are about to make is lockout-class, and that is the control that
  actually prevents lockouts.

## Consequences

**Easier:** risky work becomes routine rather than nervous. Phase 05 and Phase 13 inherit a procedure
instead of re-deriving one. The Phase 03 stale-daemon failure becomes institutional knowledge rather
than an anecdote in a build log.

**Harder / slower:** every lockout-class change now costs a few minutes of setup. This is deliberate.
The friction is the point at which classification happens.

**Constrained:** phases may no longer make network, authentication or boot changes casually, and a
phase that does so without applying the standard is contradicting an accepted ADR — one of ADR-017's
own revisit triggers.

**Intentionally deferred:** this standard does **not** create a recovery path. It does not add a
backup SSH key, a serial console, out-of-band management, or a bootable rescue image. It makes
lockout-class changes recoverable *while remote access still works*. If remote access is lost, the
answer is still the drawer. **Phase 13 owns the actual recovery path**, and this ADR is not a
substitute for it.

**Accepted risk:** a standard that is inconvenient gets skipped. Its main defence is that most of it
is cheap — opening a second SSH session and running a validator are seconds of work — and that
`AGENTS.md` puts it in front of every future context automatically.

## Validation / revisit trigger

Revisit if any of the following occur:

- **A lockout happens anyway.** The standard failed, and the post-mortem rewrites it.
- **A lockout-class change is made without applying the standard.** Whether it caused harm or not,
  the control is not holding. This is the most likely failure and the one to watch for.
- **Phase 13 delivers a real recovery path** — a backup key, a serial console, out-of-band
  management, or an automatic-rollback mechanism. Several sections here exist only because recovery
  is expensive, and should be relaxed once it is not.
- **`eno1` is wired up**, making the two access routes genuinely independent. §3 changes materially.
- **The node stops being single-purpose or single-user**, at which point a standard written around
  one operator holding one key needs revisiting on its own terms.
- **`preflight.sh` starts being run and ignored.** A check whose output nobody acts on is worse than
  no check, because it manufactures confidence.
