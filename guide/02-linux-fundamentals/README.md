# 02 — Linux Fundamentals

## Goal

Be able to **operate** the reference node rather than only own it: read a permission line, work out
why a service will not start, tell three different kinds of "disk full" apart, query a journal
instead of scrolling it, and — most important on a machine with no monitor — recognise a change that
could lock you out *before* you type it.

By the end you should be able to sit down in front of an unfamiliar Ubuntu server and orient
yourself with about eight commands.

## Why this matters

Phase 01 installed the operating system. Phase 03 made it reachable from anywhere and then removed
its monitor. Neither taught you to run it, and every phase from here on assumes you can.

There is also a specific reason this phase exists **now**, in this order. Phase 03 ended with the
node genuinely headless: no monitor, no keyboard, no cable. Phases 01 and 03 both did their most
dangerous work with a screen an arm's length away, and both quietly relied on it. From here on,
a mistake in the wrong file is not a walk across the room — it is finding hardware in a drawer and
plugging it back in.

That single fact reshapes what "knowing Linux" means for this project. The most valuable thing in
this phase is not a command. It is the habit of asking *"could this cut me off?"* before pressing
Enter, and having a rehearsed answer when it could.

### What we are not doing

This is not a Linux textbook, and `guide/README.md` explicitly warns against becoming one. The rule
adopted here: **a concept earns a place only if it explains something this project has already done,
or will do by Phase 05.** So there is a lot about systemd units and almost nothing about SELinux;
plenty about `apt` provenance and nothing about compiling from source.

## Reference-build choice

Three decisions shape this phase.

**1. Learn from this machine's own files.** Every example below is a real file on the reference node
— the sshd drop-in from Phase 03, the netplan config from Phase 01, the Wi-Fi power-save unit, the
Tailscale apt source. No `foo.txt`, no `/path/to/file`. The examples are the system you are running.

**2. Classify every exercise by blast radius before writing it.** This is the phase's core method,
and it is what makes hands-on practice safe on a console-less box:

| Tier | Meaning | Examples |
|---|---|---|
| **Tier 1 — Free** | Read-only, or writes confined to a scratch directory | Reading modes, `journalctl`, `df`, `ss`, `apt policy` |
| **Tier 2 — Sandboxed** | Real writes, but only to disposable things | Creating a user, a group, a setgid directory, a systemd unit — all thrown away afterwards |
| **Tier 3 — Read-only this phase** | Studied by reading, not by changing | `sshd`, `netplan`, `sudoers`, PAM, GRUB, fstab |

An exercise that cannot be placed in a tier does not go in the guide.

**3. Tier 3 is a deliberate deferral, not a claim of coverage.** Editing netplan on a machine with
no console, purely to practise, is a bad trade: the learning is modest and the downside is physical.
Phase 13 will have a better safety net. This guide says what it did not teach rather than implying
the topic is done.

## Alternatives

**A structured course (Linux Foundation, "The Linux Command Line", a distro certification).** More
complete, more coherent, and genuinely worth doing. It teaches a generic Linux rather than *this*
machine, so it does not tell you that `who` is broken on Ubuntu 26.04 or that your sshd drop-in
needs a reload. Complement, not substitute.

**Learn on a throwaway VM.** Safer still, and a good idea for anything genuinely destructive. The
cost is that a VM has none of the specifics that bite: no Tailscale, no Wi-Fi-only link, no
console-less constraint, no Phase 01 install decisions.

**Learn reactively, when something breaks.** This is what most people actually do. It works, and it
is a terrible plan on a machine you cannot see, because the first real lesson arrives at the moment
you have the least capacity to absorb it.

**Reattach the monitor for the duration of the phase.** Tempting and legitimate. Rejected because it
would undo Phase 03's outcome for the whole phase, and because designing exercises that are safe
*without* a console produces the standard this project actually needs.

## Prerequisites

- Phase 01 complete: Ubuntu Server on the node.
- Phase 03 complete: `ssh homelab` works with keys; the node is headless.
- A terminal on the MacBook, and this repository checked out.
- Patience with `sudo` asking for a password every time. There is no `NOPASSWD` on this node, and
  that is deliberate.

## Implementation

### Part A — The one rule that matters

