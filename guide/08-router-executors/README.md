# 08 — Router & Executors

## Goal

Give the bot a structure that can grow, and let it perform exactly one privileged
action **without becoming privileged**.

By the end you should be able to explain the difference between authentication
and authorisation, read a polkit rule, and say why a wildcard in an escalation
grant is usually a full root grant in disguise.

## Why this matters

Phase 07 built an interface with nothing behind it. This phase builds the
structure — and it is the first phase where three ADRs stop being principles and
become code:

- **ADR-006** — build interface → router → executor manually before frameworks.
- **ADR-007** — model access behind replaceable executors.
- **ADR-011** — services unprivileged, escalation explicit and auditable.

ADR-011 in particular has been accepted since bootstrap and never tested. Phase
07 satisfied it by having nothing to escalate. This is the first phase that
needed the other half.

### The result, up front

```console
$ id homelab-bot
uid=999(homelab-bot) gid=982(homelab-bot) groups=982(homelab-bot)

$ sudo grep -rl homelab-bot /etc/sudoers /etc/sudoers.d/ | wc -l
0
```

**The account gained nothing.** No group, no sudoers entry, no new file access.
And it can restart exactly one service, and provably not three others.

---

## 1. A router is a table, not a chain of ifs

The tempting shape:

```python
if command == "/status":  return do_status()
elif command == "/disk":  return do_disk()
elif command == "/restart":
    if user in privileged:      # ← the check has drifted in here
        return do_restart(args)
```

The problem is not style. It is that **the authorisation check has moved inside a
branch.** Phase 09 adds transcription, Phase 10 adds knowledge retrieval, Phase 12
adds automation — each editing this function, each responsible for remembering
the check.

A registry keeps it in one place:

```python
@dataclass(frozen=True)
class Executor:
    name: str
    capability: Capability      # READ / PRIVILEGED / UNAVAILABLE
    handler: Callable[[list[str]], str]
    summary: str
```

Adding a capability is adding an entry. The check lives in `Router.dispatch()`
and nowhere else, so a new executor **cannot** be unprotected by accident.

`/help` is generated from that registry too. Hand-maintained help text is how an
undocumented command survives.

---

## 2. Authentication and authorisation are different questions

Phase 07 answered one: *may this user talk to the bot at all?* That was enough
while everything was read-only.

| File | Question | Empty means |
|---|---|---|
| `allowlist` | May you use the bot? | **fatal** — refuses to start |
| `privileged-allowlist` | May you invoke `/restart`? | **nobody may escalate** |

**Note the asymmetry, it is deliberate.** An empty `allowlist` is a hard error,
because *empty-means-everybody* would publish this machine's state to strangers.
An empty `privileged-allowlist` is fine, because *empty-means-nobody* fails safe.

The privileged list is enforced as a **subset** at startup:

```python
stray = privileged - allowlist
if stray:
    sys.exit("Refusing to start. A user cannot be authorised for privileged "
             "commands without first being permitted to use the bot at all.")
```

A misconfiguration becomes a refusal to start — which someone notices — rather
than a surprise the first time an unlisted id sends `/restart`.

### Refused is not the same as unknown

```console
/restart chrony      (not privileged)  -> '/restart' is a privileged command and
                                          you are not authorised for it.
/rm -rf /                              -> Unknown command. Try /help
```

Telling a permitted user that a command does not exist sends them looking for a
typo instead of asking for access.

---

## 3. Escalation: why not sudo

The plan was a sudoers rule. It cannot work here, and the check took a minute:

```console
$ setpriv --no-new-privs sudo -n true
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

The unit sets `NoNewPrivileges=yes`. `sudo` is **setuid**, and that flag exists
precisely to forbid gaining privilege that way.

> **Using sudo would have meant removing the hardening in order to add the
> escalation** — weakening the process in order to grant it privilege.

### polkit instead

`systemctl` is not setuid. It asks PID 1 over D-Bus, and **polkit decides inside
PID 1**. Nothing in the bot's process ever gains privilege, so `NoNewPrivileges`
stays on.

polkit is also **safer to get wrong**:

| Mechanism | If the file is malformed |
|---|---|
| `/etc/sudoers.d/` | **`sudo` breaks entirely** — on a node with no console |
| `/etc/polkit-1/rules.d/` | the rule is ignored → **denied** |

On this machine that difference is the whole argument. A denial is an
inconvenience; losing `sudo` with no console is a trip to find a monitor.

---

## 4. The grant: one user, one unit, one verb

```javascript
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.user == "homelab-bot" &&
        action.lookup("unit") == "chrony.service" &&
        action.lookup("verb") == "restart") {
        return polkit.Result.YES;
    }
    // everything else falls through to the default: denied.
});
```

**No wildcards.** `systemctl restart *` would reach `ssh`, `tailscaled` and
`systemd-networkd` — every service whose loss costs access to this machine. A
wildcard in an escalation grant is usually a full root grant wearing a disguise.

### Two gates, in two processes, neither trusting the other

The polkit rule is one. The other is a unit allowlist **inside the bot**, checked
before `systemctl` is invoked at all.

- A bug in the bot cannot reach a unit polkit refuses.
- A mistake in the polkit rule cannot reach a unit the bot's list does not name.

Both were proved *before* the rule was installed — the bot's list refused `ssh`,
and polkit refused `chrony` because no rule yet existed. And again afterwards:

```text
ok  homelab-bot is DENIED ssh.service (polkit refused, no agent involved)
ok  homelab-bot is DENIED tailscaled.service (polkit refused, no agent involved)
ok  homelab-bot is DENIED systemd-networkd.service (polkit refused, no agent involved)
```

---

## 5. The model executor is registered and deliberately switched off

```console
/model summarise this
→ The model executor is registered but not connected.
  This is deliberate. ADR-008 authorises subscription-backed interactive access;
  it does not authorise unattended use...
