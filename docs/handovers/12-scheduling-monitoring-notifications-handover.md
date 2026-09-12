# Phase 12 Handover — Scheduling, monitoring and notifications

- **Phase:** 12 — repurposed by ADR-045 §3 as the scheduler, watchdog and notifier
- **Brief:** [`12-scheduling-monitoring-notifications.md`](12-scheduling-monitoring-notifications.md),
  merged to `main` before implementation per ADR-017 (`ab093ef`)
- **Executed:** 2026-09-12, on branch `phase/12-work` in a separate worktree; the owner ran every
  privileged step and both reboot tests over SSH
- **Addressed to:** Phase 18.2 (migration), Phase 15.1 (spend governor), and whoever next touches
  `homelab-notify@.service`

## Outcome

**Complete.** The node now reports its own recovery — downtime, clean-versus-unplanned, and the data
volume's lock state — within about two minutes of every boot, and pages the owner when the bot, the
model helper or the watchdog itself dies. Both were proved live on 2026-09-12: a clean `reboot` and
a real power cut each produced the correct message unprompted, including `LOCKED`; a real crash
produced an alert and a clean `stop` did not; and the model helper refused the watchdog at the kernel.
Nothing about the bot, its account or the node's listening surface changed. No package was installed,
no ADR was needed, and the cost is zero.

The brief's mechanism did not survive contact with the node in one respect: `last -x` does not exist
on this Ubuntu. The same signal is read from the journal instead, and the episode of getting that
wrong first is recorded under *Problems* rather than smoothed over.

## What the next phase inherits

### Phase 18.2 — by name

1. **The watchdog/notifier exists and depends on nothing 18.2 changes.** It reads `/etc/crypttab`
   (first field `homelab-data`) and asks `findmnt /srv/homelab`. It does not care who owns the volume,
   what is in it, or how it is laid out.
2. **Do not add `ConditionPathIsMountPoint=/srv/homelab`, `Requires=`, `After=`, `Wants=` or `PartOf=`
   naming the volume, `homelab-data.target`, the probe, or the bot to `homelab-watchdog.service` or
   `homelab-watchdog.timer`.** Any of them silently reintroduces *"the watchdog dies with the thing it
   watches"* — a locked volume would then skip the one unit whose job is to say the volume is locked.
   This is checked structurally: both unit files carry no dependency on any of those, and the
   power-cut test on 2026-09-12 (volume locked, watchdog ran, message said `LOCKED`) is the evidence
   it works that way.
3. **Re-verify before writing your brief:**
   `systemctl is-enabled homelab-watchdog.timer` → `enabled`;
   `systemctl show -p After,Requires,Wants,PartOf,ConditionPathIsMountPoint --value homelab-watchdog.service`
   → no mention of `srv`, `homelab-data`, or the bot;
   `journalctl -u homelab-watchdog.service -b` → one run, one of the four literal messages.

### Phase 15.1 — by name

1. **§6's constraint is enforced, and it is enforced in the unit, not in the script.**
   `homelab-watchdog.service` and `homelab-notify@.service` both carry
   `RestrictAddressFamilies=AF_INET AF_INET6` — no `AF_UNIX`. The account they run as
   (`homelab-bot`) *is* in the model helper socket's group, so the DAC layer would let it through; the
   kernel's seccomp filter refuses socket creation first. Observed 2026-09-12 under the identical
   restriction: `OSError: [Errno 97] Address family not supported by protocol`.
2. **Lifting it requires both preconditions, and this phase names them and stops:**
   (a) the spend governor landed and enforcing budget before any call; and
   (b) a new ADR naming the scheduler as a client authorised to reach the model helper — ADR-044 §4's
   default is nothing. Adding `AF_UNIX` back is the reversal of a decision, not a configuration fix,
   and the guide says so at the point where a reader would be tempted.
