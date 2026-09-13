# Phase 13.1 — S2 runbook (the node)

**The last runbook run by paste.** Every step is **OWNER** except row 12, which the executor runs
itself at the end over `ssh homelab-agent`. Every OWNER block prints what it is about to do before
it waits; the only prompt anywhere is a `sudo` password prompt you can see; `sudo -v` comes first.

Terminals on the MacBook:

- **T** — a MacBook-local terminal in `/Users/home/Code/homelab-p131`.
- **S1** — the working session (`ssh homelab`).
- **S2** — opened before step 1, **holding a root shell** (`sudo -i`), touched only to type the
  rollback, closed only at the end of step 3 after a third fresh connection has proved logins work.

Why S2 holds a root shell and not just an idle login: this phase lands a file under
`/etc/sudoers.d/`. A parse error in any file there disables `sudo` for **every** account, `aleix`
included — and then `sudo rm` cannot undo it. An already-open root shell can. The installer runs
`visudo -c -f` before the file lands; S2 is what the standard requires anyway (§1 "Authentication").

| Step | Needs S2? | Lockout class (`safe-changes-headless.md` §1) |
|---|---|---|
| 0 preflight, key, alias, scp | no | — |
| 1 `install` (account + sudoers) | **yes, root shell** | authentication (`/etc/sudoers.d/`) |
| 2 sshd `AllowUsers` | **yes** | remote access |
| 3 verify + rows | no (S2 closes after 3a) | — |
| 4 backup + verify | no | — |
| 5 closing check | no | — |
| 6 row 12 | no | — the executor's turn |

## 0 — Preflight, key, alias, files (T)

```bash
# T
echo "== preflight: routes, sshd validator, failed units (a FAIL on homelab-lan alone is ufw working) =="
bash scripts/macos/preflight.sh --check sshd

echo "== the agent's key: passphrase-less on purpose (an agent cannot type one); 0600; never in a backup =="
[ -f ~/.ssh/id_ed25519_homelab_agent ] && echo "exists — not regenerating" || \
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homelab_agent -N '' -C 'homelab-agent (ADR-049)'
ls -l ~/.ssh/id_ed25519_homelab_agent*
grep -q 'PRIVATE' ~/.ssh/id_ed25519_homelab_agent.pub && echo "WRONG FILE" || echo "public half ok"

echo "== the alias: append Host homelab-agent from the example, then fix HostName =="
grep -q '^Host homelab-agent' ~/.ssh/config && echo "alias exists" || \
  sed -n '/^# The executor agent.s door/,$p' config/ssh/homelab.ssh-config.example >> ~/.ssh/config
HN=$(ssh -G homelab | awk '/^hostname /{print $2}'); echo "using $HN"
sed -i '' "s/homelab\.CHANGE-ME\.ts\.net/$HN/" ~/.ssh/config
grep -c 'CHANGE-ME' ~/.ssh/config
ssh -G homelab-agent | grep -E '^(user|identityfile|batchmode|connecttimeout|requesttty) '

echo "== copy every S2 file to the node in one go (PUBLIC key only) =="
ssh homelab 'mkdir -p /tmp/p131'
scp ~/.ssh/id_ed25519_homelab_agent.pub \
    scripts/server/install-homelab-agent.sh \
    config/sudoers.d/homelab-agent \
    config/ssh/10-homelab-hardening.conf \
    scripts/server/apply-ssh-hardening.sh \
    homelab:/tmp/p131/
ssh homelab 'ls -l /tmp/p131; grep -c PRIVATE /tmp/p131/*.pub'
```

