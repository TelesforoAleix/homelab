# Linux Command Reference

The commands this project actually uses, grouped by **the question they answer** rather than by
topic. Written during Phase 02, from commands run on the reference node.

This is an operator's reference, not a tutorial. The explanations are in
[`guide/02-linux-fundamentals/`](../../guide/02-linux-fundamentals/README.md).

Two conventions:

- `#` means it needs root — and on this node `sudo` **always asks for a password**.
- Anything marked ⚠️ is **lockout-class**. Apply
  [`safe-changes-headless.md`](../standards/safe-changes-headless.md) before running it.

---

## "Where is this thing?"

| Question | Command |
|---|---|
| Where is this program? | `command -v tailscale` · `readlink -f "$(command -v tailscale)"` |
| Which package installed it? | `dpkg -S /usr/bin/tailscale` |
| What files did a package install? | `dpkg -L openssh-server` |
| Where does a file live on disk, really? | `df -h /path` then `findmnt /path` |
| Find files by name | `find /etc -name '*.conf' -type f` |
| Search file *contents* fast | `rg 'PasswordAuthentication' /etc/ssh` |

Directories that matter on this node:

```text
/etc/netplan/                   network config      (0600 root:root, holds the Wi-Fi passphrase)
/etc/ssh/sshd_config.d/         sshd drop-ins       (0600 root:root, first match wins)
/etc/apt/sources.list.d/        package sources     (Ubuntu's, plus Tailscale's)
/etc/systemd/system/            units we wrote      (overrides /usr/lib/systemd/system/)
/usr/lib/systemd/system/        units the OS ships  — never edit these
/var/log/journal/               the binary journal  — read with journalctl, not cat
/srv/                           service data        — where Phase 05 will put things
/proc, /sys                     kernel state as files — not real files on a disk
```

## "Who can read or change this?"

| Question | Command |
|---|---|
| Permissions, owner, group | `ls -l file` · `ls -ld directory` |
| Same, script-friendly | `stat -c '%A %U:%G %n' file` |
| Numeric mode | `stat -c '%a' file` |
| Who am I, and in which groups? | `id` · `id -nG aleix` |
| Who else exists? | `getent passwd \| awk -F: '$3>=1000 && $3<65534'` |
| Which groups exist? | `getent group` |
| Change owner | `# chown root:root file` |
| Change mode | `# chmod 0600 file` |
| Copy *and* set owner/mode atomically | `# install -o root -g root -m 0600 src dst` |

Reading a mode line:

```text
-rw------- 1 root root 3017 Sep  9 12:32 10-homelab-hardening.conf
│└┬┘└┬┘└┬┘
│ │  │  └── others : nothing
│ │  └───── group  : nothing
│ └──────── owner  : read + write
└────────── type   : - file, d directory, l symlink
```

`d rwx r-x r-x` on a directory means something different from a file: `x` is permission to *enter*
it, and `r` is permission to *list* it.

## "Why is this service not running?"

Work down this list in order. Stop when you have the answer.

```bash
systemctl status ssh.service          # 1. state, recent log lines, main PID
journalctl -u ssh.service -b          # 2. everything it logged this boot
systemctl cat ssh.service             # 3. the unit as systemd actually sees it
systemd-analyze verify ssh.service    # 4. is the unit file even valid?
```

`systemd-analyze verify` walks the unit's **dependency closure**, not just the file you named — on
this node it reports deprecation warnings from `xfs_scrub_all.service`, which is nothing to do with
`ssh`. Read the filename on each line before assuming a warning is about your unit.

| Question | Command |
|---|---|
| Is anything broken right now? | `systemctl --failed` |
| Is the whole system healthy? | `systemctl is-system-running` |
| Is it on at boot? | `systemctl is-enabled unit` |
| Is it running now? | `systemctl is-active unit` |
| One property, exactly | `systemctl show ssh.service -p KillMode` |
| What runs on a schedule? | `systemctl list-timers` |
| Reload config without dropping work | `# systemctl reload ssh` |
| Full stop/start ⚠️ | `# systemctl restart ssh` |
| Did my reload actually happen? | `systemctl show ssh.service -p StateChangeTimestamp` |

**`StateChangeTimestamp` moves on a reload. `ActiveEnterTimestamp` does not.** Phase 03 lost hours
to that distinction.

## "What is it doing / what is eating the machine?"

| Question | Command |
|---|---|
| Interactive overview | `htop` (`q` quits) |
| One-shot snapshot, sorted | `ps -eo pid,ppid,user,stat,etime,comm --sort=-pcpu \| head` |
| Who is the parent of what | `pstree -p 1` |
| Load average | `uptime` — compare against `nproc` |
| What is listening on a port | `ss -tlnp` |
| What has this file open | `# lsof /path` · `# fuser -v /path` |

Load average is a count of *runnable-or-waiting* processes, not a percentage. On this node `nproc`
is **4**, so a load of 4.0 means fully busy and 0.03 means idle. A high load with low CPU usually
means processes blocked on disk or network, not on the processor.

`STAT` column: `R` running, `S` sleeping, `D` uninterruptible (usually disk I/O — cannot be killed),
`Z` zombie (finished, parent has not collected it — harmless unless they pile up), `s` session
leader, `l` multi-threaded, `+` foreground.

## "Where has the disk gone?"

Three *different* failure modes. They fail independently and need different commands.

```bash
df -h /            # 1. bytes
df -i /            # 2. inodes  — can hit 100% with the disk nearly empty
# lsof +L1         # 3. deleted files still held open by a process
```

