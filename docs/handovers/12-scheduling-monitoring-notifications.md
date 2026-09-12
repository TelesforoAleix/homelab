# Phase 12 Brief — Scheduling, monitoring and notifications

- **Phase:** 12 — Scheduling, monitoring and notifications
- **Written:** 2026-09-12
- **Status:** Brief, committed before implementation per ADR-017
- **Predecessor:** Phase 18.1 (encryption execution), complete 2026-09-12 —
  [`18.1-encryption-execution-handover.md`](18.1-encryption-execution-handover.md) §What the next
  phase inherits → Phase 12
- **Successors:** whichever phase runs next per `ROADMAP.md`'s sequencing note (18.2 is named next);
  §16 states what any later phase must not silently inherit

## 1. Purpose

Phase 18.1 left a gap it named but could not close: the data volume is unlocked right now and will
not survive an unattended reboot, and nothing on the node tells the owner when that happens. This
phase closes it with three roles — a trigger source, an observer, and a channel to report through —
built as the minimum that satisfies all three without adding a service the phase has no concrete need
for.

The roadmap repurposed this phase on 2026-09-11 (ADR-045 §3), correcting an earlier assessment that
had called it fully absorbed into the scheduler-as-client design. The scheduler half of that earlier
call still holds: a scheduled trigger is an ordinary client request with no human waiting (ADR-040).
What survives as this phase's actual work is the half that has no other home — observing the node's
own recovery and reporting it — because nothing else in the roadmap owns monitoring or notification.

## 2. Starting state

Verified on the node 2026-09-12, at the close of Phase 18.1. Not re-derived here.

- Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic, systemd 259.5. `is-system-running` → `running`, 0
  failed units, 6 listeners (2× sshd, 2× systemd-resolved, 2× tailscaled).
- Root: 62.4 G ext4, 8.9 G used, 50.7 G available.
- `ubuntu-vg/data` → LUKS2 → `/dev/mapper/homelab-data` → ext4 at `/srv/homelab`, 126 G usable.
  `noauto` in both `/etc/crypttab` and `/etc/fstab`; nothing pulls it in at boot.
- `homelab-data.target` and `homelab-data-probe.service` installed. `data-volume.sh
  {unlock|lock|status}` at `/usr/local/sbin/data-volume.sh`, mode 755; `status` is unprivileged by
  design.
- `homelab-telegram-bot.service` runs as `homelab-bot`, uid 999 / gid 982, no shell, no home,
  `systemd-analyze security` → 1.3 OK. Outbound HTTPS only (long polling), no listening socket. The
  token is delivered via `LoadCredential=bot-token:/etc/homelab-telegram-bot/token`
  (`config/systemd/homelab-telegram-bot.service`); the file itself is `root:root 0600`. The allowlist
  at `/etc/homelab-telegram-bot/allowlist` is `root:homelab-bot 0640`, numeric Telegram user IDs, one
  per line (`services/telegram-bot/allowlist.example`).
- `homelab-model-helper.socket` + templated service: runs as `aleix`, socket-activated,
  `SocketUser=aleix`, `SocketGroup=homelab-bot`, `SocketMode=0660`, `Accept=yes` (ADR-025 §1–§2). The
  bot's own unit already carries `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX` to reach it.
- `ufw` active since 2026-09-10, default deny inbound. Boot time 27.6 s cold.
- **The volume is unlocked as of close of Phase 18.1 and will not survive an unattended reboot.** A
  power cut today reproduces Phase 18.1's own D3 test — locked and silent — with nothing pushing that
  fact to the owner.

## 3. Learning objectives

By the end, the owner should understand: why a systemd timer is sufficient as a trigger source and
what "the watchdog must not share a process with what it watches" actually rules in and out; how a
process reuses an existing service account's credential grant (`LoadCredential=`) without widening
that account or copying the secret; how to tell a clean reboot from a power cut from the journal and
`wtmp` alone, with no external monitor; and why "recovery-oriented, not real-time" is a scope decision
that rules out a whole class of always-on monitoring daemon this phase does not need.