3. **A side effect you will meet:** without `AF_UNIX` these units cannot run `systemctl` at all (it
   talks to PID 1 over D-Bus or `/run/systemd/private`). The watchdog checks `findmnt` alone for that
   reason. If 15.1's design needs the scheduler to ask PID 1 anything, that is the same `AF_UNIX`
   decision in a different costume.

### The residual, named — `homelab-notify@.service`'s own failure is unwatched

`homelab-notify@.service` has no `OnFailure=`. That is the recursion guard (a notifier that pages on
its own failure by starting itself would loop), verified on the node:
`systemctl show -p OnFailure --value "homelab-notify@test.service"` → empty. The consequence is that if
Telegram is unreachable at the moment an alert fires, that alert is lost silently; the next boot's
watchdog message is the recovery path. No phase is asked to fix this here. The honest fix, if one is
ever wanted, is a *different* mechanism (a spool, a second channel), not a second `OnFailure=`.

### Open risks and unsatisfied controls — not to be silently inherited

- **The 90-second boot delay worked, unchanged.** `OnBootSec=90s` is the shipped value. On the two
  real boots of 2026-09-12 the watchdog ran 102 s and 89 s after the first journal entry of the boot
  (17:23:31 → 17:25:13; 17:33:22 → 17:34:51), and the send succeeded first time on both
  (`NRestarts=0`, `Result=success`). Tailscale and DNS were up by then on this node. This is one
  node, one network, two samples — a measurement, not a guarantee. If a future node needs longer, the
  symptom is `homelab-watchdog.service` failing on the send and `homelab-notify@watchdog.service`
  paging you with the curl error once the network is up.
- **The classification edge, rewritten for the journal mechanism.** The classifier calls a stop clean
  if and only if PID 1 logged `Shutting down.` in the previous boot. Any clean-stop path in which PID
  1 does not log that line — a crash inside a shutdown hook, a future systemd that changes the
  message, a `systemctl poweroff` that behaves differently from `reboot` — will be reported as
  `unplanned reboot`. **Only `sudo reboot` was tested as the clean path**; `poweroff` was not, and
  neither was `halt`. The failure mode is a false "unplanned", never a false "clean": the absence of
  the marker is what says unplanned, so a missing marker errs towards alarming, not reassuring. The
  reverse edge — a power cut that somehow contains the PID-1 marker — has no known path.
- **Multi-recipient delivery is untested.** `homelab-notify.sh` iterates the allowlist and posts to
  each ID; the node has one owner, so the loop has only ever run once per call. Not blocking; the
  first time a second ID is added, watch one send.
- **The alert is per crash, not per outage.** `OnFailure=` runs on every transition into `failed`,
  including the ones `Restart=` recovers from. A crash loop pages once per crash (seven alerts during
  the kill run). This is systemd's semantics and the brief's requirement; it is recorded here because
  the *volume* of alerts in a real crash loop was not anticipated by anyone.

### Ground already covered

- **All seven deployed files are in both macOS backup lists** (`NODE_PATHS`, `CRITICAL`), same
  commit. A restore reproduces the whole mechanism, not the watchdog without its notifier.
- **`homelab-notify.sh` is the single definition of "post this text to every allowlisted chat_id."**
  Anything in a later phase that wants to send a Telegram message from a unit should call it with
  `LoadCredential=bot-token:/etc/homelab-telegram-bot/token` and `User=homelab-bot`, not reimplement
  it. Its `--alert <alias>` mode composes the failure text; its plain mode sends whatever it is given.
- **The `OnFailure=` drop-in pattern** (`<unit>.d/onfailure.conf`, one line, a literal alias instance)
  is the way to watch a new unit. It does not edit the watched unit's file.
- **The instance-form `systemctl show`** for template properties on systemd 259, and the two
  `pipefail`/SIGPIPE traps, are written up in the guide so nobody rediscovers them.

## What was implemented

