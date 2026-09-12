# Phase 13 — S3 runbook (credentials and the box)

Order fixed by the orchestrator: **2b → TMOUT tty proof → 6.6 → real reboot → post-boot checks → BIOS
→ power-cycle → post-boot checks.** ADR-047 and the ADR-046 amendments are written afterwards from
the evidence. Every step prints what it does before it waits; the only prompts are visible `sudo`
prompts and, in the BIOS, the firmware's own.

**Two moments the node can go dark: the reboot and the power-cycle.** A second SSH session is no
help across either — **be at the box with the monitor and keyboard attached for both** (ADR-041).
If 6.6 fails condition 3 (bot silent after the reboot), `creds-undo` runs from the console *before*
the BIOS visit. Never stack two boot-class changes on an unproven one.

Terminals: **S1** (`ssh homelab`), **S2** idle from step 1 to the reboot (it will not survive it),
**T** MacBook. Telegram open. Card **not** needed.

## 0 — Copy the S3 files (T)

```bash
echo "== copy S3 files =="
ssh homelab 'mkdir -p /tmp/p13/homelab-telegram-bot.service.d /tmp/p13/homelab-notify@.service.d /tmp/p13/homelab-watchdog.service.d'
scp scripts/server/p13-s3.sh homelab:/tmp/p13/
for u in homelab-telegram-bot homelab-notify@ homelab-watchdog; do
  scp "config/systemd/$u.service.d/credential.conf" "homelab:/tmp/p13/$u.service.d/"; done
```

## 1 — 2b: the published-port proof (S1, T) — node in a known-good state, nothing boot-class yet

```bash
# S1
echo "== publish a throwaway container on 0.0.0.0:8080 (python:3-alpine, ~50 MB) =="
docker run --rm -d --name p13probe -p 8080:80 python:3-alpine python3 -m http.server 80
docker ps --format '{{.Names}} {{.Ports}}'
```
```bash
# T — same LAN (192.168.1.x) and tailnet
echo "== LAN path: expect 'Operation timed out' (DOCKER-USER drops wlp1s0) =="; nc -zv -w3 192.168.1.57 8080
echo "== tailnet path: also timeout — the ACL (S2) allows only tcp/22, so this proves the ACL, not DOCKER-USER =="; nc -zv -w3 100.71.62.71 8080
echo "== the container itself answers on the node (proves it was listening) =="
ssh homelab 'curl -s -o /dev/null -w "local: HTTP %{http_code}\n" http://127.0.0.1:8080/; sudo iptables -vnL DOCKER-USER | grep -E "DROP|pkts"'
```
The LAN timeout is row 6's negative half. The `DROP` counter on the `wlp1s0` rule should be > 0
after the LAN attempt — that is the packet being dropped by *this* rule, not by something else.

```bash
# S1 — cleanup; row 16
echo "== remove the container and the image; inventory back to zero =="
docker rm -f p13probe; docker rmi python:3-alpine; docker system df
```

## 2 — TMOUT tty proof (at the box) — runs in the background of step 3

Attach monitor + keyboard. On **tty1**: log in as `aleix`, run `echo $TMOUT; date`, expect `900`
and note the time. Leave it. Meanwhile **S2 is also idle** — the control: it must still be alive
after the same 15½ minutes (`ssh` sessions carry no TMOUT). Check both at the start of step 4,
before the reboot: the tty shows a fresh login prompt (session ended); S2 still answers `echo ok`.

## 3 — 6.6: seal the bot token (S1)

**Before anything: the token must be in the password manager.** Its revocation path is
`@BotFather → /revoke` either way, but the plaintext there is what makes rollback a paste and not a
re-issue. If it is not there yet, read it once in private with `sudo cat /etc/homelab-telegram-bot/token`
and store it now. Nothing below prints it.

```bash
# S2 — type, do not run (rollback; also the console fallback after a reboot):
sudo bash /tmp/p13/p13-s3.sh creds-undo
```
```bash
# S1
echo "== condition 1 re-check, current state =="
sudo bash /tmp/p13/p13-s3.sh creds-check
echo "== encrypt (TPM2, no PCRs), install the three drop-ins, restart the bot; plaintext stays for now =="
sudo bash /tmp/p13/p13-s3.sh creds-encrypt
```
Telegram: `/status` → expect the usual answer. Then the notifier path, on demand:
```bash
# S1 — fire the notifier once by hand (it loads the same credential); expect a Telegram message
sudo systemctl start homelab-notify@bot.service; systemctl is-failed homelab-notify@bot.service || true
journalctl -u homelab-notify@bot.service -n 3 --no-pager
```