## 4. Functional objectives

1. A trigger fires once per boot, without a human present, and cannot double-fire.
2. The trigger's target computes how long the node was down and whether the prior shutdown was clean.
3. The trigger's target reads the data volume's lock state without privilege and without error when
   the volume is not configured at all.
4. Exactly one of four defined messages reaches the owner's Telegram, matching §7.4's literal text.
5. The mechanism that sends the message cannot read the Telegram bot token from disk directly, cannot
   read any LUKS key material, and cannot reach the model helper socket — proved by attempt, not
   asserted.
6. `homelab-telegram-bot.service`'s own file is untouched: `systemd-analyze security` stays 1.3 OK,
   `id homelab-bot` stays byte-identical, `ss -tln` stays at 6 listeners.
7. A real, unattended power cut — mains pulled, node returns on its own — produces the notification
   without anyone prompting it.

## 5. Decisions already fixed

**Inherited from Phase 18.1, by name** (handover §What the next phase inherits → Phase 12):

1. The lock-state signal is `data-volume.sh status`, or directly `findmnt /srv/homelab` and
   `systemctl is-active homelab-data.target`.
2. The gap this phase closes is observed, not hypothetical, as of 2026-09-12.
3. The unlock procedure the notification must point at is `ssh homelab`, `sudo data-volume.sh
   unlock`.
4. The watchdog and notifier live on root, carry no `ConditionPathIsMountPoint`, and must not share a
   process with what they watch.