- `homelab-watchdog.timer` — `OnBootSec=90s`, `WantedBy=timers.target`, no recurrence.
- `homelab-watchdog.service` — `Type=oneshot`, `User=homelab-bot`, `SupplementaryGroups=systemd-journal`,
  `LoadCredential=bot-token:…`, `RestrictAddressFamilies=AF_INET AF_INET6`, full hardening set,
  `OnFailure=homelab-notify@watchdog.service`, `Restart=on-failure` bounded by
  `StartLimitBurst=5`/`StartLimitIntervalSec=300`.
- `homelab-watchdog.sh` — `classify_boot()` (journal, PID 1 marker, `--list-boots` timestamps, dies
  with a clear message if boot `-1` is absent) and `volume_state()` (`/etc/crypttab` first, then
  `findmnt`), composing exactly one of four literal messages and calling the notifier.
- `homelab-notify.sh` — reads the token from `$CREDENTIALS_DIRECTORY` only, posts to every allowlist
  entry with `curl`, `--alert <alias>` mode for failure text with the unit's last five journal lines.
- `homelab-notify@.service` — the template the three `OnFailure=` lines target; same account,
  credential and address-family restriction as the watchdog; **no `OnFailure=`**.
- `homelab-telegram-bot.service.d/onfailure.conf`, `homelab-model-helper@.service.d/onfailure.conf`.
- `backup-node.sh` / `verify-node-backup.sh` — seven new paths each, same commit.

## Final architecture / state

Relative to the Phase 18.1 close: one enabled timer, one static oneshot, one static template, two
drop-ins, two scripts in `/usr/local/sbin`. No new account, no new group membership in `/etc/group`,
no sudoers entry, no listening socket, no package. `id homelab-bot`, `ss -tln` (6 listeners) and the
bot's `systemd-analyze security` (`1.3 OK`) are unchanged. `current-architecture.md` carries the new
topology and strikes the *"nothing reports the bot dying"* line.

## Validation performed

All by the owner on the node, 2026-09-12 (UTC). Every line below was observed, not predicted.

| Check | Result |
|---|---|
| `md5sum` of the seven staged artifacts vs repository | identical, both directions |
| `systemctl show -p OnFailure --value homelab-telegram-bot.service` | `homelab-notify@bot.service` |
| `… "homelab-model-helper@test.service"` | `homelab-notify@model-helper.service` |
| `… "homelab-notify@test.service"` (recursion guard) | empty |
| `systemd-run … -p 'RestrictAddressFamilies=AF_INET AF_INET6' python3 … AF_UNIX connect` | `OSError: [Errno 97] Address family not supported by protocol`; positive control: the bot's own connection (Phase 09) |
| `sudo -u homelab-bot cryptsetup luksDump /dev/ubuntu-vg/data` / as root | `does not exist or access denied` / full header |
| 15 × `systemctl kill -s SIGKILL homelab-telegram-bot.service` | bot `failed (Result: signal)` at 17:16:38 and stayed down; `homelab-notify@bot.service` ran `status=0/SUCCESS`; Telegram: `Home Lab alert: homelab-telegram-bot.service failed.` + journal lines; seven alert runs 17:14:51–17:16:38 |
| `systemctl stop` then `journalctl -u "homelab-notify@bot.service" --since "5 minutes ago"` | `Result=success`; no run after 17:16:38 |
| `systemctl enable --now homelab-watchdog.timer` | fired 17:20:22: `Home Lab back up. Down ~1m, unplanned reboot. Data volume: unlocked` (the 18.1 power-cut transition); `list-timers` NEXT `-` |
| `sudo reboot` (17:23:14) | watchdog 17:25:13: `Home Lab back up. Down ~0m, clean reboot. Data volume: LOCKED -- ssh homelab && sudo data-volume.sh unlock`; `journalctl -b -1 -q _PID=1 -g 'Shutting down\.'` → one line |
| mains pulled (~17:33) | watchdog 17:34:51: `Home Lab back up. Down ~0m, unplanned reboot. Data volume: LOCKED -- ssh homelab && sudo data-volume.sh unlock`; same `journalctl` → empty, exit 1 |
| `sudo data-volume.sh unlock` → `findmnt /srv/homelab`, after each boot | mount row present (positive control for `LOCKED`) |
| Every Telegram message | text identical to the journal line |
| Post-test: `id homelab-bot` / `ss -tln \| wc -l` / `--failed` / `is-system-running` / bot security | `uid=999(homelab-bot) gid=982(homelab-bot) groups=982(homelab-bot)` / `7` / empty / `running` / `1.3 OK` |
| `NRestarts` / `Result` on `homelab-watchdog.service` after three boots | `0` / `success` |

