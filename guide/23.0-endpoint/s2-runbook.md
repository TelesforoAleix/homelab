# Phase 23.0 — S2 runbook (the node)

One owner session doing the work, **a second idle SSH session open throughout** (S2 below), the
phone for Telegram. **Every step prints what it is about to do before it waits for anything; no
silent pause.** The only prompt anywhere is a `sudo` password prompt you can see. Nothing is piped
through `tail`, `head` or `less`. `sudo -v` runs once, up front, at a labelled line.

**Class:** boot-class (`safe-changes-headless.md`) — the new unit is `WantedBy=multi-user.target`
and the last step is a reboot with the volume locked. Not lockout-class: nothing here touches sshd,
the firewall, Tailscale, authentication, the admin account or the volume's encryption. The unlock
after the reboot is over SSH as usual; the console is the fallback, not a requirement.

**The order is the brief's §7.2 and the reason is the regression check:** the helper's socket
changes group and the bot is restarted *before* the harness exists, and `/ask` is proved working in
between — so if `/ask` breaks, the only thing that changed is ADR-048, not the new consumer.

**Costs.** Steps 6 and 7 make **four real model calls** through the endpoint (rows 3, 4a, 4b, 7).
Subscription only, under the helper's caps (6/hour per provider). Everything else is a ping, a
refusal, or the fixture with a stub. Count them for `costs.md` (0 €).

Terminals:

- **T** — MacBook-local, in `/Users/home/Code/homelab-p230`.
- **S1** — `ssh homelab` (the working session).
- **S2** — a second `ssh homelab`, idle. Open it first. Do nothing in it unless S1 is lost.
- **Phone** — Telegram, the bot.

## 0 — Preflight, and the rollback staged first (T, S1)

```bash
# T — both fixtures pass locally before anything is copied. Expect 19 and 64.
echo "== local fixtures (no node, no allowance) =="
python3 services/model-helper/fixture-tests.py 2>&1 | grep -E '^All|did not pass'
python3 services/homelab-harness/fixture-tests.py 2>/dev/null | grep -E '^All|did not pass'

echo "== stage the ROLLBACK first: the previous socket unit and notifier from main (9b6db12) =="
mkdir -p /tmp/p230-rollback
git show 9b6db12:config/systemd/homelab-model-helper.socket > /tmp/p230-rollback/homelab-model-helper.socket
git show 9b6db12:scripts/server/homelab-notify.sh          > /tmp/p230-rollback/homelab-notify.sh
ssh homelab 'mkdir -p /tmp/p230-rollback /tmp/homelab-phase230 /tmp/homelab-phase09'
scp /tmp/p230-rollback/* homelab:/tmp/p230-rollback/

echo "== copy the harness files (installer reads /tmp/homelab-phase230) =="
scp services/homelab-harness/harness.py services/homelab-harness/classify.py \
    services/homelab-harness/fixture-tests.py services/homelab-harness/config.example.json \
    config/systemd/homelab-harness.service \
    config/systemd/homelab-harness.service.d/onfailure.conf \
    scripts/server/install-homelab-harness.sh \
    homelab:/tmp/homelab-phase230/
echo "== copy the helper-side changes (its installer reads /tmp/homelab-phase09) =="
scp config/systemd/homelab-model-helper.socket \
    config/systemd/homelab-model-helper@.service.d/runtime.conf \
    scripts/server/install-model-helper.sh scripts/server/homelab-notify.sh \
    homelab:/tmp/homelab-phase09/
ssh homelab 'ls -l /tmp/p230-rollback/ /tmp/homelab-phase230/ /tmp/homelab-phase09/'
```

```bash
# S1 — sudo once, up front. Every later sudo runs on the refreshed timestamp.
echo "== refreshing sudo (password prompt follows) =="; sudo -v

echo "== stage the on-node side of the rollback: live copies of what this runbook changes =="
sudo cp -p /etc/systemd/system/homelab-model-helper.socket /tmp/p230-rollback/live.socket
sudo cp -p /usr/local/sbin/homelab-notify.sh              /tmp/p230-rollback/live.notify.sh
sudo cp -p /etc/homelab-model-helper/config.json          /tmp/p230-rollback/live.config.json
sudo chown aleix:aleix /tmp/p230-rollback/live.*
ls -l /tmp/p230-rollback/
```

