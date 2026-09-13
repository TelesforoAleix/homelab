# Phase 23.0 — S2 report: the node

- **Stage:** S2 of four (brief §7.2). Node changed; `factory` untouched.
- **Run:** 2026-09-13, 10:40–11:10 UTC (12:40–13:10 local), one owner session, second idle session
  open until the reboot, phone for Telegram. Runbook: `s2-runbook.md` (+ `s2-step6.sh`).
- **Every claim below is OBSERVED** from pasted output unless marked PREDICTED.

## 1. What changed on the node

| Change | How | Rollback kept |
|---|---|---|
| group `homelab-model` (gid 981); `homelab-bot` added to it | `install-model-helper.sh group` | `gpasswd -d` |
| `homelab-model-helper.socket`: `SocketGroup=homelab-model` | same; socket restarted, **bot restarted** | `/etc/systemd/system/homelab-model-helper.socket.bak-2026-09-13` |
| `homelab-model-helper@.service.d/runtime.conf`: `RuntimeMaxSec=270` | `install` + `daemon-reload` | `rm` the drop-in |
| `/etc/homelab-model-helper/config.json`: route `execution-agent`, `max_question_chars: 4000` | `python3 -c` edit | `config.json.bak-2026-09-13-p230` |
| `/usr/local/sbin/homelab-notify.sh`: `harness)` alias | `install` | `homelab-notify.sh.bak-2026-09-13` |
| account `homelab-harness` (uid 995, gid 980, groups own + `homelab-model`), nologin, `/nonexistent` | `install-homelab-harness.sh install` | `uninstall` |
| `/opt/homelab-harness/` (4 files, root 0644), `/etc/homelab-harness/config.json`, `homelab-harness.service` + `onfailure.conf`, enabled into `multi-user.target`, `/var/lib/homelab-harness/audit.jsonl` | same | same |

Nothing else: sshd, firewall, Tailscale ACL, the volume's encryption and the Workbench unit untouched.

## 2. The brief's §8 rows — OBSERVED