5. They may hold no key material for the volume (ADR-046 §3).
6. §6.5 of the 18.1 brief (a lock-state line in the bot's `/status`) was **declined by the owner**,
   not deferred. It is not this phase's to implement — see §6 Out of scope in the 18.1 brief and §Out
   of scope below.

**Binding ADRs, as they apply here, not restated in full:**

- **ADR-011** — no user-facing or network-facing service runs as root; escalation is explicit.
- **ADR-017** — this phase is self-contained; any cross-phase change becomes an ADR, not a silent
  edit.
- **ADR-023 §4, §7** — `LoadCredential=` over an environment variable for any bearer token; a process
  that never forks or executes anything cannot be talked into executing the wrong thing. The bot
  itself must never fork a process (§7), which is why the notifier cannot be a subprocess the bot
  spawns — it has to be a systemd unit the timer starts independently.
- **ADR-025 §1–§2** — the pattern for a credential-scoped local mechanism: access control lives in
  the unit file (`SocketUser=`/`SocketGroup=`/`SocketMode=`), not in code. Applied here by omission
  rather than by socket: see §7.2.
- **ADR-037 §4** — degraded-until-unlocked is a normal operating state, not a fault; a service
  observing it must say so, not treat it as an error.
- **ADR-037 §5** — the boundary already places "Telegram bot · watchdog · notifier" on unencrypted
  root, opposite "harness · Workbench · Factory · projects · brain" in the volume. This phase's units
  belong on root by design, which is also why they work before unlock.
- **ADR-037 §6, ADR-046 §3** — no keyfile, no TPM enrolment, no cached or scripted passphrase, no
  header backup on the node. Nothing this phase adds may hold any of those.
- **ADR-040** — a scheduled trigger is an ordinary request with no human waiting; budget, not
  attribution, is the control on model calls. It does not say a component with no budget accounting
  may make model calls — see §6 below.
- **ADR-044 §3** — system-control services are not reachable from a client whose job is not operating
  the machine; a client reaches only what it is explicitly granted, and the default is nothing.
- **ADR-046 §3** — nothing on root may be able to open the volume.
- **PROJECT.md §12** — Definition of Done, copied and adjusted at §15.

## 6. The constraint that scopes this phase

**Nothing this phase schedules may call a model.** This is not in the roadmap entry and is stated
here because it determines what the trigger's target is allowed to do.

ADR-040 makes scheduled triggers ordinary and replaces attribution with budget as the control on
autonomous model spend. But the spend governor ADR-040 §2 depends on does not exist — ADR-033 §5
assigns it to Phase 15.1, which has not run. A scheduler able to reach the model helper today would
be an unmetered autonomous spend path, exactly what ADR-040 traded attribution away for budget to
avoid, with no budget behind it yet.

**Decision: Phase 12's trigger observes and reports locally. It never reaches the model helper.**
Enforced structurally, not by omission of code alone (§7.2, §8): the unit that runs the watchdog and
notifier logic carries `RestrictAddressFamilies=AF_INET AF_INET6` with **no `AF_UNIX`**. It cannot
open a UNIX socket at all, so `/run/homelab-model-helper.sock` is unreachable at the kernel's seccomp
filter, before the socket's own `SocketGroup=homelab-bot` permission is ever consulted. This is the
same principle ADR-025 §2 states for the socket itself, applied one layer out: a rule in a committed
unit file, checkable on the running unit, rather than a promise about what the script chooses to
dial.

What would have to exist first for a later phase to lift this: the spend governor (ADR-033 §5, Phase
15.1) landed and enforcing budget before the call; and a new ADR authorising this specific client
(the scheduler) to reach the model helper, per ADR-044 §4's default of nothing. Recorded for whichever
phase reaches for it — likely 15.1 or a phase after it, not decided here.

## 7. Implementation scope

### 7.1 Topology: two units, three roles, not three units

**Scheduler, watchdog and notifier are three roles inside one process, triggered by one systemd
timer.** Two new units, not three:

- `homelab-watchdog.timer` — `OnBootSec=90s`, no `OnUnitActiveSec=`. Ninety seconds gives Tailscale
  and DNS room to come up (Phase 18.1's own boot took 27.6 s to userspace; 90 s is headroom, not a
  measured requirement, and is a candidate for tuning during execution — see §6 Decisions still
  open). No repeat interval: this is a boot-recovery signal, not a heartbeat, per the roadmap's own
  "recovery-oriented, not real-time." Enabled via `WantedBy=timers.target`, which makes it
  **boot-class** under the headless-change standard (`docs/standards/safe-changes-headless.md`,
  ADR-041) — classify it as such in the execution runbook, the same way Phase 18.1 classified
  `/etc/fstab` edits.
- `homelab-watchdog.service` — `Type=oneshot`, started by the timer. Runs
  `/usr/local/sbin/homelab-watchdog.sh` once. No `Restart=` beyond `on-failure` with a bounded
  `RestartSec=`/`StartLimitBurst=`, mirroring the bot's own §"Restart policy" reasoning
  (`config/systemd/homelab-telegram-bot.service`): a clean exit stays stopped, a failure gets bounded
  retries, not a loop.

**Why not three units.** A separate scheduler daemon would duplicate what `systemd-timer(7)` already
does for free — the brief's own hint stands: a systemd timer is a trigger source, and this phase needs
nothing more than one. Splitting watchdog and notifier into two units would need a hand-off mechanism
(a file, a socket, an argument) whose only purchase is process isolation between roughly thirty lines
of state-reading code and roughly ten lines of `curl`. Phase 18.1's own lesson — most of its seven
runbook defects came from unnecessary structure, not from too little — argues against building that
hand-off for a benefit this phase cannot cash in: both roles read no secret and hold no privilege
banned by §5's ADRs, so isolating them from each other buys nothing that isolating them from the
volume and the bot does not already buy.

**Why this still satisfies "must not share a process with what it watches."** *What it watches* is
`homelab-data.target`, the probe, and the bot's own long-polling process — not the notifier role.
`homelab-watchdog.service` shares a process with none of them: it is started independently by its own
timer, has no `Requires=`, `After=`, `PartOf=`, or `Condition*=` naming any of them, and its own crash
is visible rather than silent — a failed oneshot unit shows in `systemctl --failed` and moves
`is-system-running` to `degraded`, a structurally different (and noticed) failure mode from a crash
folded into another unit's process.

### 7.2 How the notifier reaches Telegram

The bot holds the token via `LoadCredential=`, and ADR-023 §7 means it never forks a process — so the
notifier cannot be a subprocess of the running bot, and the bot has no listening socket to be asked
over. `homelab-watchdog.service` gets its own `LoadCredential=bot-token:/etc/homelab-telegram-bot/
token` line, naming the **same file** the bot's unit already names. This is free: `LoadCredential=` is
evaluated by systemd (PID 1, root) before the service's own process starts, and it hands that process
a private tmpfs copy in `$CREDENTIALS_DIRECTORY` — no DAC read permission on the source file is
needed by the unit's `User=`, and the source file's own `root:root 0600` mode is untouched. No
credential is copied to a new path; the bot's unit file is not edited; `systemd-analyze security
homelab-telegram-bot.service` cannot change because that file does not change.

**`User=homelab-bot`, reusing the account Phase 07 already provisioned, not a new one.** The
allowlist at `/etc/homelab-telegram-bot/allowlist` (`root:homelab-bot 0640`) already grants exactly
the read this role needs — the numeric IDs that double as Telegram `chat_id`s for a private chat —
with no new group grant. `id homelab-bot` does not change: reusing an account for a second,
independent unit does not alter what that account reports about itself. A brand-new account would add
a group, a home-directory decision and an allowlist-access grant to reproduce access the existing
account already has correctly scoped, for no isolation benefit — the two roles' failure mode is
identical (leak the same token to the same channel), so separating their identity buys nothing ADR-011
is actually for. `homelab-watchdog.service` still gets its own independent hardening block (mirroring
the bot's, not `Include=`-shared with it — one unit, one reviewable file, per Phase 18.1's "two
committed config files did not match" lesson about drift between nominally-linked files).

**No new listening socket.** The unit makes one outbound HTTPS POST (`api.telegram.org`) and exits;
`RestrictAddressFamilies=AF_INET AF_INET6` (§6) permits exactly that and nothing else.

### 7.3 Boot classification and downtime — the mechanism, named

`journalctl --list-boots` and `journalctl -b -1` read the current boot log, not `wtmp`; `last -x`
reads `wtmp`, where a clean shutdown/reboot writes a `shutdown` pseudo-entry timestamped at the
moment it happened, and an unclean one (power cut) writes none — the next `reboot` entry simply
appears with no `shutdown` before it. That absence is the entire signal:

```
last -x -n 4 reboot shutdown --time-format=iso
```

Newest-first. If the two most recent lines are `reboot` then `shutdown` (in that order), the prior
shutdown was **clean** and its own printed span is the downtime. If the second-most-recent line is
another `reboot` with no `shutdown` between them, the prior stop was **unplanned**, and there is no
recorded "went down at" timestamp — downtime must be computed from what the previous boot last logged
before it stopped:

```
journalctl -b -1 -n 1 --output=short-iso --no-pager
uptime -s
```

`down_seconds = date -d "$(uptime -s)" +%s  -  date -d "<previous-boot's-last-log-timestamp>" +%s`.
This is an approximation (the last log line is not necessarily the instant power was lost) and the
message says "~N minutes," never an exact figure, for exactly that reason. Phase 18.1's own boot
history exercised both branches: boot `-1` (13:07) was followed by a clean rescue reboot; boot `0`
(14:11) was followed by a real power cut — the two cases this mechanism must tell apart, already
observed once on this node.

### 7.4 The message — exact format

One template, instantiated to exactly one of four literal strings per run:

```
Home Lab back up. Down ~<N>m, <clean reboot|unplanned reboot>. Data volume: <STATE>
```

Where `<STATE>` is exactly one of:

| Condition | `<STATE>` |
|---|---|
| `findmnt /srv/homelab` fails, volume configured | `LOCKED -- ssh homelab && sudo data-volume.sh unlock` |
| `findmnt /srv/homelab` succeeds and `systemctl is-active homelab-data.target` is `active` | `unlocked` |
| `/etc/crypttab` has no `homelab-data` entry at all | `not configured on this node` |

The flagship instance, matching the 18.1 handover's own quoted deliverable: *"Home Lab back up. Down
~14m, unplanned reboot. Data volume: LOCKED -- ssh homelab && sudo data-volume.sh unlock"*. No emoji,
no Markdown, no `parse_mode` — plain text, matching the existing `/status` reply's own house style
(`services/telegram-bot/executors.py`), and avoiding a formatting foot-gun in a message this project
does not need styled.

The third row exists because a `crypttab` entry can be absent — a node re-imaged before this phase's
successor lands, or a test environment — and reporting `LOCKED` there would be a false alarm pointing
the owner at an unlock command that cannot do anything. Checking `/etc/crypttab` for the entry, not
just the mapper device, is what tells those two states apart; `/etc/crypttab` is world-readable and
holds no secret (no keyfile path is ever recorded in it — ADR-046 §3), so this needs no privilege.

### 7.5 Files

New, this phase:

- `config/systemd/homelab-watchdog.timer`, `config/systemd/homelab-watchdog.service`.
- `scripts/server/homelab-watchdog.sh` — installed to `/usr/local/sbin/homelab-watchdog.sh`, mode
  755, following `data-volume.sh`'s own precedent of one committed, commented bash script with no
  installer wrapper (unlike the bot and model helper, this needs no new account, no polkit rule and
  no multi-file staging, so a dedicated `install-*.sh` reproduces `data-volume.sh`'s own C11-style
  direct `install` commands for no benefit).

Existing files the execution stage must touch **in the same commit as the two new unit files**, or
the coverage gap Phase 18.1 shipped and this repository just finished fixing
(`fix/verifier-critical-list`) recurs immediately for this phase's own files:

- `scripts/macos/backup-node.sh` — add both new unit files and the new script to `NODE_PATHS`.
- `scripts/macos/verify-node-backup.sh` — add the same three paths to `CRITICAL`, in the same commit.
  These two lists must agree or the coverage check silently stops covering, exactly as it did for
  Phase 18.1's five paths; do not add to one without the other, and do not defer the second list to a
  follow-up commit.

## 8. Validation / tests

**The reboot-survival test — 18.1's stage D shape, its length, not its prose.** Applying its lesson:
check `is-active`, never a command's exit code, because `systemctl start` of a condition-skipped unit
returns 0.

1. **Precondition.** Volume unlocked; `homelab-watchdog.timer` enabled; note `date`.
2. Pull the mains lead. Wait sixty seconds. Reconnect. Touch nothing.
3. From the Mac, poll until reachable, then check the unit ran:
   ```
   until ssh -o BatchMode=yes -o ConnectTimeout=5 homelab true; do sleep 5; done
   ssh homelab systemctl is-active homelab-watchdog.timer
   ssh homelab systemctl show -p Result --value homelab-watchdog.service
   ```
4. **Verify:** `is-active` on the timer reports `active`; the service's last `Result` is `success`;
   the Telegram message arrived, unprompted, matching §7.4's `unplanned reboot` / `LOCKED` row (the
   volume does not survive an unattended reboot — §2); `systemctl --failed` is empty; `is-system-running`
   is `running`.
5. **Abort / what the console is for:** if the timer shows `inactive` after the window it should have
   fired in, the console (attached, tested — Phase 18.1 §Console) reads `journalctl -u
   homelab-watchdog.service -b --no-pager` for the reason before touching anything else.

**Refusals, each with its positive control — proved by attempt, not asserted.**

| Refusal | Attempt | Result | Positive control |
|---|---|---|---|
| Notifier cannot read LUKS key material | `sudo -u homelab-bot cryptsetup luksDump /dev/ubuntu-vg/data` from the watchdog's own account | Permission denied | The same command run by root over SSH succeeds — the volume can still be legitimately inspected, so the refusal is a real boundary, not everything being broken |
| Scheduler/watchdog cannot reach the model helper | From inside `homelab-watchdog.service`'s own cgroup, attempt a `connect(2)` to `/run/homelab-model-helper.sock` | Refused at `AF_UNIX` (not in `RestrictAddressFamilies`), before the socket's own `SocketGroup=` check ever runs | The bot's own unit, which does carry `AF_UNIX`, performing the identical connect to the identical socket succeeds (already proved in Phase 09) |
| Watchdog reports honestly, locked | Run `homelab-watchdog.sh` once while `findmnt /srv/homelab` fails | Message's `<STATE>` row is `LOCKED -- ...` | Immediately after `sudo data-volume.sh unlock`, the same script run again reports `unlocked` — same command, different real state, different truthful output |

**Structural checks, run once, not just observed at boot:**

- `systemctl show -p After,Requires,Wants,Conditions homelab-watchdog.service` names nothing
  belonging to `homelab-data.target`, the probe, or the bot.
- `systemd-analyze security homelab-telegram-bot.service` unchanged from Phase 18.1's `1.3 OK`.
- `id homelab-bot` byte-identical to Phase 07/18.1. `ss -tln` still 6 listeners.
- `systemctl list-dependencies timers.target` includes `homelab-watchdog.timer`, confirming it is
  boot-class and classified as such in the execution runbook (§7.1).

## 9. Security considerations

- **No new listening socket, in either direction.** The trigger fires locally; the only network
  activity this phase adds is one outbound HTTPS POST per boot.
- **No credential is copied or newly created.** The same token file, the same allowlist file, read
  the same way the bot already reads them, from a second unit that reuses the bot's account.
- **The model-helper boundary is enforced by the kernel, not by the script's good behaviour** — see
  §6 and §8's refusal table. A future edit that added `AF_UNIX` back to this unit without a
  corresponding ADR would be the regression to watch for; note it in the guide (§11).
- **Nothing here changes the bot's exposure.** `homelab-telegram-bot.service` is not edited; its
  hardening, its account, and its `1.3 OK` are unaffected by this phase's existence.
- **`homelab-watchdog.timer` is boot-class** (ADR-041) because `WantedBy=timers.target` is part of
  the default boot sequence. Classify it as such in the execution runbook, with the console as the
  named recovery path, the same way Phase 18.1 classified `/etc/fstab`.
- **The volume's own protections are untouched.** This phase adds no keyfile, no TPM enrolment, no
  cached passphrase, and does not touch `/etc/crypttab` or `/etc/fstab` beyond reading the former.

## 10. Repository changes expected

- `config/systemd/homelab-watchdog.timer`, `config/systemd/homelab-watchdog.service` — new.
- `scripts/server/homelab-watchdog.sh` — new.
- `scripts/macos/backup-node.sh`, `scripts/macos/verify-node-backup.sh` — both extended, same commit
  (§7.5).
- No changes to `homelab-telegram-bot.service`, `bot.py`, `router.py`, `executors.py`,
  `model_client.py`, `data-volume.sh`, or any ADR, per §Out of scope.

## 11. Guide documentation required

A short addition (new file or a section in an existing guide, execution stage's call) covering: why a
timer plus one oneshot unit is the whole mechanism; how `last -x` tells a clean reboot from a power
cut with no monitoring daemon; why `LoadCredential=` on a second unit is free and copies nothing; and
why the model-helper refusal is a kernel-level address-family restriction rather than a promise in the
script — so a future reader does not "simplify" it back into a reachable socket.

## 12. Project documentation required

`docs/reference/project-state.md` and `ROADMAP.md`'s Phase 12 entry, updated by whichever stage closes
this phase out (not this brief, which is one new file — §Out of scope). This brief records what must
change there: Phase 12 complete, the watchdog/notifier topology as built, and the volume's
unlocked-at-boot gap (§2) as closed.

## 13. ADRs required / possible

**None required to execute this brief as written.** The model-helper boundary (§6) is enforced by
configuration within this phase's own unit, not by a new architectural rule, and needs no ADR of its
own. If execution finds that `RestrictAddressFamilies=AF_INET AF_INET6` breaks something unanticipated
and the fix would be adding `AF_UNIX` back, that is not a configuration fix — it reopens §6's decision
and needs a superseding ADR before it happens, not after.

## 14. Costs

**Zero.** No package is installed beyond what the node already has (`curl` or `python3`, both
present); no subscription, no metered call, no new hardware.

## 15. Definition of Done

Per `PROJECT.md` §12, adjusted for this phase:

- [ ] The timer fires once per boot and cannot double-fire (§4.1, §8 structural checks).
- [ ] Downtime and boot classification are computed correctly for both a clean reboot and a power cut
      (§7.3, §8).
- [ ] The lock-state read is correct and unprivileged in all three states — locked, unlocked, not
      configured (§7.4, §8).
- [ ] Exactly the four literal message forms in §7.4 are what the notifier can produce; no other text
      reaches Telegram from this mechanism.
- [ ] The refusal table in §8 passes with both attempt and positive control recorded, not asserted.
- [ ] `homelab-telegram-bot.service`, `id homelab-bot`, and `ss -tln` are unchanged (§8 structural
      checks).
- [ ] The real power-cut test (§8, items 1–5) passes and the notification arrives unprompted.
- [ ] `backup-node.sh`'s `NODE_PATHS` and `verify-node-backup.sh`'s `CRITICAL` both gain the three new
      paths, in the same commit (§7.5).
- [ ] Relevant repository files are committed; the guide is updated (§11); project documentation is
      updated (§12).
- [ ] No ADR is required (§13), or one is written if execution finds otherwise.
- [ ] Actual costs recorded as zero, or corrected if not (§14).
- [ ] Problems, failed approaches and lessons are recorded honestly, including anything about the
      90-second boot delay or the classification heuristic that did not survive contact with the real
      node.
- [ ] Tested versions recorded (`systemd`, `curl` or `python3`, whichever is used).
- [ ] `main` represents a known-working state after this phase's handover merges — not this brief's
      branch, which does not merge.
- [ ] `is-system-running` reports `running` with no failed units, both immediately after the power-cut
      test and after the timer has fired.
- [ ] A structured handover is written into `docs/handovers/`, stating what the next phase inherits.

## 16. Return handover requirements

The execution stage's handover must state, separately and by name:

**To whichever phase runs next (18.2, per the current sequencing note):** the watchdog/notifier
mechanism now exists and depends on nothing 18.2 changes about `/srv/homelab`'s ownership or layout;
18.2 must not add a `ConditionPathIsMountPoint=/srv/homelab` or any `Requires=`/`After=` on the volume
to `homelab-watchdog.service` or `.timer` — doing so would silently reintroduce "the watchdog dies
with the thing it watches," the exact failure this phase exists to rule out.

**To Phase 15.1 (spend governor), by name:** §6's constraint — this phase's scheduler cannot reach the
model helper, enforced by omitting `AF_UNIX` from `RestrictAddressFamilies`. Lifting it requires both
the governor landed and enforcing budget before any call, and a new ADR naming the scheduler as a
client authorised to reach that service (ADR-044 §4's default is nothing). This phase does not lift
it and does not design toward lifting it; it names the two preconditions and stops.

**Open risks and unsatisfied controls, not to be silently inherited:**

- The 90-second boot delay (§7.1) is a starting guess, not a measured requirement. If the real node
  needs longer for Tailscale/DNS before the first send can succeed, that is this phase's tuning to do
  during execution, and the handover must record what value actually worked and why.
- The classification heuristic in §7.3 depends on `wtmp` recording a `shutdown` entry for every clean
  stop. If a future clean-shutdown path (e.g. `systemctl poweroff` versus `reboot`, or a crash inside
  a shutdown hook) does not write one, the heuristic will misclassify a clean stop as unplanned. Not
  fixed here; recorded as a known edge the execution stage should test at least once, not assume.
- Multi-recipient delivery iterates the existing allowlist; it has never been exercised with more than
  one entry, since the node has one owner. Untested with more than one ID, and not blocking.
