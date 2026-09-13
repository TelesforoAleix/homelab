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
| `systemctl start / stop / restart / reset-failed / is-active / is-enabled / show / status / cat` | `homelab-*` units only, one unit per call; `daemon-reload` |
| `systemctl list-units / list-timers / --failed / is-system-running`, `journalctl`, `ss -tlnp`, `systemd-analyze security / verify`, `stat`, `ls`, `getent`, `id` | read |
| `cat` | `/etc/homelab-*/*.json` only, one file per call |
| `install -m 644 -o root -g root <src> <dst>` | `src` under `/tmp/homelab-*/`, `dst` a `.json` under `/etc/homelab-*/` |
| `cp -p`, `mv` | both paths inside `/var/lib/homelab-model-helper/` |
| `/usr/local/sbin/data-volume.sh status` | read; `lock`/`unlock` denied |

## What it may never do — the line (ADR-049 §3)

- **Lock the owner out**: `sshd`, `ufw`, `iptables`/`nft`, `tailscale`, `netplan`, `visudo`,
  `usermod`/`useradd`/`passwd`, `reboot`/`shutdown`, `systemctl reboot|isolate|rescue|…`,
  `apt`/`dpkg`/`snap`, and any `install` to `/etc/ssh/`, `/etc/sudoers*`, `/etc/ufw/`.
- **Read or write a secret**: any `cat`/`cp`/`mv`/`install` whose arguments contain `key`, `token`,
  `.cred`, `secret`, `credentials` or `shadow`, anything under `/home/aleix/` or `/root/`,
  `getent shadow`, `systemd-creds`.
- **Touch the volume's lock state**: `data-volume.sh lock|unlock`, `cryptsetup`.
- **Change its own grant**: sudoers is owner-only, with a password, through `visudo`.

Every one of these is a **named deny line**, not just an omission, so the intent survives a later
edit; and every allow that names two paths has a matching deny for a third argument, a later option
(`-t DIR`), and `..` — because sudoers matches arguments as one space-joined string and `*` matches
a space. Read the header of the sudoers file for the worked example; it is learning objective 3.1.

**A property the project maintains, not one sudoers enforces:** `journalctl` is unscoped because
unit-scoped globs are fragile and the journal holds no secret by the project's own rules (Phase 13's
audit; 15.1's type/code-only logging). If a future unit logs a secret, that unit is the defect.

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
AGENT   scp config/model-helper/config.example.json homelab-agent:/tmp/homelab-agent/config.json
AGENT   ssh homelab-agent 'sudo -n install -m 644 -o root -g root /tmp/homelab-agent/config.json /etc/homelab-model-helper/config.json'
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
- **Two parsers.** The node runs `sudo-rs`; the MacBook's `visudo` is C sudo. The file uses only
  the subset both accept (aliases, `NOPASSWD`, `!`, `*`). The local `visudo -c -f` is a syntax
  check; the node's own, inside `install` before the file lands, is the gate.

## Status by row

| Row | State |
|---|---|
| 1–16 | PREDICTED — S2 |