| # | Row | Evidence |
|---|---|---|
| 1 | fixture, every refusal vs control | MacBook 64/64 (step 0); **node 64/64 as `homelab-harness`** with stub CLIs (step 5 verify) |
| 2 | identity in the body | `client`, `user_id` → `identity_in_body`, field named; helper journal **empty** for the window (step 6) |
| 3 | `question`, routed role | `ok`, `codex/gpt-5.6-luna`, `request_id 061fbbe7…`; helper journal `user=harness:runbook route=execution-agent … outcome=ok`; audit line `question_len 93, context_items 1, context_len 54, output_len 244, cost null, peer null`; grep of the question in audit file and journal → **0 / 0** |
| 4 | hints carried, not selecting | plain and hinted both `codex/gpt-5.6-luna`; journal shows `priority=critical complexity=high` on the hinted line, same path |
| 5 | role not in routes | `unknown_role`, `stage: helper`, `"no route for role 'review-qa'"` verbatim; journal `key=review-qa outcome=unknown_role`, no counter line (no cap spent) |
| 6 | `kind: task` | `needs_decomposition`, rule `T1`, no helper call |
| 7 | command; the canary | `/restart ssh.service` → `not_a_request` (`C2`), no helper call. Canary: model returned exactly `/restart ssh.service` as `text`; `NRestarts 0 → 0`; ssh `ActiveEnterTimestamp` unchanged from boot |
| 8 | eight sockets | `ss -tlnp`: the seven + `127.0.0.1:8766 python3` as uid 995; **8** again after the reboot (pids 1381 harness, 2240 Workbench) |
| 9 | from the MacBook, no tunnel | `curl -m 5 http://homelab:8766/` → `(28) Connection timed out` (ACL); from the node itself → `(7) refused` (loopback) |
| 10 | account and group | `id homelab-harness` = `980(homelab-harness),981(homelab-model)`; `getent group homelab-model` = `homelab-bot,homelab-harness`; no aleix/docker/sudo |
| 11 | scores | `homelab-harness.service` **1.3** (findings: the Workbench's list + `RestrictAddressFamilies=~AF_UNIX 0.1`, with `# WHY`); helper instance **3.8** before and after the drop-in; `RuntimeMaxUSec = 4min 30s` |
| 12 | locked; locked reboot | Locked: Workbench `inactive`, harness `active`, `/health`, `/health/helper reachable`, a request answered. After a locked reboot: `data-volume.sh status` LOCKED, harness `active` (pid 1381), Workbench `inactive` not failed, `--failed` empty, `running`, `/health` ok, socket `aleix:homelab-model:660` re-created from a fresh `/run`; unlock → Workbench `active`; `/health/helper reachable` |
| 13 | killed 5× / start limit | First round, **5 kills**: 5 alerts, unit came back (5 = the burst). Second round, **6 kills**: 7 alerts (one per kill + one for the refused 6th restart: `restart counter is at 6`, `Start request repeated too quickly`), `Result=signal`, `NRestarts=6`, `failed`; `reset-failed` + `start` → `active`, `/health` ok, `running` |
| 14 | `/ask` before / after | 12:43 before the group change (claude/haiku); after the socket+bot restart; and after the reboot at 13:09 (codex) — all answered. 15.0 fixture **19/19 on the node** after the `SocketGroup` change (step 1 verify) |
| 18 | third account | `sudo setpriv --reuid=nobody … socket-probe.py` → `PROBE FAIL: PermissionError errno=13`; again inside the harness `verify` |
| 20 | `# WHY` present | `grep -c WHY`: service 5, socket 2, runtime.conf 1 |
| 19 | backup | scripts updated in this stage (`backup-node.sh`, `verify-node-backup.sh`); **run is S4's** — PREDICTED until then |
| 15–17 | factory | S3 |

## 3. Findings

1. **Claude's subscription limit was reached during S2.** Every real call's first provider
   (`claude/haiku`) answered `outcome=exhausted` and the route fell back to Codex (`took 1.7–2.1 s`
   for the refusal, `4.9–5.9 s` for the answer). The 15.0 fallback works as designed and row 4's
   "same provider/model" held through it. Two consequences: the helper's cap counter counts the
   *reservation*, so four refused Claude attempts show as `claude: 4/6 this hour` — a cap slot is
   spent on a provider that then refuses; and the morning's phases plus this one used the day's
   Claude allowance. Costs: **4 Codex answers, 0 €**; the `/ask`s in row 14 are the owner's.
2. **`OnFailure=` pages once per crash.** With `Restart=on-failure`, a crash loop sends one alert per
   restart plus one for the refused restart — seven messages in ~45 s for `StartLimitBurst=5`. Phase
   12 saw the same shape on the bot. Recorded for the guide; not changed (a rate limit on alerts is a
   Phase 12/notifier concern, not this unit's).
3. **The bot's `/status` has no volume line.** The brief's row 12 expected "bot `/status` reports
   locked"; the reply is host/uptime/load/memory/disk. The watchdog's boot notice *does* say
   `Data volume: LOCKED`. Brief corrected (`2673d25`); `data-volume.sh status` is the check.
4. **`StateDirectory=` adds `RequiresMountsFor=/var/lib/homelab-harness`** — a root path. The S1
   prediction "empty" was wrong; the installer's first version asserted it and failed. Corrected to
   "nothing under `/srv/homelab`" (`a69c922`). The unit is not volume-dependent; row 12 proves it.
5. **`StartLimitBurst=5` allows five restarts** — the limit hits on the sixth. The runbook said five
   kills; it took six. Corrected (`07764cc`).
6. **Same-day `.bak` collision.** Phase 15.0's S2 ran the same morning; `config.json.bak-2026-09-13`
   already existed and the edit refused, correctly, and changed nothing. Suffix `-p230` used. The
   date-only convention assumes one phase per day.
7. **Paste-wrapping and wrong-host pastes cost three retries** (a heredoc that never terminated; long
   `curl -d` lines split into two commands; two blocks run on the MacBook after the SSH session
   dropped). No call was spent by any of them. Step 6 became a script (`s2-step6.sh`); the post-boot
   block gained a hostname guard. Lesson for the runbook template: anything longer than a terminal
   width ships as a file, and every block that follows a reconnect checks `hostname` first.
8. **`systemd-run --uid=homelab-bot` picks up supplementary groups** (S1 PREDICTED item 7) — the bot
   probe passed after the group change with no `SupplementaryGroups=`.
9. **Two `systemd-analyze verify` warnings** about `CPUAccounting=` in vendor xfs units — Ubuntu's,
   not ours; noise.

## 4. ADR-048 — evidence for acceptance

Rows 10, 14 and 18 OBSERVED (above). The group is the boundary: `nobody` refused with `EACCES`, the
harness reaches the socket from inside its sandbox (`/health/helper`), the bot's `/ask` works after
the change and after a reboot, the 15.0 fixture is 19/19. The ADR can move to **Accepted** at S4.

## 5. State for S3

- The endpoint is live on `127.0.0.1:8766` with route `execution-agent`; `/health/helper` reachable.
- The Claude allowance may still be exhausted for some hours; S3's real call (row 17) will likely be
  answered by Codex. That is the fallback working, not a failure — but if **both** report
  `exhausted`, row 17 waits for the caps, it does not get a retry loop.
- Audit file so far: 9 lines from step 6 + 1 from step 8 (the wrapped-JSON `bad_request`) + the
  fixture's lines are in the fixture's own temp dir, not here.
- MacBook shell for S3's `scp`s must be in `homelab-p230` (the last prompt showed `homelab-p150`).
