# 07 — Telegram Interface

## Goal

Build the first thing this project does *for* you: a bot you can message from
your phone that reports the server's state — and build it so that a compromise
of it costs you almost nothing.

By the end you should understand why it needs no open port, why it runs as an
account that can barely do anything, and why "read-only" is not the same as
"harmless".

## Why this matters

Six phases in, the node is well built and **does nothing for you**. This phase
changes that. It also carries three firsts that make it heavier than its size
suggests:

- **The first long-running service this project has written.** Everything before
  was installed or configured. This is code that runs unattended and comes back
  at boot.
- **The first live secret since the repository went public.** A bot token is a
  bearer credential, and a committed one is a disclosure, not a fixable slip.
- **The first real test of ADR-011.** Privilege separation has been an accepted
  principle since bootstrap with nothing to apply it to.

### Why this counts as lockout-class

`docs/standards/safe-changes-headless.md` lists under **Boot**: *anything
`WantedBy=multi-user.target`*. A service enabled at boot is exactly that.

The realistic risk is low — a failing bot does not normally stop a boot. But the
standard's argument is that lockouts come from **not noticing a safety step
applied**, and this phase proved the point: an unguarded exception turned the bot
into a restart loop (§9). So it got `preflight.sh`, two sessions,
`systemd-analyze verify` before enabling, and a real reboot test.

---

## 1. Why there is no open port

Telegram offers two ways to receive messages:

| | How it works | What it needs |
|---|---|---|
| **Webhook** | Telegram connects **to you** | A public, inbound HTTPS endpoint |
| **Long polling** | You connect **to Telegram** | Outbound HTTPS only |

This bot uses **long polling**. It makes an outbound HTTPS request that Telegram
holds open for ~50 seconds waiting for a message, then makes another.

That is not a style preference. **This node had no firewall when this was written** **Superseded 2026-09-10** — a firewall was added out of phase; see [`guide/security-shared-network`](../security-shared-network/README.md). `:22` was the only
port reachable off-box, and anything published here would be published to the
LAN. Long polling is what makes running a network service on this machine
acceptable at all.

Verified — the listener list is identical before and after:

```console
$ ss -tln | tail -n +2 | wc -l
6                       # same as the pre-Phase-07 baseline
ok  the bot listens on NOTHING (long polling, outbound only)
```

**If a later phase ever moves to webhooks, that changes the exposure model
completely** and needs its own ADR. It is not a config tweak.

---

## 2. The token is a bearer credential

Not a password with a user behind it. **Whoever holds the token *is* the bot** —
from anywhere, with no second factor. It is closer to a private key.

That drives four decisions:

**It never touches the repository.** `token.example` holds a placeholder. The real
value is typed on the server with `sudoedit`, never `echo 'tok' | sudo tee`,
because the latter puts it in your shell history forever.

**It never goes in a chat window.** Phase 06 recorded a one-time authorization
code reaching an agent transcript. This one is long-lived, so the same slip is
worse.

**It is not an environment variable.** The unit uses `LoadCredential=`:

```ini
LoadCredential=bot-token:/etc/homelab-telegram-bot/token
```

systemd reads the file **as root** at unit start and hands the process a private
copy on a tmpfs, unmounted when the unit stops. The file itself is
`root:root 0600` — so **the bot's own account cannot read it**:

```console
ok    homelab-bot cannot read the bot token file
```

An environment variable would be visible to anything that can read
`/proc/PID/environ`, and environment variables leak into crash dumps,
`systemctl show`, and logs.

**It is scrubbed from logs.** The token is part of *every* API URL, and `urllib`
puts URLs into its exception messages. Without a `redact()` helper, one
connection error would write a permanent bearer credential into the journal:

```console
ok    token does not appear in the unit's journal
```

If it ever does leak: **revoke it with BotFather first.** Cleaning up wherever it
appeared is the second action, not the first.

---

## 3. The allowlist is the actual access control