Not exercisable on this node: the `not configured on this node` message (crypttab has the entry);
`poweroff` as a clean path; more than one allowlist entry.

## Files changed

- `config/systemd/homelab-watchdog.timer`, `homelab-watchdog.service`, `homelab-notify@.service` — new
- `config/systemd/homelab-telegram-bot.service.d/onfailure.conf`,
  `config/systemd/homelab-model-helper@.service.d/onfailure.conf` — new
- `scripts/server/homelab-watchdog.sh`, `scripts/server/homelab-notify.sh` — new
- `scripts/macos/backup-node.sh`, `scripts/macos/verify-node-backup.sh` — seven paths each
- `guide/12-scheduling-monitoring-notifications/README.md`, `guide/README.md` — new / index
- `docs/architecture/current-architecture.md`, `docs/reference/project-state.md`, `ROADMAP.md`,
  `docs/reference/costs.md` — Phase 12 complete
- this handover

Commits on `phase/12-work`: `3420401` (the eight files), `54b7569` (fail loudly without `last` — the
wrong conclusion, kept), `04d4236` (journal classifier), `e2a6f3f` (seven backup paths), `12c8a64`
(`journalctl -g`, not `| grep -q`), then the three documentation commits.

## Guide updates

[`guide/12-scheduling-monitoring-notifications/README.md`](../../guide/12-scheduling-monitoring-notifications/README.md)
— the brief's §11 four topics, with: journal-based classification and why; `_PID=1` mandatory; the
ext4 line is not a signal; the two systemd-259 corrections and the "do not simplify this back"
warning; the two `pipefail` traps; `OnFailure=` per crash and the 15-kill start limit; the owner's
observed run; tested versions. Indexed in `guide/README.md`.

## Project documentation updates

`docs/architecture/current-architecture.md` (state line, physical-roles block, Deployed row, two
*Not implemented yet* lines struck with the reason), `docs/reference/project-state.md` (current
phase, Phase 12 status section, services row), `ROADMAP.md` (Phase 12 status block),
`docs/reference/costs.md` (Phase 12: 0 DKK).

## ADRs

**None created, superseded or proposed**, as the brief's §13 anticipated. The model-helper boundary
is configuration inside this phase's own units. The one condition §13 named for needing an ADR —
that the fix for something `RestrictAddressFamilies` breaks would be adding `AF_UNIX` back — was
approached once (`systemctl is-active` from inside the unit) and resolved by dropping the check,
not by widening the filter.

## Tested versions

Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic; systemd 259.5 (`259.5-0ubuntu3.4`); util-linux
2.41.3 (`2.41.3-3ubuntu2.2`, no `last`/`utmpdump`); curl 8.18.0; python3 3.14 (refusal probe only);
`wtmpdb` 0.75.0-5ubuntu1 was the candidate package, **not installed**.

## Security notes

- Both new units run as the bot's account with the bot's token via `LoadCredential=`; no secret is
  copied, no file mode changes, the bot's unit is untouched (drop-in only).
- `RestrictAddressFamilies=AF_INET AF_INET6` on both — the phase's one real boundary, tested by
  attempted access with a positive control.
- `SupplementaryGroups=systemd-journal` grants journal read inside the units only; `id homelab-bot`
  is unchanged.
