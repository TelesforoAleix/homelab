# 12 — Scheduling, monitoring and notifications

## Goal

After this phase the node tells its owner, unprompted, two things it could not say before:

- **"I'm back."** Within about two minutes of any boot, one Telegram message: how long the node was
  down, whether the previous stop was a clean reboot or a power cut, and whether the encrypted data
  volume still needs unlocking.
- **"Something died."** When the Telegram bot, the model helper, or the watchdog itself ends in
  systemd's `failed` state, one Telegram message naming the unit, with its last journal lines.

No daemon, no dashboard, no metrics stack, no new package, no new listening socket, and nothing in
this phase can call a model.

## Why this matters

Phase 18.1 made the data volume wait for a human after every boot (ADR-037 §4: *locked* is a normal
state). That closed a security gap and opened an operational one: after a power cut the node comes
back, the volume stays locked, every volume-dependent service is skipped — and nothing said so. The
owner found out when they next tried to use it.

The second gap was older. `current-architecture.md` had carried the line *"nothing reports the bot
dying"* since Phase 07. `Restart=on-failure` restarts a crashed bot, but if it crashes five times in
five minutes systemd stops trying and the bot stays down, silently.

Both gaps close with the same small mechanism: a way for the node to send one message to the owner
without a human asking first.

**Why recovery-oriented, not real-time.** If the whole node is down, nothing on it can tell you, and
building an external watcher for that is a different project. What the node *can* do is work out,
from its own logs, how long it was gone — so the design reports on **recovery**, not on absence.

**Why the watchdog must not depend on what it watches.** A watchdog that needs the data volume
mounted, or the bot running, or the model helper answering, dies with them. Every unit in this phase
lives on unencrypted root, names no other service in `Requires=`/`After=`/`Condition*=`, and reads
only what it needs with the least privilege that gets it.

## Reference-build choice

Two units, two scripts, three drop-in lines. Everything is in `config/systemd/` and `scripts/server/`.

```text
boot
 └─ homelab-watchdog.timer      OnBootSec=90s, once per boot, nothing else scheduled
     └─ homelab-watchdog.service  oneshot, User=homelab-bot
         └─ homelab-watchdog.sh    classifies the previous stop, reads the lock state,
             └─ homelab-notify.sh  composes one of four literal messages, POSTs it to Telegram

failure
 homelab-telegram-bot.service ──OnFailure=──▶ homelab-notify@bot.service
 homelab-model-helper@.service ─OnFailure=──▶ homelab-notify@model-helper.service
 homelab-watchdog.service ─────OnFailure=──▶ homelab-notify@watchdog.service
                                                └─ homelab-notify.sh --alert <alias>
 homelab-notify@.service ─────── no OnFailure= (the recursion guard)
```

### Why a timer plus one oneshot unit is the whole mechanism

systemd already has a scheduler. A `.timer` with `OnBootSec=` fires its unit once, a fixed time after
boot, and never again until the next boot — there is no `OnUnitActiveSec=` or `OnCalendar=` to make it
recur. A `Type=oneshot` service runs a script to completion and exits. Nothing stays resident, so
there is nothing to crash, leak, or monitor between boots. A cron entry, a loop in a script, or a
long-running "monitoring agent" would all add a process that can itself fail, for no gain.

### How the previous stop is classified — from the journal, not `last -x`

The brief specified `last -x`, which reads `/var/log/wtmp`. **This node does not have `last`.**
`util-linux` 2.41.3 on Ubuntu 26.04 no longer ships `/usr/bin/last` or `utmpdump`; the replacement
is a separate `wtmpdb` package that is not installed, and the phase's cost rule (§14: no new package)
holds. So the same signal is read from the journal instead:

- On a **clean stop**, PID 1 logs exactly one `Shutting down.` line as its last act.
- On a **power cut**, PID 1 never runs its shutdown path, so that line is absent.

The absence is the entire signal, exactly as it was with `wtmp`'s `shutdown` pseudo-entry — only the
file being read has changed. The script asks:

```bash
journalctl -b -1 -q --no-pager _PID=1 -g 'Shutting down\.'
```

Exit 0 → `clean reboot`. Exit 1 → `unplanned reboot`. No boot `-1` in the journal at all → the
script dies with a clear message, the unit lands in `failed`, and the failure alert pages the owner
with the reason. Inventing a class would be worse than an honest failure.