Before anything else, read [`docs/standards/safe-changes-headless.md`](../../docs/standards/safe-changes-headless.md)
(adopted as [ADR-020](../../docs/decisions/ADR-020-change-safety-headless.md)). Its shape:

```text
1. Is this lockout-class?  network / sshd / auth / boot / the admin account
2. Second session open, idle.
3. Both routes proved, with BatchMode=yes.
4. Validator run.       sshd -t · netplan try · visudo -c · systemd-analyze verify
5. Rollback typed, unexecuted, in session 2.
6. reload, not restart, where the unit supports it.
7. Verify the running system from the other machine.
8. Third fresh connection + no failed units, then stand down.
```

Step 1 is the control. Steps 2–8 only help once you have noticed that step 1 applies.

From the MacBook, the machine-checkable part runs itself:

```bash
bash scripts/macos/preflight.sh
```

### Part B — Reading the system (Tier 1)

#### Exercise 1: where this project put things

```bash
ls -l /etc/netplan/ /etc/ssh/sshd_config.d/ /etc/apt/sources.list.d/
```

```text
/etc/apt/sources.list.d/:
-rw-r--r-- 1 root root  162 Sep  9 12:36 tailscale.list
-rw-r--r-- 1 root root  395 Sep  8 18:16 ubuntu.sources

/etc/netplan/:
-rw------- 1 root root  276 Sep  8 18:18 00-installer-config.yaml
-rw------- 1 root root 1422 Sep  8 19:12 99-eno1-optional.yaml

/etc/ssh/sshd_config.d/:
-rw------- 1 root root 3017 Sep  9 12:32 10-homelab-hardening.conf
-rw------- 1 root root   27 Sep  8 18:26 50-cloud-init.conf
```

Read the *modes*, not just the names. The apt sources are `644` — world-readable, because which
repositories you use is not a secret. The netplan and sshd files are `600` — because one holds the
Wi-Fi passphrase in cleartext and the other is a security control. **The mode is part of the
configuration.**

Note the date stamps: they are a history of this project. `Sep 8 18:18` is the Phase 01 install;
`Sep 9 12:32` is when Phase 03 hardened sshd.

#### Exercise 2: read a permission line

```bash
stat -c '%A %U:%G %s bytes  %n' /etc/ssh/sshd_config.d/*
```

```text
-rw------- root:root 3017 bytes  /etc/ssh/sshd_config.d/10-homelab-hardening.conf
-rw------- root:root 27 bytes  /etc/ssh/sshd_config.d/50-cloud-init.conf
```

```text
-rw------- 1 root root
│└┬┘└┬┘└┬┘
│ │  │  └── others : nothing
│ │  └───── group  : nothing
│ └──────── owner  : read + write
└────────── type   : - file, d directory, l symlink
```

Now prove the mode does something:

```bash
cat /etc/ssh/sshd_config.d/10-homelab-hardening.conf
```

```text
cat: /etc/ssh/sshd_config.d/10-homelab-hardening.conf: Permission denied
```

You are `aleix`. The file is `root:root` with nothing for group or others. sshd reads it as root, so
`0600` costs nothing and reveals nothing. During Phase 03 this project documented that file as
`0644` on the grounds that "sshd needs it world-readable" — which was simply false, and Ubuntu's own
`50-cloud-init.conf` right next to it proves the point at `0600`.

**Two file sizes worth noticing.** `50-cloud-init.conf` is 27 bytes: exactly
`PasswordAuthentication yes`. sshd takes the **first** value it sees for a keyword and reads
drop-ins in lexical order, so `10-` is read before `50-` and wins. Renaming the hardening file to
`60-` would silently switch password authentication back on. **The number in the filename is a
security control.**

#### Exercise 3: three kinds of "disk full"

```bash
df -h /          # bytes
df -i /          # inodes
```

```text
/dev/mapper/ubuntu--vg-ubuntu--lv  232G  7.8G  214G   4% /
/dev/mapper/ubuntu--vg-ubuntu--lv 15433728 114063 15319665    1% /
```

Bytes and inodes are separate budgets. A filesystem with 200 GB free and no inodes left is full, and
`df -h` will cheerfully tell you it is 4% used. Millions of tiny files — caches, mail spools,
container layers — exhaust inodes first.