The revert is on the box before anything changes. `/tmp` is cleared at boot; step 9 reboots, so
the `.bak-<date>` copies the installers keep beside the live files are the durable rollback.

```bash
# S1 — baseline. Every figure here is compared against at the end.
echo "== nothing failed =="; systemctl --failed; systemctl is-system-running
echo "== id homelab-bot (expect: uid,gid,groups=homelab-bot only) =="; id homelab-bot | tee /tmp/p230-id-before
echo "== the socket (expect aleix:homelab-bot:660) =="; stat -c '%U:%G:%a' /run/homelab-model-helper.sock
echo "== ss -tlnp (expect SEVEN) =="; sudo ss -tlnp | tee /tmp/p230-ss-before
echo "== helper instance score before (expect 3.8) =="
sudo systemd-analyze security 'homelab-model-helper@probe.service' --no-pager | grep -i 'overall exposure'
echo "== the NEW verify against the OLD install: expect ok everywhere except THREE named FAILs"
echo "   (socket is aleix:homelab-bot -- the Phase 09 group; bot not yet in homelab-model; group"
echo "   homelab-model does not exist), each saying 'run group' -- the state this runbook changes =="
sudo bash /tmp/homelab-phase09/install-model-helper.sh verify
```

**Phone:** `/ask what is a unix socket` → an answer. **Row 14 "before".** Note the time.

## 1 — ADR-048: the group, the socket, the bot (S1, phone)

```bash
# S1 — creates homelab-model, adds homelab-bot, installs the socket unit (previous kept as
# .bak-<date>), restarts the socket AND the bot (its process's groups are fixed at exec), verifies.
echo "== install-model-helper.sh group =="
sudo bash /tmp/homelab-phase09/install-model-helper.sh group
```

Expected: `created system group homelab-model`, `added homelab-bot to homelab-model`,
`socket restarted: aleix:homelab-model:660`, `bot restarted and active`, then the verify block
**all `ok`** including `fixture tests passed as aleix` (**row 14: 19/19 on the node**) and
`getent group homelab-model = homelab-bot` (the harness is not a member yet — correct at this step).
`TCP listeners: 7`.

```bash
# S1 — the two facts, and row 18 early: a third account outside the group is refused
echo "== id homelab-bot (expect groups=homelab-bot,homelab-model and NOTHING else) =="; id homelab-bot
echo "== row 18: nobody probes the socket (expect PROBE FAIL ... errno=13 Permission denied) =="
sudo setpriv --reuid=nobody --regid=nogroup --clear-groups \
    /usr/bin/python3 /opt/homelab-model-helper/socket-probe.py /run/homelab-model-helper.sock; echo "rc=$?"
```

**Phone:** `/ask what is a unix socket` again → an answer. **Row 14 "after the SocketGroup change".**
If it fails with a permission error in `journalctl -u homelab-telegram-bot`, the bot did not restart
— `sudo systemctl restart homelab-telegram-bot.service` and retry. If anything else: stop, rollback
step A below.

## 2 — RuntimeMaxSec (6.9) (S1)

```bash
# S1 — the drop-in, then the value systemd actually holds
echo "== installing homelab-model-helper@.service.d/runtime.conf (RuntimeMaxSec=270) =="
sudo install -o root -g root -m 0644 /tmp/homelab-phase09/runtime.conf \
    /etc/systemd/system/homelab-model-helper@.service.d/runtime.conf
sudo systemctl daemon-reload
echo "== RuntimeMaxUSec (expect 4min 30s) =="
systemctl show -p RuntimeMaxUSec --value 'homelab-model-helper@probe.service'
echo "== helper instance score after (expect 3.8, unchanged -- a timeout is not a sandbox directive) =="
sudo systemd-analyze security 'homelab-model-helper@probe.service' --no-pager | grep -i 'overall exposure'
```

## 3 — Routes and the question limit in config.json (6.8, S1 q4) (S1)

