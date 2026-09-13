# Phase 15.0 — S2 runbook (registry swap on the node)

One owner session. **Every step prints what it is about to do before it waits for anything; no
silent pause.** The only prompt anywhere is a `sudo` password prompt you can see. Nothing here is
piped through `tail`, `head` or `less` (the Phase 13 closing defect).

**Class:** ordinary — a user-space service change, revertible from git. Not lockout-class: no
network, boot, authentication or disk change; the unit file is **not** edited.

**The one thing to know before starting.** The new helper code refuses the Phase 09 `config.json`
shape, and the old code cannot read the new shape. They must swap together. `Accept=yes` means each
`/ask` is a fresh process that reads the config at start, so the window between "code installed"
and "config moved" is real but short — a few seconds. An `/ask` that lands inside it gets
`Could not ask a model: helper misconfigured` on Telegram and a `config error:` line in the journal;
it is retried by sending it again, nothing is lost and nothing is spent. Step 3 keeps that window
to one `mv`.

Terminals:

- **T** — MacBook-local, in `/Users/home/Code/homelab-p150`.
- **S1** — `ssh homelab`.

## 0 — Preflight (T, S1)

```bash
# T — the fixture passes locally before anything is copied. Expect "All 19 checks passed."
echo "== local fixture (no node, no allowance) =="
python3 services/model-helper/fixture-tests.py

echo "== stage the ROLLBACK first: the Phase 09 helper from main (7c2fc3b) to /tmp/p150-rollback on the node =="
mkdir -p /tmp/p150-rollback
for f in helper providers limits; do
  git -C /Users/home/Code/homelab show 7c2fc3b:services/model-helper/$f.py > /tmp/p150-rollback/$f.py
done
ssh homelab 'mkdir -p /tmp/p150-rollback /tmp/homelab-phase09'
scp /tmp/p150-rollback/*.py homelab:/tmp/p150-rollback/
ssh homelab 'ls -l /tmp/p150-rollback/'

echo "== copy the helper files to the node (same staging path Phase 09 used) =="
scp services/model-helper/helper.py services/model-helper/providers.py \
    services/model-helper/limits.py services/model-helper/socket-probe.py \
    services/model-helper/fixture-tests.py services/model-helper/config.example.json \
    config/systemd/homelab-model-helper.socket config/systemd/homelab-model-helper@.service \
    scripts/server/install-model-helper.sh \
    homelab:/tmp/homelab-phase09/
```

The revert is on the box before anything changes. `/tmp` is cleared at boot; nothing here reboots.

```bash
# S1 — sudo once, up front, at a labelled line. Every later sudo in this runbook runs on the
# refreshed timestamp, so no piped command is ever the one that prompts (baseline §7).
echo "== refreshing sudo (password prompt follows) =="; sudo -v

# S1 — baseline. Every figure here is compared against at the end.
echo "== nothing failed =="; systemctl --failed; systemctl is-system-running
echo "== the NEW verify against the OLD install: the Phase 09 six must pass; the two 15.0 checks"
echo "   are EXPECTED to say UNKNOWN (no fixture file in /opt yet) and FAIL (config is Phase 09 shape) =="
echo "   (sudo password prompt follows)"
sudo bash /tmp/homelab-phase09/install-model-helper.sh verify
```

Expected: six `ok` lines (socket, probe, two credentials, groups, code not writable), then
`UNKNOWN  /opt/homelab-model-helper/fixture-tests.py is not installed` and
`FAIL  config.json 'providers' is list` — both are the state this runbook exists to change. Anything
else not `ok` is a stop. Note the `TCP listeners:` count — seven.

```bash
# S1 — the two facts that must be byte-identical at the end
echo "== id homelab-bot =="; id homelab-bot | tee /tmp/p150-id-before
echo "== ss -tlnp (expect seven) =="; sudo ss -tlnp | tee /tmp/p150-ss-before
echo "== helper unit score before (expect 3.8) =="
sudo systemd-analyze security homelab-model-helper@.service --no-pager | grep -i 'overall exposure'
```

## 1 — Write the new config beside the old one (S1)

Nothing changes yet. The new file is written as `config.json.new`, root-owned, from the example —
then the two model ids are checked against the live file so the swap changes the *shape* only.

```bash
# S1
echo "== current config (Phase 09 shape) =="
sudo cat /etc/homelab-model-helper/config.json

echo "== write config.json.new from the example (root:root 0644) =="
sudo install -o root -g root -m 0644 /tmp/homelab-phase09/config.example.json \
     /etc/homelab-model-helper/config.json.new

echo "== compare the model ids and binaries old vs new (expect four 'same') =="
sudo python3 - <<'EOF'
import json
old = json.load(open('/etc/homelab-model-helper/config.json'))
new = json.load(open('/etc/homelab-model-helper/config.json.new'))
for p, key in (('claude', 'haiku'), ('codex', 'mini')):
    print(p, 'bin  ', 'same' if old[p]['bin'] == new['providers'][p]['bin'] else f"DIFFERENT {old[p]['bin']} -> {new['providers'][p]['bin']}")
    print(p, 'model', 'same' if old[p]['model'] == new['providers'][p]['models'][key]['id'] else f"DIFFERENT {old[p]['model']} -> {new['providers'][p]['models'][key]['id']}")
print('caps', old['caps'], '->', new['caps'])
EOF
```

If a line says `DIFFERENT`, stop and paste it. The live config may carry a model the example does
not (the owner may have tuned it); the fix is to edit `config.json.new` to match, not to proceed.