The third kind is the one that catches people. Try it (it is Tier 1: your own file, in your own
temporary directory):

```bash
D=$(mktemp -d); cd "$D"
dd if=/dev/zero of=big.bin bs=1M count=200 status=none
du -sh "$D"          # 200M
exec 9<big.bin       # hold the file open
rm big.bin
du -sh "$D"          # 0
ls -l /proc/$$/fd/9
```

```text
200M	/tmp/tmp.V0RKPSpV7A
0	/tmp/tmp.V0RKPSpV7A
lr-x------ 1 aleix aleix 64 Sep  9 13:11 /proc/3113/fd/9 -> /tmp/tmp.V0RKPSpV7A/big.bin (deleted)
```

The file is gone from the directory but the 200 MB is still allocated, because a process still holds
a descriptor to it. `du` walks directory entries and sees nothing; `df` counts blocks and still sees
200 MB. **When `df` and `du` disagree, `df` is right.** Close the descriptor (`exec 9<&-`) or restart
the process and the space returns. This is why "I deleted the huge log file and nothing happened" is
such a common support question — the answer is usually that the daemon still has it open.

#### Exercise 4: query the journal, do not scroll it

```bash
journalctl -u ssh --since "today" | tail -3
```

```text
Sep 09 13:11:04 homelab sshd-session[2947]: Accepted publickey for aleix from 100.69.244.33 port 57786 ssh2: ED25519 SHA256:mAJV6...
```

That one line contains the method (`publickey`), the account, the source address (the MacBook's
Tailscale address) and the key fingerprint. It is the proof that Phase 03's hardening is working in
production, not just in a config file.

```bash
journalctl -b -p err        # errors this boot
journalctl --list-boots     # what it remembers
```

```text
Sep 09 12:49:41 kernel: DMAR: [Firmware Bug]: No firmware reserved region can cover this RMRR ...
Sep 09 12:49:41 kernel: x86/cpu: SGX disabled or unsupported by BIOS.
Sep 09 12:49:49 kernel: Bluetooth: hci0: Reading supported features failed (-16)

 -1 d17673646d9845cd9ab7768c39f81646 Wed 2026-09-09 07:51:32 UTC Wed 2026-09-09 12:49:07 UTC
  0 82e402f22a634c71bbb5203747c86446 Wed 2026-09-09 12:49:41 UTC Wed 2026-09-09 13:11:04 UTC
```

Three errors, all cosmetic: 2016 firmware quirks and a Bluetooth radio nobody uses. Worth
recognising as **the node's normal noise**, so that a fourth error stands out.

`journalctl -b -1` reads the previous boot — which is how you find out why a machine rebooted, after
it has already rebooted. That only works because the journal is persistent on disk (24 MB here);
`--list-boots` proves it.

#### Exercise 5: where a package came from

```bash
dpkg -S "$(readlink -f "$(command -v tailscale)")"
apt policy tailscale
apt policy openssh-server
```

```text
tailscale: /usr/bin/tailscale

tailscale:  1.102.3  500 https://pkgs.tailscale.com/stable/ubuntu resolute/main amd64 Packages
openssh-server:  1:10.2p1-2ubuntu3.6
    500 http://archive.ubuntu.com/ubuntu resolute-updates/main amd64 Packages
    500 http://security.ubuntu.com/ubuntu resolute-security/main amd64 Packages
```

One is Ubuntu's, one is not. Look at how the third party is wired in:

```bash
cat /etc/apt/sources.list.d/tailscale.list
```

```text
deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu resolute main
```

`signed-by=` is the control. Without it, *any* trusted key could sign *any* package from *any*
configured repository — so a compromised third-party key could ship you a replacement
`openssh-server`. With it, Tailscale's key can only vouch for Tailscale's repository. When you add
a third-party apt source, `signed-by=` is not optional detail; it is the whole security model.

`resolute` is Ubuntu 26.04's codename, and it appears in both the Ubuntu and the Tailscale lines.
Phase 03's install script refuses to proceed unless the third-party repository really publishes for
your codename, precisely so an unsupported release becomes an error rather than a silent fallback.

#### Exercise 6: sockets, services, and the Phase 03 trap

```bash
systemctl status ssh.socket | head -8
systemctl show ssh.socket -p Accept
systemctl show ssh.service -p ExecReload -p KillMode
```

