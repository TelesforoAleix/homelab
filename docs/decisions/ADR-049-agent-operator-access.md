# ADR-049: Agents operate the node through their own account with a bounded, passwordless command set

- **Status:** Proposed (Phase 13.1 brief, 2026-09-13); accepted by the orchestrator when Phase
  13.1's validation rows are OBSERVED
- **Date:** 2026-09-13
- **Supersedes:** none. Refines ADR-040 (autonomous operation is normal) and ADR-041 (the console
  is the recovery path) for the case of an *executor agent on the MacBook* operating the node;
  extends ADR-047's one-account-per-trust-boundary rule to the operator side.
- **Superseded by:** none

## Context

Since Phase 12 every phase has run as a three-role workflow: an executor agent implements and
writes runbooks, the **owner runs every command on the node and pastes the output back**, the
orchestrator reviews. That was right while the changes were boot-class — LUKS, sshd, the firewall,
BIOS — because a human read every line before it ran.

By Phase 15.1 the shape of the work has changed. A governor-proof runbook is fifty commands of
which four need `sudo`, none is lockout-class, and the owner's role has become copying output
between two windows. The cost is real: 15.1's S2 runbook alone was several hundred lines pasted
by hand, and the Codex executor burned its usage window mostly on re-reading its own context
while waiting for pastes.

The executor already has everything it needs to run the unprivileged half itself: it runs on the
MacBook, `ssh homelab` works, and nothing in `AGENTS.md` forbids it. What it cannot do is type the
owner's `sudo` password — and it must never be able to, because a password in an agent's context
is a password in a transcript (Phase 13's own incident).

Two things must therefore be true at once: the executor can run the routine privileged steps
without a password, **and** what it can do as root is bounded, auditable, and cannot lock the owner
out or spend beyond the governor.

## Decision

### 1. Agents get their own account, never the owner's

A system account **`homelab-agent`** exists on the node for executor agents: no password, shell
`/bin/bash`, home `/home/homelab-agent`, member of **no** group but its own — not `sudo`, not
`docker`, not `homelab-model`, not `aleix`. It is reached by its own Ed25519 key held on the
MacBook (`~/.ssh/id_ed25519_homelab_agent`) and its own alias, **`ssh homelab-agent`**. The
`homelab` and `homelab-workbench` aliases remain the owner's, unchanged.

The reason is the audit trail and the blast radius. Passwordless `sudo` on `aleix` would make an
agent session indistinguishable from the owner in every log, and would give anyone holding the
MacBook those root commands under the owner's name. A separate account means `journalctl _UID=`
and `sudo`'s log say *who* — and revoking the agent is deleting one key line.

### 2. What the account may run as root is a closed list, `NOPASSWD`, in one file

`/etc/sudoers.d/homelab-agent`, validated with `visudo -c -f` before it lands, containing exactly
one `Cmnd_Alias` block. The list is the **routine operator set** — start, stop, restart, inspect,
and replace configuration files of the project's own services:

| Allowed | Bound to |
|---|---|
| `systemctl {start,stop,restart,reset-failed,is-active,is-enabled,show,status,cat} homelab-*` | the project's units only, by glob; `daemon-reload` unqualified |
| `systemctl list-units`, `list-timers`, `--failed`, `is-system-running` | read |
| `journalctl *` | read |
| `ss -tlnp`, `systemd-analyze security *`, `systemd-analyze verify *`, `stat *`, `ls *`, `cat /etc/homelab-*/*.json`, `getent *`, `id *` | read; **`cat` is denied on any path containing `key`, `token`, `.cred` or `secret`** by an explicit `!` line before the allow |
| `install -m 600 -o root -g root /tmp/homelab-*/* /etc/homelab-<service>/<name>.json` | configuration files only, `.json` only, from the agent's staging directory only |
| `cp`, `mv` **within** `/var/lib/homelab-model-helper/` | ledgers and their `.bak` copies |
| `/usr/local/sbin/data-volume.sh status` | read; `lock`/`unlock` are **not** allowed |

Everything else is denied by omission, and these are denied **by explicit `!` lines** so the
intent survives a later edit: `sshd`, `sshd -t`, `ufw`, `iptables`, `ip6tables`, `nft`,
`tailscale`, `netplan`, `visudo`, anything under `/etc/sudoers*`, `/etc/ssh/*`, `/etc/ufw/*`,
`cryptsetup`, `data-volume.sh lock|unlock`, `usermod`, `useradd`, `passwd`, `chpasswd`, `apt*`,
`dpkg`, `snap`, `reboot`, `shutdown`, `systemctl {reboot,poweroff,halt,kexec,isolate,rescue}`,
`systemd-creds`, `install` to any path that is not a `.json` under `/etc/homelab-*/`, and any
`cat`/`install`/`cp` touching a credential file.

### 3. The line the list does not cross, stated so a later edit cannot move it silently

The agent must never be able to, as root or otherwise:

- **lock the owner out** — nothing in `safe-changes-headless.md`'s lockout classes (sshd, ufw,
  Tailscale, netplan, sudoers, fstab, boot);
