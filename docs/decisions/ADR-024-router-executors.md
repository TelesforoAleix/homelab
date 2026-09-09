# ADR-024: Router/executor architecture and the escalation boundary

- **Status:** Accepted
- **Date:** 2026-09-09
- **Supersedes:** none
- **Superseded by:** none

## Context

Phase 07 built an interface with nothing behind it. ADR-006 has said since
bootstrap to "build a simple interface → router → executor → tool/model flow
manually before comparing agent frameworks", ADR-007 to "define model/tool access
behind replaceable executors", and ADR-011 to "run bot/router services
unprivileged and introduce controlled executors/escalation for operations that
genuinely require additional permissions".

None had been tested. Phase 07 satisfied ADR-011's first half by having nothing
to escalate.

Three constraints shape this:

1. **The service must stay unprivileged.** The Phase 07 handover forbids widening
   `homelab-bot` — no `sudo`, no `docker`, no group.
2. **There is no console** (ADR-020), and `/etc/sudoers.d/` is in the standard's
   Authentication row. A malformed sudoers file breaks `sudo` outright.
3. **Phases 09, 10 and 12 all add executors.** A boundary that is wrong here is
   wrong four times.

## Decision

### 1. Routing is a registry, not a chain of conditionals

Commands map to `Executor` records in a dict. Dispatch is one function. Adding a
capability is adding an entry.

The alternative — `if command == "..."` branches — puts the authorisation check
inside the branches, where it drifts. A registry keeps it in exactly one place,
which is the property that matters when Phase 09 adds transcription and Phase 12
adds automation.

### 2. Executors declare a capability; the router enforces it

```python
class Capability(enum.Enum):
    READ         # answers from host state, changes nothing
    PRIVILEGED   # changes something; requires authorisation
    UNAVAILABLE  # registered, deliberately not wired
```

The check happens **in the router, before the handler is called**. An executor
never decides its own entitlement.

### 3. Two allowlists: authentication and authorisation are different questions

| File | Question | Empty means |
|---|---|---|
| `allowlist` | May this user talk to the bot at all? | **fatal** — refuses to start |
| `privileged-allowlist` | May this user invoke a PRIVILEGED executor? | **nobody may escalate** |

The asymmetry is deliberate: *empty-means-nobody* fails safe, *empty-means-
everybody* does not.

The privileged list is enforced as a **subset** of the main list at startup, so a
misconfiguration is a refusal to start rather than a surprise later.

A refusal is also distinguishable from "unknown command". Telling a permitted
user that a command does not exist sends them hunting for a typo instead of
asking for access.

### 4. Escalation is polkit, not sudo — and the brief was wrong about this

**The brief specified a sudoers rule. It cannot work here**, and the reason was
found by testing rather than reasoning:

```console
$ setpriv --no-new-privs sudo -n true
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

`homelab-telegram-bot.service` sets `NoNewPrivileges=yes` — one of the strongest
properties Phase 07 established, and part of its 1.3 exposure score. `sudo` is
setuid, so it is refused outright under that flag. **Using sudo would have meant
removing the hardening in order to add an escalation** — weakening the process in
order to grant it privilege, which is backwards.

polkit needs no setuid. `systemctl` asks PID 1 over D-Bus; polkit decides inside
PID 1. `NoNewPrivileges` stays on.

It is also **safer to get wrong**. A malformed sudoers file breaks `sudo`
entirely, on a node whose admin has no console and no other escalation path. A
malformed polkit rule **denies**. The failure modes are not comparable, and this
deviation reduces the phase's lockout risk rather than accepting it.

### 5. The grant is one user, one unit, one verb — and there are two gates

```javascript
if (action.id == "org.freedesktop.systemd1.manage-units" &&
    subject.user == "homelab-bot" &&
    action.lookup("unit") == "chrony.service" &&
    action.lookup("verb") == "restart") {
    return polkit.Result.YES;
}
```

No wildcards. A wildcard would reach `ssh`, `tailscaled` and `systemd-networkd` —
every service whose loss costs access to this machine.

**The second gate is a unit allowlist inside the bot**, checked before
`systemctl` is invoked at all. Neither gate trusts the other: a bug in the bot
cannot reach a unit polkit refuses, and a mistake in the polkit rule cannot reach
a unit the bot's list does not name.

Both were proved before any privilege was granted, and again afterwards:

```text
ok  homelab-bot is DENIED ssh.service (polkit refused, no agent involved)
ok  homelab-bot is DENIED tailscaled.service (polkit refused, no agent involved)
ok  homelab-bot is DENIED systemd-networkd.service (polkit refused, no agent involved)
```

**`id homelab-bot` is byte-identical to phase start** — uid 999, groups
`homelab-bot` only, zero sudoers entries — and it can restart exactly one
service. That is ADR-011 working.

### 6. The model executor is registered and deliberately inert

`/model` appears in `/help`, occupies its place in the architecture, and returns
an explanation rather than an error.

Wiring `claude -p` would work today and cost nothing, **which is exactly why the
decision has to be made deliberately rather than by default.** ADR-008 authorises
subscription-backed *interactive* access and is silent on unattended use, and
whether automating a personal Claude Pro or ChatGPT subscription behind a service
is within either provider's terms is **not something this project has
established**. That is an unknown, not a formality.

Phase 09 needs a real model call and decides on its merits — subscription, API
key, or local — and records it as an ADR. **It must not be resolved by copying a
personal OAuth credential to a service account because it works interactively.**

## Alternatives considered

**A sudoers rule.** The brief's choice. Rejected on evidence: incompatible with
`NoNewPrivileges`, and its failure mode is losing `sudo` on a console-less node.

**Widening `homelab-bot`** — adding it to a group with restart rights. Rejected:
the Phase 07 handover forbids it, and group membership is ambient authority that
grows silently. ADR-011 wants escalation explicit and auditable.

**A separate privileged helper service** triggered by a file or socket. Keeps the
bot entirely unprivileged, and is attractive. Rejected for now as more machinery
than one restart justifies, and because it makes reporting the *result* awkward.
Worth revisiting if the number of privileged actions grows.

**Wiring the model executor to the subscription CLIs.** Rejected — see §6.

**A queue, broker or scheduler between router and executors.** Rejected.
`AGENTS.md` forbids infrastructure added because it is common. A router is a
dict.

## Consequences

**Positive.**

- ADR-006, ADR-007 and ADR-011 are implemented rather than asserted.
- The service account gained **nothing** and can still perform a privileged action.
- Authorisation lives in one function; new executors cannot bypass it.
- Two gates in two processes with different failure modes.
- `NoNewPrivileges` retained; exposure level still **1.3 OK**.

**Negative, and accepted.**

- **The privileged executor forks `systemctl`**, losing Phase 07's "never forks"
  property. What replaces it: `NoNewPrivileges` retained, empty
  `CapabilityBoundingSet`, and authority that lives outside the process entirely.
- **`AF_UNIX` is now permitted**, because `systemctl` reaches PID 1 over a UNIX
  socket. Checked rather than assumed: this does not open the Docker socket,
  which is `root:docker 0660` to an account in no group but its own.
- **polkit logs denials but not grants.** Measured: a rule-based `YES` produces
  zero journal lines, and a `polkit.log()` call is filtered out at the default
  log level. The second independent audit record is therefore **systemd's**
  (`Stopping`/`Started chrony.service` from PID 1), not polkit's. An audit trail
  that records refusals but not approvals is half an audit trail, and it is the
  wrong half.
- **One more thing can now change the system.** Small, scoped and proved — but
  Phase 07's property that a compromise could leak information and nothing more
  no longer holds.

## Related

- **ADR-006** — manual flow before frameworks; this is that flow.
- **ADR-007** — model access behind replaceable executors; the interface exists, unwired.
- **ADR-008** — subscription-backed interactive access only; why `/model` is inert.
- **ADR-011** — privilege separation; escalation explicit and auditable.
- **ADR-020** — console-less change safety; why polkit's failure mode matters.
- **ADR-023** — the Phase 07 service this extends.