```text
● ssh.socket - OpenBSD Secure Shell server socket
     Active: active (running) since Wed 2026-09-09 12:49:48 UTC
     Listen: 0.0.0.0:22 (Stream)

Accept=no

ExecReload={ argv[]=/usr/sbin/sshd -t ... }
ExecReload={ argv[]=/bin/kill -HUP $MAINPID ... }
KillMode=process
```

Read `Accept=no` carefully, because it caused the worst failure of Phase 03.

With `Accept=yes`, systemd would start a fresh process per connection — each one reading the config
afresh. With **`Accept=no`**, systemd hands the listening socket to **one** long-running `sshd -D`,
and every connection is a fork of that daemon, using the configuration it parsed **when it started**.

So editing a config file changes nothing at all until the daemon re-reads it:

```bash
sudo systemctl reload ssh
systemctl show ssh.service -p StateChangeTimestamp
```

`ExecReload` shows exactly what a reload does: validate with `sshd -t` first, and only then send
`SIGHUP`. `KillMode=process` means your existing session is not killed either way. And
`StateChangeTimestamp` is the timestamp that moves on a reload — `ActiveEnterTimestamp` does not,
which is a second bug Phase 03 shipped and had to fix.

#### Exercise 7: read a unit this project wrote

```bash
systemctl cat wifi-powersave-off.service
```

```text
# /etc/systemd/system/wifi-powersave-off.service
[Unit]
Description=Disable Wi-Fi power saving (always-on server)
After=network-online.target
```

Two things to take from it. `/etc/systemd/system/` is where *your* units go; `/usr/lib/systemd/system/`
is where the distribution's live, and you never edit those — you override them. And `After=` is
ordering, not a dependency: it says "not before", not "only if".

#### Exercise 8: the network, read-only

```bash
ip -br address
networkctl list
ss -tlnp | head
```

```text
lo          UNKNOWN  127.0.0.1/8 ::1/128
eno1        DOWN
wlp1s0      UP       192.168.1.57/21 metric 600
tailscale0  UNKNOWN  100.71.62.71/32 fd7a:115c:a1e0::c01:3ed6/128

IDX LINK       TYPE     OPERATIONAL SETUP
  2 eno1       ether    no-carrier  configuring
  3 wlp1s0     wlan     routable    configured
  4 tailscale0 none     routable    unmanaged
```

Four interfaces, and the whole access story is visible:

- `wlp1s0` is the only real link. Both ways in depend on it.
- `tailscale0` is `unmanaged` — networkd does not control it; `tailscaled` does.
- `eno1` is `no-carrier`: the Ethernet port exists with no cable in it. Wiring it would make the two
  access routes genuinely independent, and no phase owns that yet.
- `UNKNOWN` on `lo` and `tailscale0` is normal for virtual interfaces, not a fault.

```text
LISTEN 0.0.0.0:22                    (sshd)
LISTEN 127.0.0.1:44207               code-0958016b2a   ← VS Code Remote SSH
LISTEN 100.71.62.71:36121            tailscaled
LISTEN 127.0.0.53%lo:53              systemd-resolved
```

Only `:22` is reachable from the LAN. Everything else is bound to loopback or the tailnet.
**`ss -tlnp` is the honest answer to "what is exposed"** — a firewall's rules are a claim, this is
what is actually listening.

⚠️ Everything that *changes* networking here is Tier 3 and out of scope for this phase.

### Part C — Tooling

```bash
sudo apt install -y tree ncdu ripgrep
```

Three tools, each earning its place in an exercise rather than as decoration:

- **`tree -L 2 /etc/ssh`** — structure at a glance, where repeated `ls` gets tedious.
- **`ncdu /var`** — interactive drill-down for "where has the disk gone", far faster than `du | sort`.
- **`rg 'PasswordAuthentication' /etc/ssh`** — searches file contents fast, and respects `.gitignore`
  in a repository, which matters from Phase 04 onward.

`fzf` and `bat` were considered and left out: pleasant, but comfort rather than diagnosis, and every
package is surface area on a headless node.

### Part D — Practising the write side, safely (Tier 2)

