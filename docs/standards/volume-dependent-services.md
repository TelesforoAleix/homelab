# Volume-Dependent Services

**Status:** Standard. Written by Phase 18.2 under [ADR-043](../decisions/ADR-043-cross-cutting-contracts.md)
(the pattern is shared by Phases 12, 18.2 and 23) from the pattern Phase 18.1 proved twice.
**Applies to:** every systemd unit that reads or writes `/srv/homelab`, and — by its negative clause —
every unit that *observes* the volume.

The data volume ([ADR-037](../decisions/ADR-037-encryption-at-rest-executed.md)) is `noauto`. After a boot it
is locked until a person runs `sudo data-volume.sh unlock`. A unit that needs the volume therefore has
two honest states on a fresh boot: *skipped because the volume is locked* and *running because it was
unlocked*. It must never have a third — *failed* — because the volume was not there, and it must never
run against the empty mountpoint underneath.

## 1. The contract — four directives

```ini
[Unit]
ConditionPathIsMountPoint=/srv/homelab
After=homelab-data.target
PartOf=homelab-data.target

[Install]
WantedBy=homelab-data.target
```

| Directive | What it does | Why this one |
|---|---|---|
| `ConditionPathIsMountPoint=/srv/homelab` | Skip the unit unless a filesystem is mounted there | The empty directory under the mount exists whether or not the volume is open; a plain `ConditionPathExists=` would pass while locked. `Condition`, **not** `Assert`: a failed condition leaves the unit `inactive` with the reason in the journal and does not count as a failure, so `systemctl --failed` and `is-system-running` stay clean. An `Assert` would mark the unit failed on every locked boot |
| `After=homelab-data.target` | Order the start after the target | The target is started by `data-volume.sh unlock` *after* the mount; `After=` makes the condition check happen once the mount is in place, not racing it |
| `PartOf=homelab-data.target` | Stop and restart with the target | `data-volume.sh lock` stops the target first; `PartOf=` propagates that stop so nothing is still writing when the volume is unmounted. Without it `lock` gets a busy mount |
| `WantedBy=homelab-data.target` | Enable through the target, not `multi-user.target` | Enabling into `multi-user.target` would start the unit at boot, when the volume is always locked; the condition would skip it and nothing would start it on unlock. Through the target, unlock pulls it in |

Enable with `sudo systemctl enable <unit>` — the `[Install]` section makes that a symlink under
`homelab-data.target.wants/`. Never `enable --now` while the volume is locked and expect it to start.

## 2. Two things every script must know

**`systemctl start` of a skipped unit returns 0.** A condition that fails is not an error to systemd.
Check `systemctl is-active <unit>`, never `start`'s exit code — observed in Phase 18.1 and again in
this phase's own validation table.

**A skipped unit is `inactive`, not `failed`.** `journalctl -u <unit>` shows
`ConditionPathIsMountPoint=/srv/homelab was not met`. That line is the refusal working, not a bug
report.

## 3. The canary

One unit is the reference implementation of this contract — the one you start-while-locked to prove
the pattern still holds after a systemd upgrade or a unit rewrite. Phase 18.1's canary was
`homelab-data-probe.service`, a fixture that wrote a timestamp into the volume. From Phase 18.2 the
canary is **`homelab-workbench.service`** (`config/systemd/homelab-workbench.service`), a real service,
and the probe is removed. If the Workbench is ever removed, name a new canary in the same commit.

The proof is always a pair: the refusal (`lock` → `start` → `is-active` → `inactive`, journal line
present) *and* the positive control (`unlock` → `is-active` → `active` without a manual start).

## 4. The negative clause — units that must NOT carry this contract

Anything whose job is to **observe** the volume must not **depend** on it. If it did, a locked volume
would silently skip the one unit whose purpose is to say the volume is locked.

Concretely, and by name (Phase 12 handover, *Phase 18.2 — by name*, item 2):

- `homelab-watchdog.service` and `homelab-watchdog.timer`
- `homelab-notify@.service`
- any future health check, metrics exporter or reminder that reports on the volume's state

carry **none** of `ConditionPathIsMountPoint=`, `Requires=`, `Wants=`, `After=` or `PartOf=` naming
`/srv/homelab`, `homelab-data.target`, or any unit that does. They read the volume's state from the
outside — `/etc/crypttab` and `findmnt /srv/homelab` — and live on the root filesystem.

The check is structural and is re-run after every unit change on the node:

```bash
systemctl show -p After,Requires,Wants,PartOf,ConditionPathIsMountPoint --value homelab-watchdog.service
# → no "srv", no "homelab-data", no "workbench", no "bot"
```

The evidence it matters: on 2026-09-12 the node came back from a real power cut with the volume locked
and the watchdog ran and said so. It could only do that because it does not wait for the volume.

## 5. What the contract does not cover

- **Reaching the volume from another unit's filesystem view.** A unit hardened with
  `ProtectSystem=strict` needs `ReadWritePaths=/srv/homelab` (or a narrower path) in addition to the
  four directives; the contract governs *when* a unit runs, not *what it may touch*.
- **Docker.** `data-root` is on the root filesystem by decision (Phase 18.2 §6.5). A container that
  needs volume content bind-mounts it; if a container ever needs the contract itself, that is the ADR
  the 18.1 handover asked for.
- **The unlock itself.** `data-volume.sh` starts the target after mounting; the contract assumes that
  order and nothing else starts the target.

## 6. The one-screen version

```text
Needs the volume?   ConditionPathIsMountPoint= · After= · PartOf= · WantedBy=homelab-data.target
Condition, not Assert.        Skipped is inactive, not failed.
start returns 0 on skip.      Check is-active.
Prove it as a pair:           lock → refusal ; unlock → active.
Observes the volume?          NONE of the above. Read crypttab + findmnt. Live on root.
Canary:                       homelab-workbench.service (was the probe).
```