```bash
# S1 — the new file must load under the NEW code before it goes live. Runs the new helper
# from /tmp as aleix with `ping` (no model call), pointed at config.json.new.
echo "== new code + new config: ping (expect ok:true, providers [claude, codex]) =="
echo '{"v":1,"op":"ping"}' | HOMELAB_MODEL_HELPER_CONFIG=/etc/homelab-model-helper/config.json.new \
    python3 /tmp/homelab-phase09/helper.py
```

## 2 — Keep the old config as the rollback (S1)

```bash
# S1 — never overwrite a same-day backup (baseline §7)
BAK=/etc/homelab-model-helper/config.json.bak-$(date +%F)
echo "== backup old config to $BAK (refuses if it already exists) =="
if sudo test -e "$BAK"; then echo "STOP: $BAK exists — a second round today; choose another name"; else
  sudo cp -p /etc/homelab-model-helper/config.json "$BAK" && sudo ls -l "$BAK"; fi
```

## 3 — The swap: install the code, then move the config (S1)

`install` copies the code to `/opt` (the window opens), leaves the existing `config.json` alone by
design, re-installs the unchanged units, runs `daemon-reload`, and then runs `verify` — which will
now **FAIL on `config.json is in the Phase 09 shape`** and skip nothing else. That failure is
expected and is the window. The `mv` on the next line closes it.

```bash
# S1
echo "== install the Phase 15.0 helper code (sudo prompt follows). verify at the end is EXPECTED"
echo "   to FAIL on the config-shape check — that is the window, closed by the next command. =="
sudo bash /tmp/homelab-phase09/install-model-helper.sh install

echo "== close the window: move the new config into place (atomic rename) =="
sudo mv /etc/homelab-model-helper/config.json.new /etc/homelab-model-helper/config.json
sudo ls -l /etc/homelab-model-helper/
```

Rollback, if anything in step 4 is wrong — one step, both halves:

```bash
# S1 — ROLLBACK ONLY. Old config back, old code back from /tmp/p150-rollback (staged in step 0).
echo "== rollback: restore config and the three Phase 09 files =="
sudo cp -p /etc/homelab-model-helper/config.json.bak-$(date +%F) /etc/homelab-model-helper/config.json
for f in helper providers limits; do sudo install -o root -g root -m 0644 /tmp/p150-rollback/$f.py /opt/homelab-model-helper/$f.py; done
sudo ls -l /opt/homelab-model-helper/ /etc/homelab-model-helper/
```

## 3b — Clear the window's failed instance (S1)

The installer's own probe in step 3 lands inside the window by construction (it runs `verify`
before the `mv`), so one helper instance exits 1 and stays `failed`; `OnFailure` also sends one
Telegram notice. Both are the window made visible, not a fault. Clear it:

```bash
# S1
echo "== the failed instance from the window (expect one homelab-model-helper@… line) =="; systemctl --failed
echo "== reset it =="; sudo systemctl reset-failed 'homelab-model-helper@*'; systemctl is-system-running
```

## 4 — Verify (S1)

```bash
# S1 — the full verify, now including the fixture as aleix. Expect "All checks passed."
echo "== verify (sudo prompt follows) =="
sudo bash /tmp/homelab-phase09/install-model-helper.sh verify
```

What to look for in the output, each a brief test:

| Line | Test |
|---|---|
| `fixture tests passed as aleix` and the five `test 1/2/3/11/12` lines under it | 1, 2, 3, 11, 12 (and 5, 6, 7, 8 inside the same run) |
| `homelab-bot is in no group but its own` | 9 |
| `config.json is in the Phase 15.0 registry shape` | the swap |
| `still cannot read` ×2, `InaccessiblePaths` unchanged | 15 |

```bash
# S1 — the byte-identical pair and the score
echo "== id homelab-bot (expect: no diff) =="; id homelab-bot | diff /tmp/p150-id-before - && echo same
echo "== ss -tlnp (expect: no diff — seven) =="; sudo ss -tlnp | diff /tmp/p150-ss-before - && echo same
echo "== helper unit score after (expect 3.8) =="
sudo systemd-analyze security homelab-model-helper@.service --no-pager | grep -i 'overall exposure'
echo "== nothing failed =="; systemctl --failed; systemctl is-system-running
```

## 5 — Test 4: `/ask` from Telegram, live (phone + S1)

Send from the phone: `/ask what is the load on this machine?`

```bash
# S1 — the journal line for that call. Expect route=owner-interactive unattended=false ... outcome=ok
echo "== last helper journal lines =="
sudo journalctl -u 'homelab-model-helper@*' -n 5 --no-pager -o cat
```

Paste the Telegram reply verbatim (it ends `-- claude/haiku` or `-- codex/gpt-5.6-luna`, as before)
and the journal line. That is test 4's captured output.

## 6 — Test 14: the volume locked (S1 + phone)

```bash
# S1 — the helper lives on root; it must answer with the volume locked (ADR-046 §2)
echo "== lock the volume (sudo prompt follows) =="
sudo data-volume.sh lock
echo "== now send /ask from the phone; then unlock =="
```

Send `/ask is the volume relevant to you?` from the phone; paste the reply. Then:

```bash
# S1
echo "== unlock (passphrase goes to cryptsetup's own prompt) =="
sudo data-volume.sh unlock
systemctl --failed; systemctl is-system-running
```

(`sudo data-volume.sh lock|unlock` is the form the Phase 18.1 execution handover records, §3 and
line 843; it is on `PATH` for root.)

## 7 — Paste back

Everything printed by steps 0, 1, 3, 4, 5 and 6, plus the two Telegram replies. The stage report
tags each brief test OBSERVED from those pastes.