The exercises so far only read. Creating users, setting ownership and writing units are the things
that actually go wrong — and the things you must not rehearse on `aleix` or on `ssh`.

`scripts/server/lab-sandbox.sh` builds a disposable environment: a user with no password and a
`nologin` shell, a group, a setgid directory under `/srv/lab`, and a systemd unit with **no
`[Install]` section**, so it cannot be enabled and therefore cannot ever affect boot.

```bash
sudo bash /tmp/lab-sandbox.sh setup
sudo bash /tmp/lab-sandbox.sh status
```

Before using it, try to break it. A script that deletes users should be tested by pointing it at
things it must refuse:

```bash
sudo LAB_USER=aleix bash /tmp/lab-sandbox.sh setup
sudo LAB_USER=root bash /tmp/lab-sandbox.sh setup
sudo LAB_USER=daemon bash /tmp/lab-sandbox.sh setup
```

All three must be refused. This is worth doing rather than trusting: `userdel -r` on the wrong name
deletes a home directory, and the guard rails are the only thing standing between a typo and that.

The teardown guard is stricter still. The script writes a marker into the account's comment field
and **refuses to delete any account that does not carry it** — if it did not create the account, it
will not remove it.

#### Exercise 9: setgid, seen rather than described

```bash
ls -ld /srv/lab
sudo touch /srv/lab/made-by-root      # inside the setgid directory
sudo touch /tmp/made-by-root-elsewhere # outside it
ls -l /srv/lab/made-by-root /tmp/made-by-root-elsewhere
```

```text
drwxrws--- 2 labuser labgroup 4096 Sep  9 13:23 /srv/lab
-rw-r--r-- 1 root labgroup 0 Sep  9 13:26 /srv/lab/made-by-root
-rw-r--r-- 1 root root     0 Sep  9 13:26 /tmp/made-by-root-elsewhere
```

The same command, run by the same user, two seconds apart, produced files with **different groups**.
Normally a new file takes the creating user's primary group — root's is `root`. The `s` in
`drwxrws---` changes that: inside a setgid directory, new files inherit the *directory's* group.

That is how a shared working area is made to actually work. Without it, every file a colleague
creates lands in their own private group and nobody else can touch it.

#### Exercise 10: group membership is not ownership

```bash
id labuser
sudo -u labuser touch /srv/lab/made-by-labuser
ls -l /srv/lab/
```

```text
uid=1001(labuser) gid=1001(labgroup) groups=1001(labgroup)

-rw-r--r-- 1 labuser labgroup 0 Sep  9 13:26 made-by-labuser
-rw-r--r-- 1 root    labgroup 0 Sep  9 13:26 made-by-root
```

Two files, two different owners, one shared group. "Who owns it" and "who is in the group" are
separate questions, and permissions are answered by combining them.

#### Exercise 11: `Type=oneshot` — inactive is success

```bash
sudo systemctl start homelab-lab.service
systemctl is-active homelab-lab.service
systemctl status homelab-lab.service | head -8
```

```text
inactive

○ homelab-lab.service - Home Lab Phase 02 practice unit (disposable)
     Loaded: loaded (/etc/systemd/system/homelab-lab.service; static)
     Active: inactive (dead)

Sep 09 13:26:12 homelab systemd[1]: homelab-lab.service: Deactivated successfully.
Sep 09 13:26:12 homelab systemd[1]: Finished homelab-lab.service ...
```

`inactive (dead)` after a successful run looks alarming and is completely normal. A `Type=oneshot`
unit does a job and exits; there is no daemon left behind to be "active". **`inactive` and `failed`
are different states**, and the circle glyph `○` versus a cross `×` tells you which at a glance.

Note `Loaded: … ; static`. That is systemd reporting that the unit has **no `[Install]` section**, so
it cannot be enabled — the safety property this sandbox was designed around, confirmed by the system
rather than by the script's own claim.

#### Exercise 12: break it on purpose, then diagnose it

This is the exercise that transfers to real incidents. Override `ExecStart` with a path that does not
exist — using a drop-in, which is how you modify a unit you do not own:

```bash
sudo mkdir -p /etc/systemd/system/homelab-lab.service.d
# /etc/systemd/system/homelab-lab.service.d/break.conf
[Service]
ExecStart=
ExecStart=/usr/bin/definitely-not-here
```