Downtime is `(first entry of this boot) − (last entry of the previous boot)`, taken from
`journalctl --list-boots`, the same way in both branches. The message says `~N m` because that is an
approximation of when the machine actually lost and regained power, not a measurement.

**Two things a future reader must not change:**

- **`_PID=1` is mandatory.** Boot `-1` on this node — the boot that ended in Phase 18.1's power cut —
  contains `systemd[1909]: Reached target shutdown.target - Shutdown.` That is a *user* manager
  (a login session ending), not PID 1. A grep for shutdown text without the PID filter would have
  called a power cut clean. Match PID 1 only.
- **The ext4 kernel line is not a signal.** `EXT4-fs (dm-0): orphan cleanup on readonly fs` appeared
  in boot 0 after the power cut *and* in the boot that followed a clean rescue-ISO session. It is
  circumstantial evidence, not a classifier. Only the PID-1 marker decides.

### Why `LoadCredential=` on a second unit is free and copies nothing

The bot's token lives in `/etc/homelab-telegram-bot/token`, `root:root 0600`. The watchdog and notify
units run as `homelab-bot`, which cannot read it. Both units carry

```ini
LoadCredential=bot-token:/etc/homelab-telegram-bot/token
```

PID 1 reads the file *before* the service process exists and hands it a private, per-invocation
tmpfs copy at `$CREDENTIALS_DIRECTORY/bot-token`. No DAC permission on the source is needed, the
source file's mode is untouched, the bot's own unit is not edited, and nothing is written to disk
that outlives the process. A second unit naming the same credential is one line, not a second copy
of a secret. `homelab-notify.sh` refuses to run without `CREDENTIALS_DIRECTORY` set, so it cannot be
made to work by handing it the token some other way.

### Why the model-helper refusal is a kernel restriction, not a promise — do not simplify this back

Nothing this phase schedules may call a model (brief §6; the spend governor, Phase 15.1, does not
exist). That is enforced one layer below the scripts:

```ini
RestrictAddressFamilies=AF_INET AF_INET6
```