```

Wiring `claude -p` would work today and cost nothing. **That is exactly why the
decision has to be made deliberately rather than by default.**

ADR-008 authorises subscription-backed *interactive* access and is silent on
unattended use. Whether automating a personal Claude Pro or ChatGPT subscription
behind a service is within either provider's terms is **not something this
project has established**. That is an unknown, not a formality.

Registering it anyway means the architecture is honest — `Interface → Router →
Executor` has all three layers, one of them visibly unfinished — and `/help`
shows it with a `-` marker rather than hiding it.

Phase 09 needs a real model call and will decide on its merits.

---

## 6. How to verify it worked

```bash
sudo bash /tmp/install-bot-escalation.sh install   # proves both directions
id homelab-bot                                      # must be unchanged
sudo grep -rl homelab-bot /etc/sudoers /etc/sudoers.d/ | wc -l   # must be 0
systemd-analyze security homelab-telegram-bot.service
ss -tln                                             # must match the baseline
```

From Telegram: `/help`, `/restart chrony`, `/restart ssh`, `/model`.

---

## 7. What can go wrong

| Symptom | Cause | Fix |
|---|---|---|
| `sudo: The "no new privileges" flag is set` | trying to use sudo from the service | use polkit; do not remove the hardening |
| Restart fails: `Access denied ... interactive authentication` | polkit rule missing or not matching | check the rule's unit/verb/user strings exactly |
| Restart fails at the socket | `AF_UNIX` missing from `RestrictAddressFamilies` | add it |
| A test **prompts for a password** | `systemctl` found a TTY and registered a polkit agent | `--no-ask-password` |
| Bot refuses to start, "privileged but not in main allowlist" | working as designed | add the id to `allowlist` too |
| `/restart x` says not permitted | the bot's own allowlist | that is gate two doing its job |

---

## 8. What the reference build actually hit

Four problems in
[`docs/build-log/2026-09-09-phase-08-router-executors.md`](../../docs/build-log/2026-09-09-phase-08-router-executors.md).
Three generalise:

**1. The brief specified a mechanism the runtime forbids.** Second phase running,
after `ProcSubset=pid` in Phase 07.

> A brief is written against documentation. Documentation describes what a
> mechanism does, not what *this machine* will permit it to do. Both times the
> check that closed the gap took under a minute.

**2. A test prompted the admin instead of testing the account.** The
"proves it does NOT extend" step ran `systemctl restart ssh.service` as
`homelab-bot` — with a controlling TTY, so `systemctl` registered a polkit
*interactive agent* and polkit escalated the question to the admin:

```text
==== AUTHENTICATING FOR org.freedesktop.systemd1.manage-units ====
Authentication is required to restart 'tailscaled.service'.
Password:
```

Two failures, and the second is worse. It asked a human to authorise restarting
**tailscaled** — one of two routes into a console-less machine. And it then
printed `ok  homelab-bot cannot restart ssh.service`, which was **a pass for the
wrong reason**: the service was not restarted because nobody typed a password,
not because the account lacked authority. The test was measuring the operator's
restraint.

Fixed with `--no-ask-password`, *and* by asserting on the reason:

```bash
if printf '%s' "$OUT" | grep -qiE 'access denied|not authorized|interactive authentication'; then
  ok "DENIED (polkit refused, no agent involved)"
else
  die "failed, but not because it was denied. Refusing to claim this as proof."
fi
```

> **A test must assert on the reason, not the outcome.** "The command failed" and
> "the account was denied" are different claims, and only one is evidence.

**3. polkit does not log what I claimed it logs.**

| Outcome | polkit journal |
|---|---|
| Denial | logged |
| **Grant** | **nothing** |

A `polkit.log()` call produced no output either — filtered at the default log
level. The dead call was removed rather than left implying a guarantee.

> **An audit trail that records refusals but not approvals is half an audit
> trail, and it is the wrong half.**

The second independent record is **systemd's** (`Stopping`/`Started
chrony.service`, from PID 1) — different process, different failure mode, and it
records the action *happening* rather than an intention to perform it.

---

## Command summary

| Question | Command |
|---|---|
| What can this account actually do? | `id <user>`; `sudo grep -rl <user> /etc/sudoers /etc/sudoers.d/` |
| Is the polkit rule loaded? | `journalctl -u polkit --since "5 min ago"` |
| Did the privileged action happen? | `journalctl -u <target-unit>` — systemd's own record |
| Who asked for it? | `journalctl -u homelab-telegram-bot \| grep restart` |
| Is a mechanism compatible with this unit? | test it: `setpriv --no-new-privs <cmd>` |
| How exposed is the service? | `systemd-analyze security <unit>` |