**The empty `ExecStart=` is not a typo.** `ExecStart` is list-valued, so an assignment *appends*.
Without the empty line resetting the list first, you get both commands, not a replacement. This
catches people constantly.

```bash
sudo systemctl daemon-reload
sudo systemctl start homelab-lab.service
```

```text
Job for homelab-lab.service failed because the control process exited with error code.
```

Now diagnose it **before** looking at what you changed:

```text
× homelab-lab.service - Home Lab Phase 02 practice unit (disposable)
     Loaded: loaded (/etc/systemd/system/homelab-lab.service; static)
    Drop-In: /etc/systemd/system/homelab-lab.service.d
             └─break.conf
     Active: failed (Result: exit-code) since Wed 2026-09-09 13:26:13 UTC
    Process: 5231 ExecStart=/usr/bin/definitely-not-here (code=exited, status=203/EXEC)

homelab-lab.service: Unable to locate executable '/usr/bin/definitely-not-here': No such file or directory
homelab-lab.service: Failed at step EXEC spawning /usr/bin/definitely-not-here: No such file or directory
```

Four things in that output answer the question without you knowing anything in advance:

- `×` and `failed (Result: exit-code)` — it ran and returned failure, rather than never starting.
- **`Drop-In:` names the file that changed the unit.** If someone else had made this change, this
  line is how you would find it.
- **`status=203/EXEC`** is systemd's code for "could not execute the binary". 203 means the file was
  missing or not executable — as opposed to `1` (the program ran and failed) or `226/NAMESPACE`
  (sandboxing directives blocked it). The number tells you which half of the problem you have.
- The journal spells it out in English anyway.

Then fix it and confirm the *system* is clean, not just the unit:

```bash
sudo rm -f /etc/systemd/system/homelab-lab.service.d/break.conf
sudo rmdir /etc/systemd/system/homelab-lab.service.d
sudo systemctl daemon-reload
sudo systemctl reset-failed homelab-lab.service
sudo systemctl start homelab-lab.service
systemctl --failed --no-legend | wc -l     # 0
```

`reset-failed` matters. A failed unit stays on the `systemctl --failed` list after you fix it, until
it either succeeds or you clear it — and Phase 01's whole lesson was that a lingering failed unit is
how a "working" machine hides being degraded.

#### Exercise 13: test the guard that protects you

```bash
sudo usermod -c tampered labuser        # simulate an account we did not create
sudo bash /tmp/lab-sandbox.sh teardown
```

```text
REFUSED: 'labuser' does not carry the sandbox marker — this script did not create it
```

And then the part that actually matters — check that the refusal happened *before* anything was
destroyed:

```text
$ ls -l /etc/systemd/system/homelab-lab.service
-rw-r--r-- 1 root root 410 Sep  9 13:23 /etc/systemd/system/homelab-lab.service
$ ls -ld /srv/lab
drwxrws--- 2 labuser labgroup 4096 Sep  9 13:26 /srv/lab
```

The first version of this script failed that test. It deleted the unit, *then* checked whether the
account was safe to remove — so a refusal left the sandbox half dismantled. **A guard that fires
after the first destructive step is not a guard, it is a report.** The script now validates
everything before it removes anything.

Then restore the marker and remove all of it:

```bash
sudo bash /tmp/lab-sandbox.sh teardown
sudo bash /tmp/lab-sandbox.sh status
```

```text
  ok   unit 'homelab-lab.service' removed
  ok   user 'labuser' removed
  ok   group 'labgroup' removed
  ok   directory '/srv/lab' removed

Phase 02 sandbox status
  user      absent
  group     absent
  directory absent
  unit      absent
```

**Teardown is part of the exercise, not tidying up.** A forgotten practice account is exactly the
kind of thing that survives into production.

### Part E — tmux, and why it is not optional here

```bash
tmux new -s work        # start
# Ctrl-b then d         # detach — the session keeps running on the server
tmux ls                 # list
tmux attach -t work     # reattach, possibly from a different machine
```

Both routes into this node run over one Wi-Fi adapter. A dropped connection in the middle of
`apt full-upgrade` can leave dpkg half-configured on a machine you cannot see. Inside tmux the
process keeps running on the server regardless of your link, and you reattach to it.

