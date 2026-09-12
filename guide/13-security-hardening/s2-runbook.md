# Phase 13 — S2 runbook (software controls)

One owner session, in this order. **Every step prints what it is about to do before it waits for
anything; no silent pause.** The only prompt anywhere is a `sudo` password prompt you can see.

Terminals on the MacBook:

- **S1** — the working session (`ssh homelab`).
- **S2** — idle, opened before step 1 and closed only at the end, after step 9 (`ssh homelab`).
- **T** — a MacBook-local terminal in `/Users/home/Code/homelab-p13` for `scp`, fresh-connection
  tests and the two-alias test.

"Fresh connection" always means a *new* `ssh` process, never a reused one.

| Step | Needs S2 idle? | Lockout class (standard §1) |
|---|---|---|
| 1 sshd | **yes** | remote access |
| 2 DOCKER-USER | **yes** | network (FORWARD only; INPUT untouched) |
| 3 TMOUT | yes (cheap) | authentication-adjacent; console only |
| 4a helper unit | no | ordinary |
| 4b wifi unit | **yes** | boot + the only network path |
| 4c lxd | yes | the admin account |
| 5 second key | **yes** | authorized_keys |
| 6 GitHub key | no | nothing changes on the node |
| 7 Tailscale ACL | **yes** | remote access, applied from outside |

## 0 — Preflight (T, S1, S2)

```bash
# T — the machine-checkable half of the standard; expect every line ok except homelab-lan,
# which has been closed by ufw since 2026-09-10 (that failure is the control working).
echo "== preflight: routes, sshd validator, failed units =="
bash scripts/macos/preflight.sh --check sshd    # a FAIL on the LAN route alone is expected

echo "== copy every S2 file to the node in one go =="
ssh homelab 'mkdir -p /tmp/p13'
scp scripts/server/apply-ssh-hardening.sh scripts/server/apply-docker-user-rules.sh \
    scripts/server/p13-s2.sh scripts/server/install-model-helper.sh \
    config/ssh/10-homelab-hardening.conf \
    config/profile.d/homelab-console-timeout.sh \
    config/systemd/homelab-model-helper@.service config/systemd/wifi-powersave-off.service \
    homelab:/tmp/p13/
```

```bash
# S2 — open it now and leave it. Type the sshd rollback here and DO NOT press Enter:
sudo cp /etc/ssh/sshd_config.d/10-homelab-hardening.conf.bak-$(date +%F) \
        /etc/ssh/sshd_config.d/10-homelab-hardening.conf && sudo systemctl reload ssh
```

```bash
# S1 — two interactive sessions must show (S1 and S2); ADR-046's "who" trap: use w.
echo "== sessions (expect 2) =="; w -h | awk '$2 ~ /^pts\//' | wc -l
echo "== baseline: nothing failed =="; systemctl --failed; systemctl is-system-running
```

## 1 — sshd (§6.9): `AllowUsers aleix`, `MaxAuthTries 3`, `X11Forwarding no`, `AllowAgentForwarding no`

```bash
# S1
echo "== keep a dated copy of the current drop-in (the apply script deletes its own backup on success) =="
sudo cp -p /etc/ssh/sshd_config.d/10-homelab-hardening.conf \
           /etc/ssh/sshd_config.d/10-homelab-hardening.conf.bak-$(date +%F)
echo "== apply: installs the new drop-in, sshd -t, reload (established sessions survive) =="
sudo bash /tmp/p13/apply-ssh-hardening.sh /tmp/p13/10-homelab-hardening.conf
echo "== row 3: expect no / no / aleix / 3 / no =="
sudo sshd -T | grep -iE '^(passwordauthentication|permitrootlogin|allowusers|maxauthtries|kbdinteractiveauthentication|x11forwarding|allowagentforwarding) '
echo "== reload actually happened: StateChangeTimestamp is now, ActiveEnter is boot time =="
systemctl show ssh.service -p ActiveEnterTimestamp,StateChangeTimestamp
```

```bash
# T — the running server, from outside, as a real user arrives (standard §7)
echo "== fresh key login =="; ssh -o BatchMode=yes homelab true; echo "rc=$?"
echo "== server offers publickey only =="; ssh -o PreferredAuthentications=none homelab true 2>&1 | tail -1
echo "== row 4: forward-free alias while the tunnel alias is open =="
ssh -o BatchMode=yes -N homelab-workbench & TUN=$!; sleep 3
ssh -o BatchMode=yes homelab true; echo "rc=$?"
curl -m 5 -s -o /dev/null -w 'workbench via tunnel: HTTP %{http_code}\n' http://127.0.0.1:8765/
kill $TUN
```

Rollback: the line typed in S2. Do not continue until `rc=0` twice and `HTTP 200`.

## 2 — DOCKER-USER (§6.4), self-revert armed

```bash
# S1
echo "== apply: after.rules + after6.rules gain a DOCKER-USER block; 10-minute self-revert armed; ufw reload =="
sudo bash /tmp/p13/apply-docker-user-rules.sh
```

