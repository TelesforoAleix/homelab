# Phase 13.1 — Agent operator access

> **Phase in progress.** S1 (files, local proof) landed 2026-09-13; S2 (the node) is next. Every
> line below is PREDICTED until the S2 runbook's row says otherwise.

Brief: [`docs/handovers/13.1-agent-operator-access.md`](../../docs/handovers/13.1-agent-operator-access.md).
Decision: [ADR-049](../../docs/decisions/ADR-049-agent-operator-access.md). Runbook:
[`s2-runbook.md`](s2-runbook.md). Installer: [`scripts/server/install-homelab-agent.sh`](../../scripts/server/install-homelab-agent.sh).
The grant: [`config/sudoers.d/homelab-agent`](../../config/sudoers.d/homelab-agent).

## What this phase is for, in one paragraph

Since Phase 12 the owner has run every node command and pasted the output back to the executor.
That was right while changes were boot-class. By Phase 15.1 a runbook is fifty commands of which
four need `sudo`, none is lockout-class, and the owner's job has become copying between two
windows. This phase gives the executor its own way onto the node — an account, a key, an alias, a
closed `NOPASSWD` list — so that it runs and reads the routine steps itself, and the owner does only
what needs a password, a secret, a browser, a phone, or a lockout-class change. **It is the last
phase run by paste; its final row is the executor running three commands itself.**

## What the account may do (as root, no password)

| It may | Bound to |
|---|---|
| `systemctl start / stop / restart / reset-failed / is-active / is-enabled / show / status / cat` | seven named units: `homelab-telegram-bot.service`, `homelab-model-helper.socket`, `homelab-harness.service`, `homelab-workbench.service`, `homelab-watchdog.timer`, `homelab-watchdog.service`, `homelab-data.target`; plus `daemon-reload` |
| `systemctl list-units / list-timers / --failed / is-system-running`, `journalctl`, `ss -tlnp`, `systemd-analyze security / verify`, `stat`, `ls`, `getent`, `id` | read, any arguments |
| `cat` | `/etc/homelab-model-helper/config.json`, `/etc/homelab-harness/config.json` — exactly those |
| `install -m 644 -o root -g root <src> <dst>` | `/tmp/homelab-agent/model-helper-config.json` → the helper's `config.json`; `/tmp/homelab-agent/harness-config.json` → the harness's |
| `cp -p`, `mv` | `spend.json` / `calls.json` ↔ their `.bak`, inside `/var/lib/homelab-model-helper/` |
| `/usr/local/sbin/data-volume.sh status` | read; `lock`/`unlock` denied |

**The file is a list, not a pattern.** The node runs sudo-rs, which matches a command's arguments
exactly, token by token; its only wildcard is a lone trailing `*` ("any arguments"). OBSERVED
2026-09-13 at S2 step 1: the first draft, written in C-sudo idiom (`systemctl restart homelab-*`,
`cat /etc/homelab-*/*.json`), was refused by the node's `visudo` — *"wildcards are not allowed in
command arguments"* — before it landed, which is what the installer is built to do; the MacBook's
C-sudo `visudo` had said `parsed OK` to the same file. A new unit or config file is a new line,
`visudo`'d and committed: the right amount of friction for widening a root grant.

## What it may never do — the line (ADR-049 §3)

- **Lock the owner out**: `sshd`, `ufw`, `iptables`/`nft`, `tailscale`, `netplan`, `visudo`,
  `usermod`/`useradd`/`passwd`, `reboot`/`shutdown`, `systemctl reboot|isolate|rescue|edit|…`,
  `apt`/`dpkg`/`snap`, `cryptsetup`, `systemd-creds`.
- **Read or write a secret**: `gateway-key`, `token.cred`, the two OAuth files, the GitHub key,
  `/etc/shadow`, `getent shadow` — each named; and every other path, by not being on the list.
- **Touch the volume's lock state**: `data-volume.sh lock|unlock`.
- **Change its own grant**: sudoers is owner-only, with a password, through `visudo`.

Every one of these is a **named deny line**, not just an omission, so the intent survives a later
edit and `sudo -l` shows the boundary as well as the grant. Under exact matching the denies are
documentation with one working exception: `getent shadow` sits inside `getent *`, and the deny,
listed last, wins.