Anyone who finds your bot can message it. There is no approval step, no friend
request. Without an allowlist, your "harmless read-only status bot" reports this
machine's disk usage, uptime and memory to strangers.

Three details matter:

**Numeric user IDs, not usernames.** A username can be changed by its owner; the
numeric ID cannot.

**Checked once, before dispatch** — not inside each handler:

```python
if user_id not in allowlist:
    log(f"refused: user {user_id} is not allowlisted")
    send_message(chat_id, "Not authorised.")
    continue

reply = handle(text)
```

One choke point, so a command added next year cannot accidentally be
unprotected.

**An empty allowlist is a hard error.** The bot refuses to start:

```console
ERROR: the allowlist at /etc/homelab-telegram-bot/allowlist is empty.
Refusing to start. An empty allowlist must never mean 'allow everyone'.
```

This is the classic version of the bug. A misconfiguration must **fail closed** —
the failure mode of an empty config file must never be "answer everyone".

---

## 4. An account that can barely do anything

```console
$ id homelab-bot
uid=999(homelab-bot) gid=982(homelab-bot) groups=982(homelab-bot)
```

A system account: no login shell, no home directory, member of no group but its
own. Never `sudo`, never `docker`, never `adm` — and the installer re-checks that
on **every** run, not only at creation, because Docker-group membership is
root-equivalent (ADR-022) and would make every hardening directive below
pointless.

### Prove it, don't assert it

The verifier tests each isolation claim by **attempting the access**:

```console
ok    homelab-bot cannot read the admin home directory
ok    homelab-bot cannot read the Claude OAuth credential
ok    homelab-bot cannot read the Codex OAuth credential
ok    homelab-bot cannot read the Docker socket
ok    homelab-bot cannot read the bot token file
ok    homelab-bot cannot modify its own code
```

That last one matters more than it looks: the code is root-owned, so a
compromised bot cannot persist by rewriting itself.

This is the Phase 06 handover's requirement made real — `aleix` holds passworded
`sudo`, root-equivalent Docker access, and two AI OAuth credentials, and **none
of it is inherited here**.

---

## 5. The unit is the security boundary

Written deny-by-default, re-enabling only what was demonstrably needed:

```ini
NoNewPrivileges=yes
CapabilityBoundingSet=
ProtectSystem=strict
ProtectHome=yes            # this is what enforces "no /home/aleix"
PrivateTmp=yes
RestrictAddressFamilies=AF_INET AF_INET6
MemoryDenyWriteExecute=yes
SystemCallFilter=@system-service
```

`RestrictAddressFamilies` omits `AF_UNIX` deliberately: the bot talks to nothing
locally, and denying it removes any path to the Docker socket even if the account
were somehow added to the docker group by mistake.

Check the **running** service, not the file — a directive that failed to apply is
silent:

```console
$ systemd-analyze security homelab-telegram-bot.service
→ Overall exposure level: 1.3 OK 🙂
```

### The bot never forks a process

Every figure comes from `/proc`, `/etc/hostname` or `os.statvfs()`. No
`subprocess`, no shelling out to `df` or `uptime`. That is why the unit can
forbid so much — **a process that cannot execute a program cannot be talked into
executing the wrong one.**

---

## 6. How to verify it worked

```bash
sudo bash /tmp/verify-telegram-bot.sh    # sudo: the isolation probes need root
systemctl status homelab-telegram-bot
journalctl -u homelab-telegram-bot -b
ss -tln                                   # must match your baseline
```

Then message the bot `/status`.

---

## 7. What can go wrong

| Symptom | Cause | Fix |
|---|---|---|
| Bot never replies, unit `activating` | crash loop — read the journal | `journalctl -u homelab-telegram-bot -b` |
| `FileNotFoundError: /proc/uptime` | `ProcSubset=pid` in the unit | remove it; see §9 |
| Refuses to start, "allowlist is empty" | working as designed | add your numeric id |
| Refuses to start, no `CREDENTIALS_DIRECTORY` | started outside systemd | start via `systemctl` |
| "Not authorised." | your id is not allowlisted | check the journal — it logs the refused id |
| Disk figure disagrees with `df` | reserved blocks counted as used | see §9 |
| A `Password:` prompt after a reboot | buffered local input, **not** the server | Ctrl-C; the server is key-only |