```bash
# T — row 6 + fresh connection
echo "== fresh connection after ufw reload =="; ssh -o BatchMode=yes homelab true; echo "rc=$?"
ssh homelab 'sudo iptables -S DOCKER-USER; sudo ip6tables -S FORWARD | head -1'
```

**2b — optional real proof** (pulls `python:3-alpine`, ~50 MB, removed afterwards; without it the
negative half of row 6 is PREDICTED):

```bash
# S1
echo "== publish a throwaway container on 0.0.0.0:8080 for 5 minutes =="
docker run --rm -d --name p13probe -p 8080:80 python:3-alpine python3 -m http.server 80
```
```bash
# T — the MacBook is on the same LAN (192.168.1.112) AND on the tailnet
echo "== LAN path: expect timeout/refused (DOCKER-USER drops wlp1s0) =="; nc -zv -w3 192.168.1.57 8080
echo "== tailnet path: expect succeeded (RETURN on tailscale0) =="; nc -zv -w3 100.71.62.71 8080
```
```bash
# S1 — cleanup; inventory back to zero (row 16)
echo "== remove the probe container and image =="
docker rm -f p13probe; docker rmi python:3-alpine; docker system df
```

```bash
# S1 — only after the fresh connection worked
echo "== keep: cancel the self-revert =="
sudo bash /tmp/p13/apply-docker-user-rules.sh --keep
```

Rollback: `sudo bash /tmp/p13/apply-docker-user-rules.sh --undo` (or wait 10 minutes).

## 3 — Console timeout (§6.5, TMOUT half)

```bash
# S1
echo "== install /etc/profile.d/homelab-console-timeout.sh (tty-only); prints TMOUT=unset for this pts =="
sudo bash /tmp/p13/p13-s2.sh tmout
echo "== fresh SSH login is not affected either =="
```
```bash
# T
ssh homelab 'bash -lc "echo TMOUT=\${TMOUT:-unset}"'      # expect TMOUT=unset
```

Row 9's positive half (tty login ends after 900 s) is proved at the box in S3. Rollback:
`sudo bash /tmp/p13/p13-s2.sh tmout --undo`.

## 4a — Model helper unit (§6.12)

```bash
# S1
echo "== install hardened helper unit; daemon-reload; socket stays up; no restart needed =="
sudo bash /tmp/p13/p13-s2.sh helper
echo "== the key is unreadable under the new directive (run as aleix with the same InaccessiblePaths) =="
sudo systemd-run --wait --pipe --quiet -p User=aleix -p InaccessiblePaths=-/home/aleix/.ssh \
  -- /bin/ls -la /home/aleix/.ssh ; echo "rc=$? (expect non-zero / permission denied)"
echo "== Phase 09 verification (socket, bot reaches it, credential boundary, no new listener) =="
sudo bash /tmp/p13/install-model-helper.sh verify
```

Then **a real request**: on Telegram send `/ask what is 2+2` to the bot. Expect an answer.

```bash
# S1
echo "== the instance that served it, and its score =="
journalctl -u 'homelab-model-helper@*' -n 20 --no-pager
inst=$(systemctl list-units --all --no-legend --plain 'homelab-model-helper@*' | awk '{print $1}' | head -1)
[ -n "$inst" ] && systemd-analyze security --no-pager "$inst" | tail -1
```

If `/ask` **fails** (no answer, or the journal shows `SIGSYS`/`Operation not permitted`): one
bisect round only —

```bash
sudo bash /tmp/p13/p13-s2.sh helper-nofilter     # same unit minus the two SystemCallFilter lines
```
— then `/ask` again. If that passes, the filter is out and the guide records it; if it still fails,
`sudo bash /tmp/p13/p13-s2.sh helper --undo` and the whole 6.12 change is reported, not forced.

## 4b — `wifi-powersave-off` (§6.13) — **S2 idle; this is the only network path**

```bash
# S2 — type, do not run:
sudo bash /tmp/p13/p13-s2.sh wifi --undo
```
```bash
# S1
echo "== install bounded unit; daemon-reload; RESTART; expect is-active + 'Power save: off'; auto-reverts on failure =="
sudo bash /tmp/p13/p13-s2.sh wifi
```
```bash
# T
echo "== still reachable, fresh =="; ssh -o BatchMode=yes homelab true; echo "rc=$?"
```

Reboot proof lands in S3's power-cycle.

## 4c — `aleix` out of `lxd` (§6.14)

```bash
# S1
echo "== gpasswd -d aleix lxd; effective at next login =="
sudo bash /tmp/p13/p13-s2.sh lxd
```
```bash
# T — a THIRD, fresh session; S1 and S2 stay open
ssh homelab 'id; sudo -n true && echo "sudo still works"'      # groups: no lxd; sudo ok
```

Rollback: `sudo bash /tmp/p13/p13-s2.sh lxd --undo`.

## 5 — Second SSH key (§6.8) — **S2 idle** (touches `authorized_keys`)

Insert the backup card first (`/Volumes/SD Card`).