One route, `execution-agent`, to the same list as `owner-interactive`; `max_question_chars` 4000.
No wildcard. The previous file is kept as `.bak-<date>-p230` — suffixed because Phase 15.0's S2 ran
the same morning and its `.bak-2026-09-13` already exists; the first run of this step refused to
overwrite it and changed nothing (OBSERVED 12:4x). The date-only convention assumes one phase per
day; a same-day second phase adds a suffix. Written as `python3 -c`, not a heredoc: a heredoc
pasted with indentation never terminates (OBSERVED, the owner had to ^C).

```bash
# S1 — prints the resulting routes and limit; nothing else in the file changes
echo "== editing /etc/homelab-model-helper/config.json (backup first, then one route + one limit) =="
sudo python3 -c '
import json, datetime, os, shutil
p = "/etc/homelab-model-helper/config.json"
bak = p + ".bak-" + datetime.date.today().isoformat() + "-p230"   # a 15.0 .bak from the same morning exists (OBSERVED)
if os.path.exists(bak): raise SystemExit(bak + " exists -- refusing to overwrite (baseline 7)")
shutil.copy2(p, bak); print("kept", bak)
c = json.load(open(p))
c["routes"]["execution-agent"] = list(c["routes"][c["default_route"]])
c["max_question_chars"] = 4000
fh = open(p + ".new", "w"); json.dump(c, fh, indent=2); fh.write("\n"); fh.close()
os.chmod(p + ".new", 0o644); os.replace(p + ".new", p)
print(json.dumps({"routes": c["routes"], "default_route": c["default_route"], "max_question_chars": c["max_question_chars"]}, indent=2))
'
echo "== the helper still loads it: ping (no model call) =="
python3 /opt/homelab-model-helper/socket-probe.py
```

Expected: `routes` has exactly `owner-interactive` and `execution-agent`, both
`["claude/haiku", "codex/mini"]`; `PROBE OK`.

## 4 — The notifier alias (S1)

```bash
# S1 — the harness) case, same stage as the drop-in that names it
echo "== installing homelab-notify.sh (previous kept as .bak-<date>) =="
bak="/usr/local/sbin/homelab-notify.sh.bak-$(date +%F)"
[ -f "$bak" ] || sudo cp -p /usr/local/sbin/homelab-notify.sh "$bak"
sudo install -o root -g root -m 0755 /tmp/homelab-phase09/homelab-notify.sh /usr/local/sbin/homelab-notify.sh
bash -n /usr/local/sbin/homelab-notify.sh && echo "syntax ok"
grep -n 'harness)' /usr/local/sbin/homelab-notify.sh
```

## 5 — The harness: account, code, config, unit, start, verify (S1)

```bash
# S1 — creates homelab-harness (system, nologin, no home, groups: own + homelab-model), installs
# /opt/homelab-harness, /etc/homelab-harness/config.json, the unit and its drop-in, enables and
# starts, then runs every check (the 64-check fixture runs as homelab-harness, stub CLIs, no spend).
echo "== install-homelab-harness.sh install =="
sudo SRC=/tmp/homelab-phase230 bash /tmp/homelab-phase230/install-homelab-harness.sh install
```