on both new units. No `AF_UNIX` means the process cannot create a UNIX socket at all —
`/run/homelab-model-helper.sock` is refused by the kernel's seccomp filter before the socket's own
`SocketGroup=homelab-bot` would otherwise have let this account (which *is* the bot's account)
through. The scripts do not try to reach the helper, but the reason they *cannot* is in the unit,
not in a comment.

This restriction has a visible cost, and the cost is why it must not be "fixed":

- **`systemctl` cannot be called from these units.** It talks to PID 1 over D-Bus or
  `/run/systemd/private`, both UNIX sockets. The brief's §7.4 table asked for
  `systemctl is-active homelab-data.target` alongside `findmnt /srv/homelab`; the two cannot both
  hold in one unit. **The script checks `findmnt` alone.** That is a narrower signal, not a broader
  one: `findmnt` succeeding is necessary for "unlocked" either way, and this node's own
  `data-volume.sh unlock` always mounts before starting the target.
- If you find yourself adding `AF_UNIX` back to make something work, stop. That is not a
  configuration fix; it reopens §6's decision and needs a superseding ADR first, and Phase 15.1's
  two preconditions (governor landed and enforcing, ADR-044 client authorisation) met.

### Why `OnFailure=` and drop-ins, not a health-check loop

`OnFailure=` is systemd's own hook: when a unit enters `failed`, start this other unit. It costs one
line per watched service, delivered as a drop-in (`<unit>.d/onfailure.conf`) so the bot's and model
helper's own unit files — governed by ADR-023 and ADR-025 — are not edited. The alert unit is a
template, `homelab-notify@.service`, instantiated with a short literal alias (`bot`,
`model-helper`, `watchdog`) rather than a raw `%n`, because a templated unit's instance name would
need `systemd-escape` to round-trip.

**The recursion guard.** `homelab-notify@.service` has no `OnFailure=` of its own. If it did, its own
failure would start another instance of itself, which would fail the same way. This is the one
residual: the notifier's own failure is unwatched, by decision.

## Alternatives

- **`wtmpdb` + `last -x`** — what the brief specified. Would work, but it is a new package for a
  signal the journal already carries. Declined under §14.
- **A heartbeat to an external service** (a dead-man's-switch endpoint) — the only design that can
  report *absence* rather than recovery. Adds an external dependency and a recurring cost for a
  problem the owner does not currently have. Not built.
- **A metrics stack** (node-exporter/Prometheus/Grafana or similar) — three services and a listening
  socket to answer a question ("is it up, is it locked") that one message answers. Out of scope.
- **A lock-state line in the bot's `/status`** — declined by the owner on 2026-09-12 (Phase 18.1
  handover); the bot stays unchanged.

## Prerequisites

- Phase 07 (the bot, its account `homelab-bot`, the token at `/etc/homelab-telegram-bot/token`, the
  allowlist at `/etc/homelab-telegram-bot/allowlist`, `root:homelab-bot 0640`).
- Phase 09 (the model helper and its socket — the thing this phase proves it cannot reach).
- Phase 18.1 (the LUKS volume, `/etc/crypttab`'s `homelab-data` line, `data-volume.sh`).
- `curl` on the node (present; 8.18.0 at build time).
- A second, idle SSH session open before the install: enabling a `timers.target` unit is a
  boot-class change under `docs/standards/safe-changes-headless.md`.

## Implementation

The canonical files are the ones in the repository; do not retype them.

| Repository file | Installed at | Mode |
|---|---|---|
| `config/systemd/homelab-watchdog.timer` | `/etc/systemd/system/homelab-watchdog.timer` | 644 |
| `config/systemd/homelab-watchdog.service` | `/etc/systemd/system/homelab-watchdog.service` | 644 |
| `config/systemd/homelab-notify@.service` | `/etc/systemd/system/homelab-notify@.service` | 644 |
| `config/systemd/homelab-telegram-bot.service.d/onfailure.conf` | `/etc/systemd/system/homelab-telegram-bot.service.d/onfailure.conf` | 644 |
| `config/systemd/homelab-model-helper@.service.d/onfailure.conf` | `/etc/systemd/system/homelab-model-helper@.service.d/onfailure.conf` | 644 |
| `scripts/server/homelab-watchdog.sh` | `/usr/local/sbin/homelab-watchdog.sh` | 755 |
| `scripts/server/homelab-notify.sh` | `/usr/local/sbin/homelab-notify.sh` | 755 |

All seven are in `backup-node.sh`'s `NODE_PATHS` and `verify-node-backup.sh`'s `CRITICAL` — the two
lists must agree, or a restored node gets a watchdog that calls a notifier that was never restored.

1. `scp` the seven files to `/tmp/phase12-artifacts/` on the node and check `md5sum` against the
   repository copies.
2. `sudo install -m 755 -o root -g root` each script into `/usr/local/sbin/`, and
   `sudo install -m 644 -o root -g root` each unit and drop-in into place (create the two `.d`
   directories with `sudo install -d -m 755` first).
3. `sudo systemctl daemon-reload`.
4. Confirm the drop-ins loaded (instance form — see Validation for why):
   `systemctl show -p OnFailure --value homelab-telegram-bot.service` →
   `homelab-notify@bot.service`; `systemctl show -p OnFailure --value "homelab-model-helper@test.service"`
   → `homelab-notify@model-helper.service`; `systemctl show -p OnFailure --value "homelab-notify@test.service"`
   → empty.
5. `sudo systemctl enable --now homelab-watchdog.timer`. Because `OnBootSec=90s` has long passed on
   a running node, `--now` fires the service immediately — expect one message about the *previous*
   transition straight away.

Type every command as one line. This node's terminal wraps long pastes and has dropped the second
argument of an `install` at the wrap point more than once; `cd` into the target directory and use a
short destination if a line is long.

## Validation

Every refusal is paired with a positive control; a check that has only ever permitted is unvalidated.

| Check | Command | Expected | Positive control |
|---|---|---|---|
| Watchdog cannot reach the model helper | `sudo systemd-run --pipe --wait --uid=homelab-bot --gid=homelab-bot -p 'RestrictAddressFamilies=AF_INET AF_INET6' /usr/bin/python3 -c "import socket; socket.socket(socket.AF_UNIX, socket.SOCK_STREAM).connect('/run/homelab-model-helper.sock')"` | `OSError: [Errno 97] Address family not supported by protocol` — refused at socket *creation*, before any group check | The bot's own unit, which carries `AF_UNIX`, connects to the same socket (Phase 09) |
| Notifier cannot read LUKS key material | `sudo -u homelab-bot cryptsetup luksDump /dev/ubuntu-vg/data` | `does not exist or access denied` | `sudo cryptsetup luksDump /dev/ubuntu-vg/data` prints the header |
| Lock state is read truthfully | `journalctl -u homelab-watchdog.service -b` after a boot, before and after `sudo data-volume.sh unlock` | `LOCKED -- ssh homelab && sudo data-volume.sh unlock` then, on the next run, `unlocked` | Same command, different real state, different output |
| Failure alert fires on a real crash | `sudo systemctl kill -s SIGKILL homelab-telegram-bot.service`, repeated | A Telegram message `Home Lab alert: homelab-telegram-bot.service failed.` with journal lines; `homelab-notify@bot.service` shows `status=0/SUCCESS` | — |
| … and not on a clean stop | `sudo systemctl stop homelab-telegram-bot.service`; `journalctl -u "homelab-notify@bot.service" --since "5 minutes ago"` | `Result=success`; no new notify run | The crash above |
| Recursion guard | `systemctl show -p OnFailure --value "homelab-notify@test.service"` | empty | Step 4's two non-empty answers |
| Clean reboot classified | `sudo reboot`; then `journalctl -b -1 -q _PID=1 -g 'Shutting down\.'` | Telegram `… clean reboot …`; exactly one journal line | The power cut below |
| Power cut classified | pull the mains lead, wait 10 s, replace; then the same `journalctl` | Telegram `… unplanned reboot …`; no journal line, exit 1 | The clean reboot above |
| Once per boot | `systemctl list-timers homelab-watchdog.timer` | one row, `NEXT` is `-` | — |
| Nothing regressed | `id homelab-bot`; `ss -tln \| wc -l`; `systemd-analyze security homelab-telegram-bot.service \| tail -1`; `systemctl --failed`; `systemctl is-system-running` | `uid=999(homelab-bot) gid=982(homelab-bot) groups=982(homelab-bot)`; `7`; `1.3 OK`; empty; `running` | Same values before the install |

**Three things the validation taught that the brief did not say:**

- **`OnFailure=` fires on every crash, not when the start limit is reached.** Each `SIGKILL` puts the
  unit through `failed` before `Restart=` picks it up again, and each of those transitions runs the
  alert. A crash loop pages once per crash — seven alerts arrived during the kill run. That is
  systemd's documented semantics and it matches the phase's requirement ("fires on a real crash"),
  but it is noisier than "you get told when the bot is down for good."
- **Reaching the start limit took 15 kills, not 5.** `StartLimitBurst=5` counts starts within
  `StartLimitIntervalSec=300`, and `RestartSec` spacing between the owner's early, unhurried kills
  kept them under the window. Five in quick succession at the end tripped it. The bot then showed
  `failed (Result: signal)` — the last failure's cause — and simply stayed down; *staying down* is
  the evidence the limit was hit, not the `Result:` text.
- **`systemctl show` on a bare template fails on systemd 259.** `systemctl show -p OnFailure --value
  homelab-notify@.service` → *"Unit name … is neither a valid invocation ID nor unit name."* Use an
  instance name (`homelab-notify@test.service`); it works even for an instance that has never run.

### Two shell traps that would misclassify silently

The watchdog runs under `set -euo pipefail`. Two idioms that look correct will, under it, turn a
clean reboot into a reported "unplanned reboot" with no error, no `die`, and no failed unit:

```bash
journalctl -b 0 -o short-iso | head -n 1        # head closes the pipe → journalctl gets SIGPIPE → exit 141
journalctl -b -1 _PID=1 | grep -q 'Shutting down.'   # grep -q exits on first match → same SIGPIPE → `if` reads it as false
```

The first was observed (`rc=141`, no output) during the build; the second only *passed* because
`Shutting down.` happens to be PID 1's last line. The shipped script uses `journalctl --list-boots`
for the timestamps and `journalctl -g` for the match — no pipe to a reader that can stop early. If
you rewrite either, keep it pipe-free.

## Security notes

- **No new account, no new group in `/etc/group`, no sudoers entry.** Both units run as
  `homelab-bot`. Journal read access comes from `SupplementaryGroups=systemd-journal` inside the unit,
  so `id homelab-bot` is unchanged.
- **The token never lands on disk for these units** — `LoadCredential=` only. The alert unit's
  journal excerpt is composed from `journalctl -u <unit> -n 5`; the failure message could carry a
  token only if a unit logged one, which none does.
- **No listening socket** — outbound HTTPS to `api.telegram.org` only; `ss -tln` is unchanged at 6
  listeners.
- **`RestrictAddressFamilies=AF_INET AF_INET6`** on both units, no `AF_UNIX`: the model helper is
  unreachable at the kernel. This is the phase's one real boundary; the section above says why it
  must not be relaxed to make `systemctl` work.
- **Nothing here can open the volume** (ADR-046 §3). The lock-state read is `/etc/crypttab`
  (world-readable, no keyfile path in it) plus `findmnt` — the unprivileged half of
  `data-volume.sh status`.
- **Residual, by decision:** `homelab-notify@.service`'s own failure is unwatched (recursion guard).
  If Telegram is unreachable when an alert fires, that alert is lost; the next boot's watchdog
  message is the recovery path.

## Reference-build experience

All of this is from the owner's run on 2026-09-12 (UTC), recorded in the S4 stage reports.

- **The `last` episode.** The first version of the watchdog shipped `last -x` as briefed, and the
  first test on the node found `command -v last` → exit 1. A journal substitute was written and then
  declared *disproved*, because it reported "unplanned" for the boot `-1 → 0` transition, which the
  executor believed was Phase 18.1's rescue reboot. It was not: it was 18.1's **power-cut test** (step
  E). The rescue reboot was `-2 → -1`. Re-run against both real transitions with `_PID=1`, the
  heuristic classified both correctly (`-2`: one `Shutting down.` line; `-1`: none, and boot 0's
  kernel log showed `EXT4-fs (dm-0): orphan cleanup on readonly fs`). The wrong conclusion came from
  testing the right heuristic on the wrong transition. It was committed, reversed in the next commit,
  and both are on the branch.
- **The timer fired three times, once per boot, and needed no retry.** 17:20:22 (on `enable --now`,
  reporting the earlier power cut: `Down ~1m, unplanned reboot. Data volume: unlocked`); 17:25:13
  after the clean reboot (`Down ~0m, clean reboot. Data volume: LOCKED …`); 17:34:51 after the power
  cut (`Down ~0m, unplanned reboot. Data volume: LOCKED …`). Each message reached Telegram with text
  identical to the journal line. `NRestarts=0`, `Result=success` — **90 s was enough for Tailscale
  and DNS on this node**; the first send succeeded every time.
- **Both branches of the classifier ran live.** After the clean reboot, `journalctl -b -1 -q _PID=1 -g
  'Shutting down\.'` printed one line (`17:23:14 systemd[1]: Shutting down.`); after the power cut it
  printed nothing.
- **Both lock states ran live**, and `sudo data-volume.sh unlock` followed by `findmnt /srv/homelab`
  showed the mount both times.
- **The refusals:** `Errno 97` from the `systemd-run` probe; `does not exist or access denied` from
  `luksDump` as `homelab-bot`, the full header as root.
- **The alert path:** 15 kills, seven alerts, bot left `failed`, alert text `Home Lab alert:
  homelab-telegram-bot.service failed.` plus journal lines; clean `stop` → `Result=success`, no alert.
- **Nothing regressed** after all of it: `id homelab-bot` byte-identical, 7 lines from `ss -tln`,
  `1.3 OK`, `--failed` empty, `is-system-running` → `running`.
- **Two runbook defects of this phase's own:** the kill count (five was optimistic, see above), and a
  transient unit — `run-p13000-i11327.service`, left by the `systemd-run` refusal probe — that showed
  up in `systemctl --failed` until it was `reset-failed`. Not a Home Lab unit, but it would have
  polluted the "no failed units" check had it not been cleared before the reboot.
- **Two brief-vs-node conflicts** resolved without touching §6: `findmnt`-only lock check and the
  instance-form `systemctl show`, both explained under Validation.

## Tested versions

Tested with: Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic; systemd 259.5 (`259.5-0ubuntu3.4`);
util-linux 2.41.3 (`2.41.3-3ubuntu2.2` — ships neither `last` nor `utmpdump`); curl 8.18.0;
python3 3.14 (used only by the refusal probe).

Requires: `journalctl -g` (PCRE2 support in systemd's journalctl), and a persistent journal — the
classifier reads the *previous* boot. Both were already true on this node.

## Next phase

Phase 18.2 — migration to the server — moves content into the volume this phase reports on. It must
not add `ConditionPathIsMountPoint=/srv/homelab`, `Requires=`, or `After=` on the volume to either
watchdog unit; see the [handover](../../docs/handovers/12-scheduling-monitoring-notifications-handover.md).