**For the record — the C-sudo hazard this file was first written against.** In C sudo `*` matches
a space, so `cat /etc/homelab-*/*.json` would also admit `cat a.json /etc/shadow b.json`, and
`cp -p /var/lib/x/* /var/lib/x/*` would admit `-t /tmp/anywhere`. That is learning objective 3.1,
and it is why the first draft carried deny lines for a third argument, a later option and `..`.
sudo-rs made them unnecessary and unparseable at once. If this node ever runs C sudo, they come back.

**A property the project maintains, not one sudoers enforces:** `journalctl` is unscoped because
the journal holds no secret by the project's own rules (Phase 13's audit; 15.1's type/code-only
logging). If a future unit logs a secret, that unit is the defect.

## `sudo -l -U homelab-agent` — the ground truth

PREDICTED until S2 row 4. Paste the node's output here verbatim at every phase close that touches
the file.

```text
(row 4 output goes here)
```

## The runbook convention: AGENT and OWNER

From this phase on a runbook has two blocks with a fixed vocabulary (ADR-049 §4):

- **AGENT** — run by the executor over `ssh homelab-agent`; it captures and reads its own output and
  reports it OBSERVED. The default for every step.
- **OWNER** — the owner at the keyboard: anything with a password (`aleix`'s `sudo`), the credential
  editor, the browser (Vercel, GitHub, Tailscale, BIOS), the phone (Telegram), and every
  lockout-class change under `safe-changes-headless.md`. The executor says when it is the owner's
  turn and stops.

One worked example — replacing the helper's config to lower a ceiling:

```text
AGENT   ssh homelab-agent 'mkdir -p /tmp/homelab-agent'
AGENT   scp config/model-helper/config.example.json homelab-agent:/tmp/homelab-agent/model-helper-config.json
AGENT   ssh homelab-agent 'sudo -n install -m 644 -o root -g root /tmp/homelab-agent/model-helper-config.json /etc/homelab-model-helper/config.json'
AGENT   ssh homelab-agent 'sudo -n systemctl restart homelab-model-helper.socket && sudo -n journalctl -u homelab-model-helper@* -n 5 --no-pager'
OWNER   (nothing — no password, no secret, no lockout-class file was touched)
```

The executor never asks the owner to run something the AGENT block could run, and never asks for a
password. The print-before-wait rule is for the OWNER block; the AGENT block has no prompt to hide.

## The money path — stated, not hidden

The agent can replace `config.json` for the model helper. That is a path through the governor's
ceilings (Phase 15.1): a mistaken or malicious config can raise them. The backstop is the gateway's
own per-key budget ($10/week, ADR-033 §5), which the agent cannot touch — it cannot read or write
`gateway-key`. This is by design (that is how a runbook lowers a ceiling) and it is the reason the
gateway budget must stay set.

## Key inventory and revocation

| Where | What | Revoke by |
|---|---|---|
| MacBook `~/.ssh/id_ed25519_homelab_agent` | passphrase-less Ed25519, `0600`, **not** in the backup | delete the node's `authorized_keys` line — the key is then worthless |
| Node `/home/homelab-agent/.ssh/authorized_keys` | the one public line (in the backup; public) | `sudo bash install-homelab-agent.sh uninstall` removes sudoers first, then the account |
| Node `/etc/sudoers.d/homelab-agent` | the grant, `root:root 0440` (in the backup; committed) | `rm` from a root shell; `visudo -c` after |
| Node sshd `AllowUsers aleix homelab-agent` | the door | OWNER, lockout-class: edit, `sshd -t`, reload, third connection |

Not in ADR-046's table on purpose: the key is on the MacBook, not on root (brief §6.5).

## Two things worth knowing

- **Root pager.** `sudo systemctl status` and `sudo journalctl` on a tty open `less` as root, and
  `less` has shell escapes. systemd sets `LESSSECURE=1` whenever `SUDO_UID` is set (escapes off), and
  the `homelab-agent` alias says `RequestTTY no` so the executor path never has a pager at all.
  PREDICTED; owner check: `ssh -t homelab-agent sudo -n systemctl status homelab-harness`, then
  `!id` inside `less` → "Command not available".
- **Two parsers.** The node runs `sudo-rs`; the MacBook's `visudo` is C sudo, and it accepts
  things sudo-rs refuses (see above). The local `visudo -c -f` is a syntax check; the node's own,
  inside `install` before the file lands, is the gate — and it fired.

## Status by row

| Row | State |
|---|---|
| 1–16 | PREDICTED — S2 |