Expected, in order: six files present; group exists; `created homelab-harness: uid=… groups=…
homelab-harness,homelab-model`; four files installed; config installed; `systemd-analyze verify
accepted the unit` (two `CPUAccounting` warnings about vendor xfs units are systemd's, not ours); `RequiresMountsFor=/var/lib/homelab-harness -- on root`; enabled and started; then the verify block with
every line `ok` — in particular `GET /health/helper: the harness reached the helper's socket`
(**row 10 live**), `nobody ... is refused ... errno=13` (**row 18**), `fixture tests passed as
homelab-harness: All 64 checks passed` (**row 1**), and `systemd-analyze security
homelab-harness.service: 1.3` or another value ≤ 2.0 (**row 11**; PREDICTED 1.3 — paste the number).

```bash
# S1 — rows 8, 10, 20 by hand
echo "== row 8: ss -tlnp (expect EIGHT: the seven plus 127.0.0.1:8766 python3 as homelab-harness) =="
sudo ss -tlnp | tee /tmp/p230-ss-after
echo "== row 10 =="; id homelab-harness; getent group homelab-model
echo "== row 11 detail: the findings list, for the guide =="
sudo systemd-analyze security homelab-harness.service --no-pager
echo "== row 20: every # WHY in the new/changed units =="
grep -c 'WHY' /etc/systemd/system/homelab-harness.service /etc/systemd/system/homelab-model-helper.socket \
    /etc/systemd/system/homelab-model-helper@.service.d/runtime.conf
```

```bash
# T — row 9: from the MacBook with Tailscale up and NO tunnel open
echo "== row 9: expect 'Connection refused' or a timeout, never JSON =="
curl -m 5 -sS http://homelab:8766/ ; echo "rc=$?"
```

## 6 — The endpoint, live (S1). Four real calls.

Shipped as a script, `s2-step6.sh`, because the long `curl -d` lines wrap when pasted and a wrapped
line runs as two commands (OBSERVED 12:55 — and it was run on the MacBook by mistake, where nothing
listens; no call was spent). It prints every step, refreshes `sudo` at a labelled line, and grep-
proves the audit file and journal at the end.

```bash
# T
scp guide/23.0-endpoint/s2-step6.sh homelab:/tmp/homelab-phase230/
```

```bash
# S1 — on the NODE
bash /tmp/homelab-phase230/s2-step6.sh
```

Expected: rows 2 (×2), 6, 7a refused with `identity_in_body` (field named), `needs_decomposition`,
`not_a_request`, and **no helper journal line** for them; row 3 `ok` with `provider`/`model`; rows
4a/4b the same provider and model (if they differ, read the journal: a fallback because of an
`exhausted` provider is not a hint selecting); row 5 `unknown_role`, `stage: helper`, message
verbatim; row 7b the model's text returned, `NRestarts` identical; grep counts `0` and `0`. Take a
distinctive word from the printed answer and `sudo grep -c '<word>' /var/lib/homelab-harness/audit.jsonl`
→ `0`.

## 7 — Row 13: the start limit and the alert (S1, phone)

`Restart=on-failure`, `RestartSec=5`, `StartLimitBurst=5` in 300 s. Five SIGKILLs seven seconds
apart exhaust the burst; the sixth start is refused, the unit enters `failed`, `OnFailure=` fires.

```bash
# S1 — prints each kill; ~40 s in total
echo "== killing homelab-harness 5x, 7 s apart (each one restarts until the limit) =="
for i in 1 2 3 4 5; do
  echo "kill $i at $(date +%T)"; sudo systemctl kill -s SIGKILL homelab-harness.service; sleep 7
done
echo "== state (expect: failed, Result: start-limit-hit) =="
systemctl status homelab-harness.service --no-pager -l | sed -n '1,12p'
```

**Phone:** a Telegram message `Home Lab alert: homelab-harness.service failed.` with five journal
lines. **Row 13.**

```bash
# S1 — recover, and prove the recovery
echo "== reset-failed + start =="
sudo systemctl reset-failed homelab-harness.service; sudo systemctl start homelab-harness.service; sleep 2
systemctl is-active homelab-harness.service; curl -sS http://127.0.0.1:8766/health; echo
echo "== nothing left failed =="; systemctl --failed; systemctl is-system-running
```

## 8 — Row 12, part 1: the volume locked, the endpoint up (S1, phone)

```bash
# S1 — lock (stops homelab-data.target and the Workbench), ask the endpoint, unlock
echo "== data-volume.sh lock =="; sudo data-volume.sh lock
echo "== workbench (expect inactive), harness (expect active) =="
systemctl is-active homelab-workbench.service homelab-harness.service
echo "== the endpoint answers while locked: health + helper ping + a refusal (no spend) =="
curl -sS http://127.0.0.1:8766/health; echo
curl -sS http://127.0.0.1:8766/health/helper; echo
curl -sS -H 'X-Homelab-Client: runbook' -d '{"v":1,"kind":"task","role":"execution-agent","question":"still here while locked"}' http://127.0.0.1:8766/v1/request; echo
```

**Phone:** `/status` → reports the volume locked.

```bash
# S1 — unlock (passphrase goes to cryptsetup's own visible prompt)
echo "== data-volume.sh unlock (cryptsetup passphrase prompt follows) =="; sudo data-volume.sh unlock
systemctl is-active homelab-workbench.service homelab-harness.service
```

## 9 — Row 12, part 2: the locked reboot (S1, S2, phone)

The boot-class proof. The volume is always locked at boot; the harness must come up anyway and the
Workbench must not. S2 will drop with the reboot — that is expected; reopen both sessions after.

```bash
# S1 — last look, then reboot
echo "== failed units before reboot (expect none) =="; systemctl --failed
echo "== rebooting in 5 s (ctrl-c to abort) =="; sleep 5; sudo reboot
```

Wait ~90 s. **Phone:** the watchdog's boot notice arrives (Phase 12), then `/status` → volume locked.

```bash
# T — reopen S1 and S2
ssh homelab
```

```bash
# S1 (new) — the four states of row 12
echo "== refreshing sudo (password prompt follows) =="; sudo -v
echo "== harness: expect active; workbench: expect inactive (Condition), NOT failed =="
systemctl is-active homelab-harness.service homelab-workbench.service
echo "== the Condition line (the refusal working, not a bug) =="
journalctl -u homelab-workbench.service -b --no-pager -o cat | grep -i condition
echo "== nothing failed after a locked boot =="; systemctl --failed; systemctl is-system-running
echo "== the endpoint on a locked boot =="; curl -sS http://127.0.0.1:8766/health; echo; curl -sS http://127.0.0.1:8766/health/helper; echo
echo "== the socket kept its group across the boot (/run is tmpfs) =="; stat -c '%U:%G:%a' /run/homelab-model-helper.sock
echo "== unlock (cryptsetup prompt follows) =="; sudo data-volume.sh unlock
echo "== workbench now active =="; systemctl is-active homelab-workbench.service
echo "== final: eight listeners, nothing failed =="; sudo ss -tlnp; systemctl --failed
```

**Phone:** `/ask what is a unix socket` → an answer (row 14, after the reboot).

## 10 — Paste back (to the executor)

1. Step 0: the two local fixture lines; `id homelab-bot` before; `ss -tlnp` before (seven); the helper score.
2. Step 1: the `group` output in full; `id homelab-bot` after; the `nobody` probe line; `/ask` worked before and after (times).
3. Step 2: `RuntimeMaxUSec`; the helper score after.
4. Step 3: the printed routes/limit JSON; `PROBE OK`.
5. Step 5: the `install` output in full — the score line especially, and the `systemd-analyze security` findings list; `ss -tlnp` after (eight); `id homelab-harness`; `getent group homelab-model`; the `# WHY` counts; row 9's curl line.
6. Step 6: every curl response; the helper journal lines with `harness:runbook`; `NRestarts` before/after; the audit file; the three grep counts.
7. Step 7: the status block; the Telegram alert text; `is-system-running` after recovery.
8. Steps 8–9: the `is-active` pairs at each point; the Condition line; `/status` while locked; the final `ss -tlnp`.

## Rollback

**A — undo ADR-048 alone** (steps 1–2; if `/ask` broke after step 1):

```bash
sudo -v
sudo install -o root -g root -m 0644 /tmp/p230-rollback/live.socket /etc/systemd/system/homelab-model-helper.socket
sudo rm -f /etc/systemd/system/homelab-model-helper@.service.d/runtime.conf
sudo systemctl daemon-reload && sudo systemctl restart homelab-model-helper.socket
sudo gpasswd -d homelab-bot homelab-model && sudo systemctl restart homelab-telegram-bot.service
stat -c '%U:%G:%a' /run/homelab-model-helper.sock    # aleix:homelab-bot:660
```

(The group itself may stay; an empty group is harmless. `groupdel homelab-model` once nothing
references it.) After a reboot `/tmp` is gone — use `/etc/systemd/system/homelab-model-helper.socket.bak-<date>`.

**B — undo the config change** (step 3): `sudo cp -p /etc/homelab-model-helper/config.json.bak-<date>-p230 /etc/homelab-model-helper/config.json`.

**C — undo the notifier** (step 4): `sudo install -m 0755 /usr/local/sbin/homelab-notify.sh.bak-<date> /usr/local/sbin/homelab-notify.sh`.

**D — remove the harness** (step 5 onward): `sudo bash /tmp/homelab-phase230/install-homelab-harness.sh uninstall`
— stops, disables, removes unit, drop-in, code, config and account; leaves `/var/lib/homelab-harness`.
Then A–C as needed. Nothing here is unrecoverable; nothing touched sshd, the firewall, Tailscale
or the volume.