- Nothing here can open the volume (ADR-046 §3): `/etc/crypttab` + `findmnt`, the unprivileged half of
  `data-volume.sh status`. `luksDump` as `homelab-bot` is refused.
- The alert's journal excerpt is five lines of the failed unit's own log, truncated to 200 columns. A
  unit that logs a secret would leak it into Telegram; none does, and ADR-039's rule (content chosen
  by whatever can write a log line never leaves) is the reason to keep it that way.
- Outbound HTTPS to `api.telegram.org` only; no listener.

## Costs

**0 DKK.** No package, no subscription, no metered call. Recorded in `docs/reference/costs.md`.

## Problems / failures / lessons

1. **`last` does not exist, and the first fix was wrong.** The brief specified `last -x`; the node's
   util-linux 2.41.3 does not ship it. The executor wrote a journal-based substitute, tested it on the
   boot `-1 → 0` transition, got "unplanned", and — believing that transition was Phase 18.1's rescue
   reboot — declared the heuristic *disproved*, shipped a version that dies when `last` is absent, and
   reported a blocking finding. The transition was in fact 18.1's **power-cut test**; the rescue
   reboot was `-2 → -1`, which the heuristic classifies correctly. The orchestrator caught it by
   running `journalctl --list-boots` and the PID-1 grep on both transitions. **Lesson:** a disproof is
   only as good as the label on the test case; when the node's own history is the test fixture, read
   the history from the node, not from memory of the handover. Both commits are on the branch
   (`54b7569`, `04d4236`) and the script header keeps a four-line record.