**Rule for this project: anything that takes more than a few seconds on the server runs inside tmux.**

## Validation

| # | Check | How |
|---|---|---|
| 1 | Permissions read correctly | `stat -c '%A %U:%G' /etc/ssh/sshd_config.d/*` → `-rw------- root:root` |
| 2 | Mode actually enforces | `cat` the drop-in as `aleix` → `Permission denied` |
| 3 | Disk triage | `df -h /` and `df -i /` differ; deleted-open file shows in `/proc/*/fd` |
| 4 | Journal queries | `-u`, `-b`, `-p err`, `--since` all return output |
| 5 | Package provenance | `apt policy` separates `pkgs.tailscale.com` from `archive.ubuntu.com` |
| 6 | Socket semantics | `systemctl show ssh.socket -p Accept` → `Accept=no` |
| 7 | Tooling | `tree --version`, `ncdu -v`, `rg --version` |
| 8 | Sandbox guards | all three refusal cases refused |
| 9 | Sandbox gone | `getent passwd labuser` empty; no group; no unit; no `/srv/lab` |
| 10 | tmux survives | detach, drop the SSH session, reconnect, `tmux attach` |
| 11 | Preflight | `bash scripts/macos/preflight.sh` |
| 12 | Access unchanged | `ssh -o PreferredAuthentications=none homelab` → `Permission denied (publickey)` |
| 13 | `aleix` unchanged | `id aleix` matches the phase-start record |
| 14 | Health | `systemctl is-system-running` → `running`; `systemctl --failed` empty |

Check 14 is last on purpose. Phase 01 passed every functional test on a machine that was quietly
degraded, and only a literal reading of the checklist caught it.

## Security notes

- **The tier boundaries are the security control**, not a teaching convenience. Tier 3 exists because
  the cost of getting netplan wrong is now measured in physical trips, not seconds.
- **The sandbox user gets nothing**: no password (so password login is impossible, not merely hard),
  a `nologin` shell, no `sudo`, no SSH key, and no home directory outside `/srv/lab`. That is
  [ADR-011](../../docs/decisions/ADR-011-privilege-separation.md) in miniature.
- **The practice unit has no `[Install]` section**, so it cannot be enabled and cannot contribute to
  a boot failure. On a console-less node, "cannot run at boot" is a safety property worth designing in.
- **Never `cat` `/etc/netplan/*` into anything you keep.** Those files hold the Wi-Fi passphrase in
  cleartext ([ADR-016](../../docs/decisions/ADR-016-wifi-reference-link.md)). `ls -l` and `stat` tell
  you what you need. The repository keeps a redacted example instead.
- **Third-party output carries identity.** `tailscale status` prints your account email and tailnet
  name against every node. Phase 03 printed both into a report meant for this repository. Redact
  before pasting, not after.
- **Nothing in this phase opens a port.** `ss -tlnp` at the end matches `ss -tlnp` at the start.

## Reference-build experience

### `who` reports zero sessions on a machine with five

Writing `preflight.sh`, the most important check is "do you have a second session open" — because an
established connection survives a broken `sshd` and a new one may not. The obvious implementation is
`who | wc -l`.

It returned **0**. Not an error — zero sessions, exit status 0, on a machine that was at that moment
carrying six:

```text
$ who
$ echo $?
0

$ w
 13:14:32 up 24 min,  6 users,  load average: 0.00, 0.00, 0.01
USER     TTY      FROM             LOGIN@   IDLE   WHAT
aleix    pts/4    100.69.244.33    13:14    3.00s  sleep 40
aleix    pts/1    100.69.244.33    12:51   23:12   -bash
...

$ ls -l /run/utmp
ls: cannot access '/run/utmp': No such file or directory
$ systemctl --version | head -1
systemd 259 (259.5-0ubuntu3.4)
```

`who` reads `/run/utmp`. **systemd 257 removed utmp support**, and Ubuntu 26.04 ships systemd 259, so
the file does not exist. `who` finds nothing to read and reports nothing — successfully.

`w` still works, because procps falls back to logind, and its `pts/N` column distinguishes real
interactive sessions from non-TTY command invocations:

```bash
w -h | awk '$2 ~ /^pts\//' | wc -l
```

Two lessons, and the second is the bigger one:

1. Long-stable commands do change. `who` has behaved the same way since the 1970s and it is wrong here.
2. **A tool that fails by returning "nothing" is more dangerous than one that errors.** This check
   would have reported "no sessions open" and been believed. The script now reports *unknown* rather
   than *zero* when it cannot tell — being wrong is bad, being confidently wrong is worse.

That is the same failure shape as Phase 03's `sshd -T`: a check that answered a question adjacent to
the one being asked, and agreed with us.

### The teardown guard fired after the first destructive step

`lab-sandbox.sh teardown` removed the systemd unit first — on the sound reasoning that you should
never delete a user while a service is still running as them — and *then* checked whether the account
was safe to touch. So pointing it at an account it did not create produced a refusal with the unit
already gone.

Found by reading the code path before running the guard test, not by the test itself. Fixed by
validating everything up front and recording what may be removed, then acting. The exercise above now
checks the unit and directory are still present *after* the refusal, which is what makes it a test of
the fix rather than a restatement of it.

**A guard that fires after the first destructive step is not a guard, it is a report.**

### The brief named a file that does not exist

The brief said netplan configuration lives in `/etc/netplan/50-wifi.yaml`. It does not — the real
files are `00-installer-config.yaml` and `99-eno1-optional.yaml`. `50-wifi.example.yaml` is the name
of the **redacted example in this repository**, and writing the brief from the repository rather
than from the machine turned a repo filename into an imagined server filename.

Small, harmless, and exactly how documentation drifts. Corrected here rather than silently.

### `preflight.sh` was specified for the wrong machine

The brief placed it in `scripts/server/`. Writing it made the error obvious: the check that matters
is *can a new connection actually arrive*, and a script running on the server is inside the thing it
is meant to be testing. It moved to `scripts/macos/`, proves both routes from outside the way a real
user arrives, and gathers host state over SSH in one round trip.

### `systemd-analyze verify` reports other people's problems

```text
$ systemd-analyze verify ssh.service
/usr/lib/systemd/system/xfs_scrub_all.service:26: Support for option CPUAccounting= has been removed
```

Nothing to do with `ssh`. `verify` walks the unit's whole dependency closure, so it surfaces
deprecation warnings from unrelated units. Read the filename on each line before assuming a warning
is yours — otherwise a clean unit looks broken.

### The volume group has no room to grow

The textbook LVM exercise is `lvextend` then `resize2fs`. It cannot be done here:

```text
└─sda3                    235.4G part LVM2_member
  └─ubuntu--vg-ubuntu--lv 235.4G lvm  ext4  /
```

The logical volume already consumes the entire volume group. Phase 01 chose to use the whole disk,
which is reasonable for a single-purpose node and removes the main benefit people install LVM for.
Growing storage here means adding a disk. Recorded as a limitation rather than worked around —
shrinking a mounted root filesystem to create practice space is precisely the class of operation a
console-less machine should never attempt.

### Everything needing `sudo` had to be handed over

There is no `NOPASSWD` on this node, so every privileged step in this phase was executed by the
owner rather than automated. This is the second phase where that has shaped the work, and it is
worth stating plainly for later phases: **automation on this node stops at the `sudo` boundary.**

## Tested versions

| Component | Version |
|---|---|
| Ubuntu Server | 26.04.1 LTS (`resolute`) |
| Kernel | 7.0.0-31-generic |
| systemd | 259 (259.5-0ubuntu3.4) |
| bash | 5.3.9(1)-release |
| tmux | 3.6 |
| OpenSSH server | 10.2p1 Ubuntu-2ubuntu3.6 |
| lsof | 4.99.4 |
| tree | 2.3.1-1 |
| ncdu | 1.22-1build1 |
| ripgrep | 15.1.0-1ubuntu1 |

`Requires`: nothing here is version-critical **except** the `who`/utmp behaviour, which needs
systemd ≥ 257 to reproduce. On an older release `who` works normally.

## Next phase

[Phase 04 — Git & GitHub Fundamentals](../../ROADMAP.md). Low risk by comparison: it changes the
repository rather than the node. The handover records what this phase did **not** teach, so Phase 04
does not assume it — no networking changes were practised, no `sudoers` editing, no firewalling, no
backup or restore, and no LVM growth.