The third is the one that confuses people: `du` walks directory entries, so a deleted-but-open file
is invisible to it while its blocks are still allocated. `df` and `du` disagree, and `df` is right.
The space returns when the process closes the descriptor or exits.

| Question | Command |
|---|---|
| What is using space here? | `du -sh /var/log /var/lib /home /usr` |
| Interactive, drill-down | `ncdu /var` (`q` quits) |
| Layout of disks and mounts | `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS` |
| Directory structure at a glance | `tree -L 2 /etc/ssh` |
| LVM layers | `# pvs` · `# vgs` · `# lvs` |
| How big is the journal? | `journalctl --disk-usage` |

**On this node the volume group has no free extents** — the root LV already fills it. `lvextend` has
nothing to take. Growing storage means adding a disk, not resizing.

## "What happened, and when?"

`journalctl` is a query tool over a binary store. Filter; do not scroll.

| Question | Command |
|---|---|
| One unit | `journalctl -u ssh` |
| This boot only | `journalctl -b` |
| The previous boot | `journalctl -b -1` |
| List the boots it remembers | `journalctl --list-boots` |
| Errors and worse | `journalctl -p err -b` |
| A time window | `journalctl --since "today"` · `--since "1 hour ago"` · `--until "13:00"` |
| Follow live | `journalctl -f -u ssh` |
| Kernel only | `journalctl -k` |
| Combine them | `journalctl -u ssh -b -p warning --since "09:00"` |

Priorities run `emerg alert crit err warning notice info debug`; `-p err` means "err and worse".

Retention is set in `/etc/systemd/journald.conf` (`SystemMaxUse=`). On this node the file is entirely
comments, so every value is the systemd default: cap at 10% of the filesystem.

## "Where did this package come from?"

| Question | Command |
|---|---|
| Refresh the index (safe, changes nothing) | `# apt update` |
| Install upgrades, never remove anything | `# apt upgrade` |
| Allow removals to satisfy dependencies ⚠️ | `# apt full-upgrade` |
| Anything to upgrade? | `apt list --upgradable` |
| Which repository does this come from? | `apt policy tailscale` |
| Which package owns this file? | `dpkg -S /usr/bin/tailscale` |
| Is it installed, and which version? | `dpkg -l openssh-server` |
| Remove packages nothing needs | `# apt autoremove` |

`apt policy` is how you tell a first-party package from a third-party one:

```text
tailscale:  500 https://pkgs.tailscale.com/stable/ubuntu resolute/main amd64 Packages
openssh-server:  500 http://archive.ubuntu.com/ubuntu resolute-updates/main amd64 Packages
```

A third-party source is a `.list` or `.sources` file in `/etc/apt/sources.list.d/` with a
`signed-by=` keyring. **`signed-by=` is the security control**: it says *only this key may sign
packages from this source*, so a compromised third-party key cannot sign a replacement `openssh-server`.

## "What is the network doing?" (read-only)

| Question | Command |
|---|---|
| Addresses, one line per link | `ip -br address` |
| Routes | `ip route` |
| Link state, systemd's view | `networkctl list` |
| DNS configuration | `resolvectl status` |
| Listening sockets + owning process | `ss -tlnp` |
| Overlay status | `tailscale status` · `tailscale ip -4` |
| Test a route the way a user arrives | `ssh -o BatchMode=yes homelab true` |

⚠️ **Everything that *changes* networking is lockout-class on this node.** `netplan try` applies a
change and automatically reverts after 120 seconds unless you confirm — never use `netplan apply`
for a change you have not already proved with `try`.

## "How do I not lose this when my connection drops?"

```bash
tmux new -s work      # start a named session
tmux ls               # list sessions
tmux attach -t work   # reattach after the connection dropped
```

Inside tmux, the prefix is `Ctrl-b`: then `d` to detach, `c` for a new window, `n`/`p` to move
between windows, `%` and `"` to split.

**Anything long-running on a remote host belongs in tmux.** An `apt full-upgrade` interrupted by a
dropped Wi-Fi link can leave dpkg half-configured. In tmux the process keeps running on the server
and you reattach to it. `ssh homelab` then `tmux attach` costs nothing and removes a whole class of
problem.

## Shell things worth knowing

| Idea | Example |
|---|---|
| Exit status: 0 is success | `false; echo $?` → `1` |
| Chain on success | `cmd1 && cmd2` |
| Chain on failure | `cmd1 \|\| echo failed` |
| Redirect output | `cmd > out.txt` (replace) · `>>` (append) |
| Redirect errors too | `cmd > out.txt 2>&1` |
| Discard output | `cmd > /dev/null 2>&1` |
| Pipe | `journalctl -b \| rg -i error \| head` |
| Quote to protect spaces | `rm "$file"` — always, not sometimes |

`set -e` (abort on error) has a trap worth knowing, because Phase 03 got it wrong:

```bash
set -e
false && echo hi     # does NOT abort — a failing non-final link in an && list is ignored
false                # DOES abort — a bare failing command
```

The same applies to the last line of a function: `[ -n "$x" ] && rm "$x"` as a function's final
statement returns 1 when `$x` is empty, and under `set -e` the caller aborts.

## Checks worth running on a schedule you keep in your head

```bash
systemctl is-system-running     # running / degraded
systemctl --failed              # should be empty
df -h / && df -i /              # bytes and inodes
journalctl -p err -b            # errors this boot
apt list --upgradable           # pending security updates
tailscale status                # is the overlay up
```

`scripts/server/verify-install.sh` and `scripts/server/verify-remote-access.sh` bundle these into
reports. `scripts/macos/preflight.sh` runs the subset that matters before a risky change.
