# Making Changes on a Machine With No Console

**Status:** Standard. Adopted by Phase 02, recorded as [ADR-020](../decisions/ADR-020-change-safety-headless.md).
**Applies to:** every phase from 02 onward, and to any change made to the reference node outside a phase.

The reference node has no monitor, no keyboard, and no attached console. All six DRM connectors
report `disconnected`. Phase 01 and Phase 03 both treated the console as the ultimate fallback and
deliberately sequenced their riskiest steps around it being available. **That fallback no longer
exists.**

Recovery from a lockout now means finding a monitor, a keyboard and a DisplayPort→HDMI cable, all of
which are in a drawer, and physically reattaching them. It is perfectly possible. It is just no
longer free, and no longer instant — which is exactly the change that makes a written standard worth
having.

## 1. Classify the change before typing it

A change is **lockout-class** if it touches any of:

| Area | Examples |
|---|---|
| Network | `netplan`, `systemd-networkd`, `wpa_supplicant`, Wi-Fi credentials, interface renaming |
| Remote access | `sshd`, `ssh.socket`, Tailscale, `authorized_keys`, host keys |
| Authentication | `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/etc/sudoers.d/`, PAM, the `sudo` group |
| Boot | GRUB, `/etc/fstab`, initramfs, kernel packages, anything `WantedBy=multi-user.target` |
| The admin account | `aleix` — its shell, home directory, groups, or UID |

Everything else is ordinary work. Everything in the table gets the rest of this document.

The classification matters more than the checklist. Most lockouts are not caused by someone skipping
a safety step; they are caused by not noticing that a safety step applied.

## 2. Two sessions, always

Open a second SSH session before starting, and leave it idle:

```bash
ssh homelab        # session 1 — do the work here
ssh homelab        # session 2 — touch nothing
```

An **established** SSH connection survives `sshd` being reloaded, restarted, or misconfigured. A
**new** connection may not. If session 1 breaks the daemon, session 2 is still logged in and can
undo it. Close session 2 only after a *third*, freshly opened connection has proved that new logins
still work.

This single habit would have made every risky step in Phases 01 and 03 recoverable without a monitor.

**Do not use `who` to check.** On Ubuntu 26.04 (systemd 259) `/run/utmp` does not exist — systemd 257
removed utmp support — so `who` prints nothing and **exits 0**. It reports no sessions on a machine
with five. Use `w`, which falls back to logind:

```bash
w -h | awk '$2 ~ /^pts\//' | wc -l     # interactive sessions only
```

A silent wrong answer is worse than an error, and this one is aimed squarely at the check that
matters most in this document.

## 3. Prove both routes before, not after

There are two ways in, and they are independent above the Wi-Fi link:

```bash
ssh -o BatchMode=yes homelab      true && echo "tailscale route ok"
ssh -o BatchMode=yes homelab-lan  true && echo "lan route ok"
```

`BatchMode=yes` forbids any interactive fallback, so a success is proof rather than encouragement.

Check them **before** the change. Discovering that the LAN fallback was already broken, at the moment
you need it, is the worst possible time to find out.

Both routes run over the same Wi-Fi adapter. **Losing Wi-Fi loses both.** `eno1` exists and is
unused; wiring it would make the two routes genuinely independent, and no phase owns that yet.

## 4. Validate before applying

Almost every configuration format on this machine ships with a validator. Using one costs seconds.

| Change | Validator | Notes |
|---|---|---|
| `sshd` config | `sudo sshd -t` | Silence means valid. It checks syntax, **not** whether you are about to lock yourself out |
| netplan | `sudo netplan try` | Applies the change and **automatically reverts after 120 s** unless you confirm. The best safety net on the machine |
| systemd unit | `systemd-analyze verify ./unit.service` | Catches typos and missing dependencies before `daemon-reload` |
| sudoers | `sudo visudo -c -f file` | Never edit a sudoers file with a plain editor. `visudo` refuses to save a file that would lock out `sudo` |
| fstab | `sudo findmnt --verify` | A bad fstab entry can stop the boot |