```bash
# T
KEYDIR=$(mktemp -d); K="$KEYDIR/id_ed25519_homelab_recovery"
echo "== generate the recovery pair in a temp dir (no passphrase; age encrypts it below) =="
ssh-keygen -t ed25519 -N '' -C "homelab recovery — $(date +%F)" -f "$K"
echo "== append the public half to the node (one line, no restrict options) =="
ssh homelab "cat >> ~/.ssh/authorized_keys" < "$K.pub"
ssh homelab 'echo "authorized_keys lines: $(grep -c ^ssh- ~/.ssh/authorized_keys)"'   # expect 2
echo "== row 5: log in with ONLY the new key, no agent =="
ssh -i "$K" -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes homelab true; echo "rc=$?"
echo "== age-encrypt the private half onto the card next to the LUKS header backup (you will be asked for a passphrase — age's prompt) =="
mkdir -p "/Volumes/SD Card/homelab-backup/recovery-key"
age -p -o "/Volumes/SD Card/homelab-backup/recovery-key/id_ed25519_homelab_recovery.age" "$K"
cp "$K.pub" "/Volumes/SD Card/homelab-backup/recovery-key/"
echo "== prove the card copy decrypts to the same key, then destroy the plaintext =="
age -d "/Volumes/SD Card/homelab-backup/recovery-key/id_ed25519_homelab_recovery.age" | ssh-keygen -y -f /dev/stdin | cut -d' ' -f1-2
cut -d' ' -f1-2 "$K.pub"                                    # the two lines above must match
rm -P "$K" "$K.pub"; rmdir "$KEYDIR"; ls ~/.ssh                # private half absent from the MacBook
ssh-add -l                                                    # still only the primary key
```

Store the age passphrase in the password manager with the LUKS header's. Rollback: remove the
second line from `~aleix/.ssh/authorized_keys` on the node.

## 6 — GitHub key (§6.2b) — no node change

Already OBSERVED in S1: `0600`, one `Host github.com` block, `IdentitiesOnly yes`, account key listed
once as `homelab node — 2026-09-12`, no deploy keys. The ADR-046 table row is written in S3.
Nothing to run.

## 7 — Tailscale ACL (§6.7) — **S2 idle**; applied from outside the node, last

The policy is committed at `config/tailscale/acl.hujson`. **Recovery:** a wrong policy locks the
MacBook out of the node and leaves the node fine — edit the policy again from any browser at
https://login.tailscale.com/admin/acls/file ; the console (ADR-041) is the fallback.

1. Open https://login.tailscale.com/admin/acls/file in the browser.
2. Replace the whole policy with the contents of `config/tailscale/acl.hujson`. The console runs the
   `tests` block on save; if it rejects the *test* syntax, delete the `tests` block, not the grant.
3. Save.

```bash
# T — row 8, positive half; S1 and S2 are still open throughout
echo "== fresh connection under the new ACL =="; ssh -o BatchMode=yes homelab true; echo "rc=$?"
echo "== tunnel alias (still TCP 22 — the forward rides inside SSH) =="
ssh -o BatchMode=yes -N homelab-workbench & TUN=$!; sleep 3
curl -m 5 -s -o /dev/null -w 'workbench via tunnel: HTTP %{http_code}\n' http://127.0.0.1:8765/; kill $TUN
echo "== a non-22 port on the node is now refused at the tailnet layer (expect timeout) =="
nc -zv -w3 100.71.62.71 36121
```

Row 8's negative half (a device *not* in the allow list) is **PREDICTED** — the tailnet has no
second device (S1 decision 6.16).

## 8 — After every change: `/status`

Send `/status` to the bot after steps 1, 2, 4b and 7. Expect the usual reply with the volume
unlocked.

## 9 — Stand down (standard §8)

```bash
# T — a fourth fresh connection and the closing check
ssh homelab 'echo "== failed units =="; systemctl --failed; systemctl is-system-running;
  systemctl is-active homelab-workbench homelab-telegram-bot homelab-watchdog.timer homelab-model-helper.socket wifi-powersave-off;
  echo "== sockets (expect 7) =="; sudo ss -tlnp | tail -n +2 | wc -l; sudo ss -tlnp'
```

Only now close S2. Paste everything back; the guide's debt table turns proposed outcomes into
OBSERVED ones from it.

## Rollback summary

| Step | Undo |
|---|---|
| 1 | `sudo cp …/10-homelab-hardening.conf.bak-<date> …/10-homelab-hardening.conf && sudo systemctl reload ssh` |
| 2 | `sudo bash /tmp/p13/apply-docker-user-rules.sh --undo` (auto after 10 min unless `--keep`) |
| 3 | `sudo bash /tmp/p13/p13-s2.sh tmout --undo` |
| 4a | `sudo bash /tmp/p13/p13-s2.sh helper --undo` |
| 4b | `sudo bash /tmp/p13/p13-s2.sh wifi --undo` (automatic on failure) |
| 4c | `sudo bash /tmp/p13/p13-s2.sh lxd --undo` |
| 5 | delete the second line of `~aleix/.ssh/authorized_keys` |
| 7 | restore the previous policy in the admin console (allow-all is the stock default) |