---

## 8. The reboot test, and why it is not optional

`systemctl start` working is a **different claim** from *starts at boot*. This is
the first phase where the difference matters, so it was tested for real:

```text
18:50:53  boot
18:51:00  unit started — 7 seconds after boot, unattended
18:51:00  WARNING: Telegram unreachable: Temporary failure in name resolution
18:51:56  Telegram reachable again
```

**Zero restarts. Three journal lines total.**

The bot started before DNS was ready, logged the outage **once**, backed off, and
recovered on its own 56 seconds later. That accidentally validated three design
decisions that could not otherwise have been tested without faking an outage:

- the bounded-backoff retry loop works;
- **bounded logging** works — an outage logs once instead of flooding a journal
  on a volume group that cannot be grown;
- `After=network.target` rather than `network-online.target` was right. The
  argument on paper was "the bot handles unavailability, so it needn't block
  boot". Now it is evidence.

---

## 9. What the reference build actually hit

Five problems, all in
[`docs/build-log/2026-09-09-phase-07-telegram-bot.md`](../../docs/build-log/2026-09-09-phase-07-telegram-bot.md).
The three that generalise:

**1. I hardened a system-info reporter so it could not read system info.** Every
`/status` died with `FileNotFoundError: /proc/uptime`. The file exists — it did
not exist *for that process*, because `ProcSubset=pid` restricts `/proc` to
process directories and hides `/proc/uptime`, `/proc/loadavg` and
`/proc/meminfo`. Those are the only three files the bot reads. The directive was
copied from a hardening checklist without being checked against what the program
does.

> **Hardening that breaks the function it protects is not hardening.** A
> checklist tells you what *can* be restricted. It cannot tell you what this
> program needs.

**2. One unguarded exception became a restart loop.** Because `handle()` had no
`try`, that crash killed the process; systemd restarted it; the same `/status`
was still queued; it crashed again — on a machine with no console.
`StartLimitBurst=5` is what stopped it becoming continuous. A user-facing command
must never be able to kill the service.

**3. The verifier reported a confident `FAIL` about a file it could not see.**
`FAIL: /etc/homelab-telegram-bot/token does not exist` — while the bot was
authenticating with that token. The config directory is `0750 root:homelab-bot`,
so `aleix` cannot traverse it, and the script confused *"I cannot see it"* with
*"it is not there"*.

That is the **fifth** occurrence of this failure family here, after `sshd -T`,
`who`, and two separate bugs in the Phase 04 secret scanner — and it was written
after the rule had been documented four times.

> **Knowing a failure mode does not confer immunity to it.** Four rounds of
> intention failed. The defence has to be structural: check your own privilege
> *first*, and make `UNKNOWN` a result the report can express.

Also worth keeping: the bot initially reported **19.3G** of disk used where `df`
said **8.9G**, because `used = total - available` counts the filesystem's
root-reserved blocks as used. More than double, no error anywhere, on the one
number an operator is most likely to act on. **Wrong-but-plausible is the
dangerous failure, not crashed.**

---

## Command summary

| Question | Command |
|---|---|
| Is it running? | `systemctl status homelab-telegram-bot` |
| Why did it fail? | `journalctl -u homelab-telegram-bot -b` |
| Did it come back at boot? | `systemctl show -p NRestarts,ActiveEnterTimestamp --value homelab-telegram-bot` |
| Is it really isolated? | `sudo bash scripts/server/verify-telegram-bot.sh` |
| How exposed is the unit? | `systemd-analyze security homelab-telegram-bot.service` |
| Did it open a port? | `ss -tln` — compare against your baseline |
| Who was refused? | `journalctl -u homelab-telegram-bot \| grep refused` |