- **read or write a secret** — no credential file, no `$CREDENTIALS_DIRECTORY`, no `systemd-creds`,
  no `~aleix`;
- **open, close or alter the volume** — `data-volume.sh` is read-only for it; ADR-046 §3 stands;
- **spend outside the governor** — it can replace `config.json` (that is how a runbook lowers a
  ceiling), so the gateway's own per-key budget is the backstop for a malicious or mistaken
  config, exactly as ADR-033 §5 intends; it cannot touch the key itself;
- **change its own grant** — sudoers is owner-only, with a password, via `visudo`.

A future phase that needs the agent to do one of these is not extending this list. It is
superseding this ADR.

### 4. The runbook convention changes accordingly

From Phase 13.1 on, a runbook has two blocks with a fixed vocabulary:

- **AGENT** — run by the executor over `ssh homelab-agent`; the executor captures and reads its
  own output and reports it OBSERVED. This is the default for every step.
- **OWNER** — the owner at the keyboard: anything with a password (`aleix`'s `sudo`), the
  credential editor step, the browser (Vercel, GitHub, Tailscale, BIOS), the phone (Telegram),
  and every lockout-class change under `safe-changes-headless.md`. The executor tells the owner
  when it is their turn and stops.

The executor never asks the owner to run something the AGENT block could run, and never asks
for a password.

### 5. The account is in the audit trail and the backup, and is revocable in one line

`sudo` logs every invocation with the account name; `journalctl _UID=<homelab-agent>` shows its
sessions. `backup-node.sh` collects `/etc/sudoers.d/homelab-agent` and
`/home/homelab-agent/.ssh/authorized_keys` (a public key — not secret). Revocation: delete the
`authorized_keys` line, or `userdel`; the MacBook's private key is excluded from the backup like
the GitHub key.

## Alternatives considered

**Passwordless `sudo` for `aleix`, narrow list.** Rejected: §1 — no audit distinction between
owner and agent, and the grant travels with the owner's key.

**Passwordless `sudo` for `aleix`, everything.** Rejected outright: it converts a stolen MacBook
session into root on the node with no password, and it makes ADR-041's "second idle session" a
fiction — the agent could lock out the owner in the same session that is meant to be the fallback.

**The agent keeps pasting; nothing changes.** Rejected on cost: the workflow spends the owner's
evenings and the executor's usage windows on copying, and the paste step is where transcription
errors enter (15.1 S2: a wrapped paste, a `# T` line executed by `zsh`).

**A privileged Telegram command set for the agent** (`/restart` already exists for the owner).
Rejected: the bot's allowlist is by Telegram user id, an agent has none, and the bot's privileged
set is deliberately tiny (ADR-024). The right tool for a fifty-command runbook is a shell.

**Tailscale SSH with ACL-scoped users.** Declined in ADR-019 and again in Phase 13 §6.7; would
re-open authentication design for a problem `sudoers.d` solves in one file.

## Consequences

- The owner's remaining node work per phase drops to: passwords, credential pastes, browser,
  phone, and lockout-class steps. Everything else the executor does and reads itself.
- A new account, key and sudoers file on the node — three more items in the Phase 13 audit set,
  added to the baseline's checklist and the backup.
- The agent can replace `config.json` for `homelab-*` services. **That is a money path** through
  the governor's ceilings; the gateway's per-key budget is the stated backstop, and the guide says
  so.
- `sudo -l -U homelab-agent` is the ground truth of what the agent may do; it is pasted into the
  guide at every phase close that touches the file.
- ADR-047's "two exceptions" language is unchanged: `homelab-agent` is an operator account, not a
  service account, and runs no unit.

## Validation / revisit trigger

**The check that this decision is holding**, run at any phase close:

1. `sudo -l -U homelab-agent` matches the list in §2 exactly — no line added, none removed.
2. `sudo -u homelab-agent sudo -n sshd -t` → `a password is required` (or explicit deny); the
   same for `ufw status`, `data-volume.sh lock`, `cat /etc/homelab-model-helper/gateway-key`,
   `visudo -c`.
3. `id homelab-agent` → no `sudo`, `docker`, `homelab-model`, `aleix`.
4. `visudo -c -f /etc/sudoers.d/homelab-agent` → parsed OK.

**Revisit if:**

1. A phase needs the agent to do anything in §3 — that is a superseding ADR, not an edit.
2. The agent account is used by anything other than an executor agent on the owner's MacBook
   (a second machine, a scheduler, a CI runner) — the trust model changes.
3. `safe-changes-headless.md`'s lockout classes change; §2's deny lines follow them.
4. The machine leaves the home (ADR-032 trigger 3).