2. **`_PID=1` is not optional.** Boot `-1` contains a *user* manager's `Reached target
   shutdown.target` line. A text-only grep would have called the power cut clean.
3. **Two `pipefail` traps in one function.** `journalctl … | head -1` was observed exiting 141
   (SIGPIPE) with no output; `| grep -q` has the same latent failure and only passed because the
   marker is PID 1's last line. Inside `if`, 141 is simply "false" — a silent misclassification, not
   an error. Fixed with `--list-boots` and `journalctl -g`; the orchestrator caught the second one on
   review after the first had been fixed and documented, which is its own lesson about fixing a
   class of bug rather than an instance.
4. **The runbook's kill count was wrong.** "Five kills within a couple of minutes" became fifteen,
   because unhurried kills spaced by `RestartSec` stayed under `StartLimitBurst=5`/300 s. And the
   bot's final state reads `failed (Result: signal)`, not `start-limit-hit` — *staying down* is the
   evidence.
5. **`OnFailure=` fires per crash.** Seven alerts in the kill run. Correct, and not what anyone had
   pictured.
6. **`systemd-run` leaves a failed transient unit behind.** `run-p13000-i11327.service` sat in
   `systemctl --failed` after the refusal probe until `reset-failed`. Not ours, but it would have
   polluted the "no failed units" DoD check.
7. **The terminal drops the second argument of a long `install` at the wrap point.** Twice. `cd`
   into the destination and use a short target name; the 18.1 handover's seven defects gain an eighth.
8. **The brief's backup-list scope was three files; it should have been seven.** Flagged by the
   executor as an open question rather than silently widened, then widened by the orchestrator's
   decision in its own commit (`e2a6f3f`). The right sequence, even though it cost a round trip.
9. **`systemctl show` on a bare template name fails on systemd 259**; use an instance.
10. **`systemctl is-active` from inside a unit without `AF_UNIX` is impossible**, for any account. The
    brief's §7.4 table asked for it. Dropped in favour of `findmnt` alone — narrower, and honest about
    being narrower.

## Deviations from phase brief

- **§7.3 mechanism:** journal (`journalctl -b -1 _PID=1 -g 'Shutting down\.'` and `--list-boots`)
  instead of `last -x`. Same signal, different file; no package.
- **§7.4 table:** `findmnt` alone, not `findmnt` AND `systemctl is-active homelab-data.target` (the
  latter is impossible under §6's own restriction).
- **§7.5 backup lists:** seven paths, not three.
- **§7.6 "two-line case statement":** lives in `homelab-notify.sh --alert`, not inline in the unit's
  `ExecStart=`; `bash -n`-checkable and free of unit-file quoting.
- **`SupplementaryGroups=systemd-journal`** on both units, not in the brief; needed for journal reads,
  chosen over an `/etc/group` change so `id homelab-bot` stays identical.
- **§8's recursion-guard command** uses an instance name.

## Open issues / technical debt

- `homelab-notify@.service`'s own failure is unwatched (by decision, above).
- `poweroff`/`halt` untested as clean-stop paths; multi-recipient send untested.
- The `not configured on this node` message has never been produced on a real node.
- Metrics remain unbuilt; the *Not implemented yet* line in `current-architecture.md` says so.

## Recommended roadmap changes

None beyond what is actioned in this phase's documentation commit. Phase 15.1's entry already
carries the governor; the two preconditions for lifting `AF_UNIX` are stated in the *Phase 15.1 —
by name* section above and in `current-architecture.md`. Phase 18.2's entry needs no change; its
constraint is in its section above.

## Definition of Done

Brief §15, each item against the owner's observed results of 2026-09-12:

- [x] Timer fires once per boot, cannot double-fire — OBSERVED: three boots, one run each
  (17:20:22, 17:25:13, 17:34:51); `list-timers` NEXT `-`; no `OnUnitActiveSec=`/`OnCalendar=`.
- [x] Downtime and classification correct for clean reboot and power cut — OBSERVED: `~0m, clean
  reboot` after `sudo reboot` with the PID-1 marker present; `~0m, unplanned reboot` after the mains
  pull with it absent; `~1m, unplanned reboot` for the earlier 96 s power-cut gap.
- [x] Lock-state read correct and unprivileged — OBSERVED `unlocked` and `LOCKED` live; `not
  configured` verified by the crypttab logic against the real file, not producible on this node.
- [x] Exactly the four literal message forms — three OBSERVED byte-identical in journal and Telegram;
  one `printf` template, two enumerations, no other text path.
- [x] Refusal table with attempt and positive control — OBSERVED: `Errno 97` vs the bot's own
  connection; `luksDump` denied vs the root header.
- [x] Bot unit, `id homelab-bot`, `ss -tln` unchanged — OBSERVED after the kill run and after both
  reboots.
- [x] Real power-cut test, notification unprompted — OBSERVED 17:34:51.
- [x] Both backup lists, every new path, same commit — `e2a6f3f`, seven each.
- [x] Failure alert fires on a real crash, not on a clean `stop`; recursion guard checked — OBSERVED.
- [x] `current-architecture.md`'s *bot dying* line — struck, with the reason.
- [x] Repository files committed; guide (§11) and project docs (§12) updated — this branch.
- [x] No ADR required — §13 confirmed; the one trigger condition was not crossed.
- [x] Costs recorded as zero — `costs.md`.
- [x] Problems, failed approaches and lessons recorded — ten above, including the 90 s value and the
  classification heuristic's real history.
- [x] Tested versions recorded — systemd 259.5, curl 8.18.0, util-linux 2.41.3.
- [ ] `main` known-working after this handover merges — **the orchestrator's step after review**;
  this branch does not merge itself.
- [x] `is-system-running` → `running`, no failed units, after the power cut and after the timer fired
  — OBSERVED (the one stale transient unit from the probe was cleared before the reboots).
- [x] Structured handover in `docs/handovers/` stating what the next phase inherits — this file.

PROJECT.md template items not enumerated above: reproducible (seven files, canonical in the repo,
install order in the guide); security considered (above); critical AI-generated components
understood (two scripts, each with a rationale header a non-sysadmin can follow, and the one
non-obvious line — `_PID=1 -g` — explained in three places).