## 4 — The real reboot (condition 3) — at the box

Check step 2's result first (tty ended; S2 alive), then:

```bash
# S1
echo "== rebooting; the volume will come back LOCKED; expect the bot to report within ~2 min =="
sudo systemctl reboot
```
Watch the console. Expect: boot, login prompt, **then a Telegram message from the watchdog**
("volume locked" recovery notice) and `/status` answering with the volume locked — **without any
manual step.** That is condition 3.

```bash
# T — after /status answered
ssh -t homelab 'sudo bash /tmp/p13/p13-s3.sh postboot'
ssh -t homelab 'sudo data-volume.sh unlock'        # visible passphrase prompt, as always
ssh -t homelab 'sudo bash /tmp/p13/p13-s3.sh postboot'
```
Expect after unlock: `failed: 0`, `running`, volume mounted, Workbench `active`, wifi `Power save:
off` (boot proof of S2 4b), bot `Encrypted=bot-token`, watchdog's last line from this boot.

**If the bot is silent after 3 minutes:** console login → `sudo bash /tmp/p13/p13-s3.sh creds-undo`
→ `/status`. 6.6 is then *declined* with the journal as the reason; do **not** proceed to the BIOS.

**If it answered:** the sealed credential loads unattended. **Confirm — by looking, not by pasting —
that the bot token is in your password manager before continuing; if it is not, stop here** (the
fallback would be `@BotFather /revoke` + a new token, a different runbook). Then remove the plaintext:
```bash
# T
ssh -t homelab 'sudo bash /tmp/p13/p13-s3.sh creds-shred'
```

## 5 — BIOS (at the box) — Lenovo M700, `F1` at the logo

```bash
# S1 — first, a clean shutdown; the node powers off
sudo systemctl poweroff
```
Power on, press **F1**. Checklist (record each as done/not found):

1. **Security → Set Administrator Password** — set it. **Do not set a Power-On / Hard Disk password**
   (unattended boot, ADR-037 §2). Store it in the password manager. It is not written anywhere else.
2. **Security → Secure Boot** — confirm *Enabled*; change nothing (OBSERVED on in S1).
3. **Startup → Primary Boot Sequence** — the Ubuntu disk first; move USB, CD/DVD and both network
   entries below it or exclude them. **Startup → Boot Order Lock** → *Enabled* if the option exists.
4. **Devices → Network Setup → PXE / Boot Agent (IPv4 and IPv6)** → *Disabled* (or *Startup →
   Network Boot* → Disabled). This removes the two PXE entries ahead of USB.
5. **Power → After Power Loss** — confirm *Power On* (Phase 01's setting for unattended recovery).
6. Leave the stale `Windows Boot Manager` entry alone (decision 6.15).
7. **F10 save and exit.** The machine reboots: **row 10** — press F1 again during the reboot: expect
   the password prompt; press Esc and let it boot **without** entering it — boot must proceed
   unattended.

## 6 — Full power-cycle (row 11) — at the box

After the row-10 boot finishes and `/status` answers: `sudo systemctl poweroff` from S1 (or the
console), **pull the power cord for 10 s, plug it back in**. Expect the box to power on by itself
(After Power Loss = On), boot, and the bot to report with the volume locked — no keyboard touched.

```bash
# T
ssh -t homelab 'sudo bash /tmp/p13/p13-s3.sh postboot'
ssh -t homelab 'sudo data-volume.sh unlock'
ssh -t homelab 'sudo bash /tmp/p13/p13-s3.sh postboot; sudo efibootmgr'
echo "== both aliases, once more =="; ssh -o BatchMode=yes homelab true; echo "rc=$?"
```
Expect `BootOrder` to lead with `0001` and no `0006/0007` (PXE) ahead of it if step 5.4 took.

## 7 — Stand down

Detach the monitor and keyboard (the console stays *available*, ADR-041). Paste every output.
Then I write ADR-047, amend ADR-046 (row 6 = the GitHub key, row 3 rewritten for the sealed token,
check-2 grep, trigger 3 fired, dated re-run of all three checks), and update
`verify-node-backup.sh` for `token.cred`.

## Rollback summary

| Step | Undo |
|---|---|
| 1 | `docker rm -f p13probe; docker rmi python:3-alpine` |
| 3–4 | `sudo bash /tmp/p13/p13-s3.sh creds-undo` (console if needed) |
| 5 | Re-enter setup with the password; clear it under Security; re-enable network boot |
| shred | plaintext from the password manager: `sudo nano /etc/homelab-telegram-bot/token`, `chmod 0600` |