Expected: preflight ok except the LAN route; one key pair, `-rw-------` on the private half; the
`CHANGE-ME` count `0` (OBSERVED: the first run skipped this and row 1 failed on the MacBook with
*Could not resolve hostname homelab.change-me.ts.net* — nothing to do with the node); `ssh -G` shows
`user homelab-agent`, `batchmode yes`, `connecttimeout 10`, `requesttty false`; five files in
`/tmp/p131`; the last line `0`. No trailing `# comments` in any pasted block: zsh runs them as
arguments (15.1's lesson, met again here).

## 1 — Install the account and the grant (S1, with S2 holding a root shell)

> **First attempt, 2026-09-13 — OBSERVED:** the node's `visudo` refused the first draft of the
> grant, *"wildcards are not allowed in command arguments"*, at the installer's pre-landing check;
> nothing was installed, no account was created, `aleix`'s `sudo` was untouched. sudo-rs matches
> arguments exactly. The grant was rewritten as an explicit list (172 entries) and re-`scp`'d;
> the block below is the second attempt. Re-copy first: `scp config/sudoers.d/homelab-agent
> scripts/server/install-homelab-agent.sh homelab:/tmp/p131/` from T.

In S2 — open it now, become root, and type the rollback WITHOUT pressing Enter:

```bash
ssh homelab
sudo -i
```
```text
rm -f /etc/sudoers.d/homelab-agent && visudo -c
```

```bash
# S1
echo "== sudo once, up front =="
sudo -v
echo "== install: visudo -c -f first; account; authorized_keys; sudoers 0440; then verify =="
sudo bash /tmp/p131/install-homelab-agent.sh install /tmp/p131/id_ed25519_homelab_agent.pub 2>&1 | tee /tmp/p131/install.log
echo "== sudo still works for aleix (the thing the root shell in S2 exists for) =="
sudo -n true && echo "aleix sudo ok"
```

Expected: `ok public key: 256 SHA256:… (ED25519)`; `visudo -c -f accepted`; `created homelab-agent:
uid=… gid=… groups=homelab-agent`; `installed /etc/sudoers.d/homelab-agent (root:root 0440)`; then
the verify block. **In the verify block, every ALLOW should be `ok` and every DENY `ok`**, except
that `AllowUsers does NOT yet name homelab-agent` is expected at this point. Paste the whole log.
If anything says `FAIL`, stop here: the rollback in S2 is one keypress, and nothing else has changed.

Row 3 (`sudo -n visudo -c -f /etc/sudoers.d/homelab-agent` → parsed OK) and row 4 (`sudo -l -U
homelab-agent`, verbatim into the guide) are in this log.

## 2 — sshd `AllowUsers` (S1, S2 idle; the one remote-access change)

In S2, replace the typed rollback with this one, still unexecuted:

```text
cp -p /root/10-homelab-hardening.conf.bak-13.1 /etc/ssh/sshd_config.d/10-homelab-hardening.conf && sshd -t && systemctl reload ssh
```

```bash
# S1
sudo -v
echo "== keep the current drop-in outside sshd's include glob =="
sudo cp -p /etc/ssh/sshd_config.d/10-homelab-hardening.conf /root/10-homelab-hardening.conf.bak-13.1
echo "== the only line that changes =="
sudo diff /root/10-homelab-hardening.conf.bak-13.1 /tmp/p131/10-homelab-hardening.conf; true
echo "== apply: sshd -t, install 0600, reload (never restart) =="
sudo bash /tmp/p131/apply-ssh-hardening.sh /tmp/p131/10-homelab-hardening.conf
echo "== what sshd resolved =="
sudo sshd -T | grep -E '^allowusers'
systemctl show ssh.service -p StateChangeTimestamp
```

Expected: the diff shows only the `AllowUsers` comment block and `AllowUsers aleix homelab-agent`;
`sshd -t accepted`; `sshd -T` prints **one line per name** — `allowusers aleix` then
`allowusers homelab-agent` (OBSERVED; not the single line the brief's row 13 wrote);
`StateChangeTimestamp` is now. The apply script also leaves a `.bak.<timestamp>` inside
`sshd_config.d/` — harmless (sshd includes `*.conf` only); the `/root` copy is the rollback.

```bash
# T — the running system, from the other machine, the way a real user arrives
echo "== row 2: the owner still gets in (fresh connection) =="
ssh -o BatchMode=yes homelab true && echo "owner ok"
echo "== row 1: the agent gets in, and is nobody else =="
ssh homelab-agent id
echo "== row 2 again, WHILE an agent session is open =="
ssh homelab-agent 'sleep 20' & sleep 2; ssh -o BatchMode=yes homelab true && echo "owner ok with agent session open"; wait
echo "== row 13 =="
ssh homelab 'sudo -n grep -c "^AllowUsers.*homelab-agent" /etc/ssh/sshd_config.d/10-homelab-hardening.conf || echo "(0600 root: run it in S1 with sudo)"'
echo "== a THIRD fresh connection, then S2 may close =="
ssh homelab 'echo third connection ok'
```

Expected: `owner ok`; `uid=… gid=… groups=homelab-agent` and nothing more; `owner ok with agent
session open`; `1` (and S1 printed `allowusers aleix homelab-agent`); `third connection ok`. **Only now** exit the root shell in S2 and
close it. If `ssh homelab-agent id` says `Permission denied (publickey)`: check the node's journal
(`sudo journalctl -u ssh -n 20`) for `User homelab-agent not allowed because…` — the contingency is
`sudo usermod -p '*' homelab-agent` (the installer already sets `*`, so this should not occur).

## 3 — The rows, as the owner (S1) and from T

`install` already ran `verify`; run it once more now that the account can log in, so the log has
the `AllowUsers` line as `ok`:

```bash
# S1
sudo -v
sudo bash /tmp/p131/install-homelab-agent.sh verify 2>&1 | tee /tmp/p131/verify.log
```

Every row's evidence and where it is:

| Row | Evidence | Note |
|---|---|---|
| 1, 2, 13 | step 2, T | |
| 3, 4 | `verify.log`: `visudo -c -f accepts it`; the `sudo -l` block | paste row 4 verbatim into the guide |
| 5 | `ALLOW systemctl restart homelab-harness.service`, `is-active homelab-harness.service`; then `sudo journalctl _COMM=sudo --no-pager \| grep 'homelab-agent :' \| tail -4` shows the restart under `homelab-agent` (`-n 5` alone shows your own `sudo` lines — OBSERVED) | |
| 6 | `ALLOW journalctl`, `ss -tlnp`, `systemd-analyze security` | eight listeners; 1.3 |
| 7 | `ALLOW install model-helper-config.json from /tmp/homelab-agent` + `byte-identical … still root:root:644`; `DENY install to gateway-key` | **644, not 600** — the helper runs as `aleix` and the harness as `homelab-harness`; a 600 root:root config blinds both. ADR §2 is amended at acceptance |
| 8 | `DENY cat gateway-key`, `DENY cat token.cred` | output discarded by the script on purpose |
| 9 | `DENY sshd -t`, `ufw status`, `tailscale status`, `visudo -c`, `apt update`; `DENY reboot`, `usermod -aG sudo`, `data-volume.sh lock` **(sudo -l, not executed)** | a broken deny on `reboot` must not be discovered by rebooting |
| 10 | `ALLOW data-volume.sh status` | |
| 11 | `ALLOW cp -p spend.json spend.json.bak`, `mv spend.json.bak spend.json`, `ledger copy kept owner/mode aleix:aleix:…`; `DENY cp spend.json to /tmp` | **`cp -p`, not `cp`** — root's `cp` would leave the ledger root-owned and the helper unable to write it (the 15.1 S3 defect) |
| — | the four exact-match probes (`cat config.json /etc/hostname`, `cat via ..`, two units, a unit without its suffix), all `DENY … ok` | sudo-rs matches arguments exactly; learning objective 3.1 in its sudo-rs form |

If any line is `UNKNOWN`, it is not a result: paste it and stop. In particular, if the three
`sudo -l` probes say `unsupported`, sudo-rs on this node does not list a single command; the
fallback is the owner's judgement, not an attempt.

## 4 — Backup and verify (T)

T, the card mounted; two prompts (node sudo, age passphrase), as always; `tee`, never `tail`.
If a backup was already taken today, **rename it first** (never `--force`: a same-day backup is
never overwritten), and give the verifier the directory **by path** — its "newest" is
`sort | tail -1`, and `2026-09-13-anything` sorts after `2026-09-13`, so it would verify the
wrong one (OBSERVED: it picked `2026-09-13-p13-p150` and reported 14 "mismatches" that were just
the node having moved on).

```bash
ls "/Volumes/SD Card/homelab-backup/"
mv "/Volumes/SD Card/homelab-backup/$(date +%F)" "/Volumes/SD Card/homelab-backup/$(date +%F)-earlier"
bash scripts/macos/backup-node.sh 2>&1 | tee /tmp/p131-backup.log
bash scripts/macos/verify-node-backup.sh "/Volumes/SD Card/homelab-backup/$(date +%F)" 2>&1 | tee /tmp/p131-verify.log
grep -E 'sudoers.d/homelab-agent|homelab-agent/.ssh|id_ed25519_homelab_agent|PASS|FAIL' /tmp/p131-verify.log
```

Expected (row 14): both new paths `ok`; `absent as required: home/homelab-agent/.ssh/id_ed25519_homelab_agent`;
`PASS`; the planted control fires.

## 5 — Closing check (S1)

```bash
# S1
echo "== row 15: nothing failed, nothing changed that should not have =="
systemctl --failed --no-legend; systemctl is-system-running
sudo -v; sudo ss -tlnp | tail -n +2 | wc -l
id homelab-bot; id homelab-harness; id aleix; id homelab-agent
echo "== row 16: ADR-046 checks 1-2 (nothing on root can open the volume) =="
sudo cryptsetup luksDump /dev/ubuntu-vg/data | grep -A3 -E '^Keyslots|^Tokens'
grep -rl 'key-file\|keyfile' /etc/crypttab /etc/systemd/system /usr/local/sbin > /tmp/p131/kf.txt
xargs -r grep -n 'key-file\|keyfile' < /tmp/p131/kf.txt
```

(Short lines on purpose: the one-line form wrapped in the paste and zsh ran the tail of the regex
as a command. Whatever the last grep prints must be comment lines only.)

Expected: empty; `running`; `8`; the three service ids byte-identical to Phase 13's close;
`homelab-agent` in its own group only; passphrase keyslots only, `Tokens:` empty; the grep prints
nothing (the watchdog's comment line is filtered).

## 6 — Row 12: the executor's turn

OWNER: say "your turn". Then the executor, from its own session on the MacBook, runs — and reads,
and reports OBSERVED in its own words with the raw output:

```bash
ssh homelab-agent 'sudo -n systemctl restart homelab-harness.service && sudo -n systemctl is-active homelab-harness.service'
ssh homelab-agent 'sudo -n journalctl -u homelab-harness -n 3 --no-pager; sudo -n ss -tlnp | tail -n +2 | wc -l; sudo -n systemd-analyze security homelab-harness.service --no-pager | tail -1'
ssh homelab-agent 'sudo -n /usr/local/sbin/data-volume.sh status'
ssh homelab-agent 'sudo -n cat /etc/homelab-model-helper/gateway-key >/dev/null; echo "rc=$?"; id'
```

The last line is the control: stdout dropped so a broken deny cannot print the key; the refusal
arrives on stderr; `id` says who asked. **OBSERVED 2026-09-13 17:03 UTC**, by the executor:
`active`; `Stopped` → `Started` → `listening on 127.0.0.1:8766`; `8`; `1.3 OK`; mapper present,
mounted, target active; `sudo: I'm sorry homelab-agent. I'm afraid I can't do that`, `rc=1`,
`uid=994(homelab-agent) gid=979(homelab-agent) groups=979(homelab-agent)`.

That last line is the positive control for the whole phase: the agent asks for the one thing it
must never get, and is refused, in its own session, with no owner in the loop.

## Rollback (any point)

```bash
# S2 root shell, or S1 with a password
bash /tmp/p131/install-homelab-agent.sh uninstall     # sudoers first, then the account
cp -p /root/10-homelab-hardening.conf.bak-13.1 /etc/ssh/sshd_config.d/10-homelab-hardening.conf && sshd -t && systemctl reload ssh
```

Then on the MacBook: delete the alias block and `~/.ssh/id_ed25519_homelab_agent*`. Nothing else
changed.