A validator that exists and is skipped is a self-inflicted wound.

Note the limit of all of them: they check that the file is *well-formed*, not that it is *correct*.
`sshd -t` is perfectly happy with a syntactically valid configuration that refuses your key.

## 5. Prefer `reload` to `restart` — and know why it matters

`restart` stops the service and starts it again; anything depending on it goes away in between.
`reload` asks the running process to re-read its configuration without dropping what it is doing.
For `ssh`, `KillMode=process` means existing sessions survive either way, but `reload` is still the
smaller blast radius.

More importantly, **`reload` is what turns a configuration file into a control.** Phase 03 wrote a
correct key-only SSH configuration and the server carried on accepting passwords for hours, because
Ubuntu's `ssh.socket` uses `Accept=no`: one long-running daemon serves every connection using the
configuration it parsed when it started. The file was right. The running system was not.

```bash
sudo systemctl reload ssh              # apply
systemctl show ssh.service -p StateChangeTimestamp   # prove it happened
```

`ActiveEnterTimestamp` does not move on a reload. `StateChangeTimestamp` does.

## 6. Type the rollback before the change

In session 2, type the command that undoes the change — and do not press Enter. Restoring a backup
under time pressure, from memory, over a link you may have just damaged, is not a plan.

```bash
# session 2, unexecuted:
sudo cp /etc/ssh/sshd_config.d/10-homelab-hardening.conf.bak \
        /etc/ssh/sshd_config.d/10-homelab-hardening.conf && sudo systemctl reload ssh
```

If you cannot write the rollback, you do not yet understand the change well enough to make it.

## 7. Verify the running system, not the file you wrote

This is the lesson Phase 03 paid for.

```bash
# What the file says sshd would do if it read it now:
sudo sshd -T | grep -i passwordauth        # → passwordauthentication no

# What the running server actually offers:
ssh -o PreferredAuthentications=none homelab
# → Permission denied (publickey)        ← the real answer
```

`sshd -T` re-parses the configuration files on the spot. It answers "what would sshd conclude if it
read these files now", which is a different question from "what is the server doing". During the
Phase 03 failure the first answered `no` while the second still offered `publickey,password`.

Ask the running system. Where possible, ask it **from the other machine**, over the network, the way
a real user arrives.

## 8. After the change

1. Open a **third** SSH connection from scratch. Do not reuse an existing one.
2. Re-run the route checks from §3.
3. `systemctl is-system-running` → `running`, and `systemctl --failed` → no units.
4. Only then close session 2.

Step 3 is not optional. Phase 01 produced a machine that passed every functional test — installed,
reachable, surviving a power cut — while a boot unit failed and every startup wasted two minutes.
Functional success does not imply a healthy system.

## 9. The one-screen version

```text
1. Is this lockout-class?  network / sshd / auth / boot / the admin account
2. Second session open, idle.
3. Both routes proved, with BatchMode=yes.
4. Validator run.            sshd -t · netplan try · visudo -c · systemd-analyze verify
5. Rollback typed, unexecuted, in session 2.
6. reload, not restart, where the unit supports it.
7. Verify the running system from the other machine.
8. Third fresh connection + no failed units, then stand down.
```

`scripts/macos/preflight.sh` checks the parts of this that a machine can check. It runs on the
MacBook rather than on the server, because §7's question — *can a new connection actually arrive* —
cannot be answered from inside the machine being tested.

## 10. What this standard does not do

It does not make lockout-class changes safe. It makes them **recoverable**, and it makes the moment
of maximum risk a deliberate one rather than an accident. Some changes are still best deferred until
there is a better safety net — Phase 02 deferred all of Tier 3 for exactly that reason, and said so
rather than pretending the topic was covered.
