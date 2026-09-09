# Build Log — Phase 02 Parts C–D: tooling, and practising the write side safely

- **Date:** 2026-09-09
- **Phase:** 02 — Linux Fundamentals
- **Branch:** `feature/02-linux-fundamentals`
- **Status:** Complete

## Starting state

Parts A–B complete: the safe-change standard and ADR-020 accepted, `preflight.sh` and
`lab-sandbox.sh` written, Tier 1 exercises run and captured. Node healthy, no console, one human
user, `tree`/`ncdu`/`ripgrep` absent.

## Objective

Install the small justified toolset, prove the sandbox script's guard rails by trying to break them,
run the Tier 2 exercises — the write side of users, groups, permissions and units — and remove every
trace of the sandbox afterwards.

## Actions taken

1. **Installed `tree` 2.3.1-1, `ncdu` 1.22-1build1, `ripgrep` 15.1.0-1ubuntu1** from Ubuntu's
   `universe` component. `apt` reported no services needing restart and no outdated binaries in use.

2. **Tested the creation guards before creating anything.** All three attempts refused:

   ```text
   REFUSED: 'aleix' is a real account. This script never touches it.
   REFUSED: 'root' is a real account. This script never touches it.
   REFUSED: 'daemon' already exists (uid 1). This script only creates new accounts.
   ```

3. **Created the sandbox**: `labgroup` (gid 1001), `labuser` (uid 1001, no password, `nologin`
   shell), `/srv/lab` at `drwxrws--- labuser:labgroup`, and `homelab-lab.service`.

4. **Ran the Tier 2 exercises** from a throwaway transcript runner, transferred by `scp` with SHA256
   verified on both sides. The runner is deliberately **not** a repository artifact: the guide lists
   these commands for a human to type, and running them from a script would defeat the point of a
   learning phase. Only its output is kept.

5. **Tore the sandbox down** and proved its absence four different ways.

## Validation

| Check | Result |
|---|---|
| Tooling installed | `tree v2.3.1`, `ncdu 1.22`, `ripgrep 15.1.0` |
| Creation guards (check 8) | All three refusals fired, quoted above |
| **setgid demonstrated** | Root-created file: group `labgroup` inside `/srv/lab`, group `root` in `/tmp` — same command, two seconds apart, different groups |
| Group vs ownership | Two owners (`labuser`, `root`), one shared group |
| `Type=oneshot` semantics | `is-active` → `inactive`, `Deactivated successfully`, log line written. Success, not failure |
| Unit cannot be enabled | `Loaded: … ; static` — systemd confirming there is no `[Install]` section |
| Deliberate breakage | `status=203/EXEC`, `Unable to locate executable`, `Drop-In:` named `break.conf` |
| Failed unit visible | `systemctl --failed` listed it |
| Recovery | Drop-in removed, `reset-failed`, restarted, `systemctl --failed` → 0 |
| **Teardown guard (check 8b)** | Refused a tampered account **and removed nothing** — unit and `/srv/lab` both still present afterwards |
| Teardown (check 9) | `status` → all absent; `getent passwd labuser` exit 2; `getent group labgroup` exit 2; `/srv/lab` gone; 0 failed units |

## Problems / failed approaches

### 1. The teardown guard fired after the first destructive step

`do_teardown` removed the systemd unit first — correct in itself, since you should never delete a
user a service is still running as — and only then called `guard_delete`. A refusal therefore left
the sandbox half dismantled.

Found by **reading the teardown path before running the guard test**, not by the test. Fixed by
validating up front and recording whether there is a user to remove, then acting:

```bash
USER_REMOVABLE=0
if guard_delete "$LAB_USER"; then USER_REMOVABLE=1; fi
# reaching this line at all means "safe to proceed"
```

The guard test was then extended to check that the unit file and `/srv/lab` still exist *after* the
refusal — which is what makes it a test of the fix rather than a restatement of it. Both were
present.

**A guard that fires after the first destructive step is not a guard, it is a report.** That is the
same category of error as Phase 03's apply script, which ran correctly and still left the system
wrong because it validated the file instead of the server.

### 2. `daemon` did not exercise the guard it was chosen for

`LAB_USER=daemon` was meant to test the UID-below-1000 branch. It was refused earlier, by the
"already exists" check. The refusal is correct and the account is safe, but the low-UID branch was
not the one that fired.

### 3. The sudo-group guard is unreachable on this machine, and is recorded as untested

`guard_create` and `guard_delete` both refuse members of the `sudo` group. `aleix` is the only sudo
member on this node, and the by-name check fires first — so the sudo-group branch cannot be reached
without either adding a second sudoer or temporarily putting the sandbox user into `sudo`. Both are
authentication-class changes on a console-less machine, which ADR-020 says not to make casually for
a convenience.

**This branch is therefore untested, and is written down as untested rather than counted as passing.**
The equivalent delete-side protection — the marker check — was tested and works.

## What we learned

- **`status=203/EXEC` is worth memorising.** systemd's exit codes distinguish "could not execute the
  binary" (203) from "the program ran and failed" (1) and "sandboxing blocked it" (226/NAMESPACE).
  The number tells you which half of the problem you have before you read a single log line.
- **`Drop-In:` in `systemctl status` names the file that modified a unit.** That is how you discover
  a change someone else made.
- **An empty `ExecStart=` resets the list.** systemd list-valued directives append by default, so
  omitting the reset gives you both commands rather than a replacement.
- **`reset-failed` is part of fixing, not tidying.** A repaired unit stays on `systemctl --failed`
  until it succeeds or is cleared — exactly the way Phase 01's machine hid being degraded.
- **`Loaded: … ; static`** is systemd confirming a unit has no `[Install]` section. The sandbox's
  "cannot run at boot" property was verified by the system rather than trusted from the script.
- Testing a guard means checking **what was not destroyed**, not just that an error was printed.

## Decisions / ADRs

No new ADR. ADR-020 governs this work; the sandbox design is
[ADR-011](../decisions/ADR-011-privilege-separation.md) applied at small scale — an unprivileged
account with no password, no shell, no `sudo` and no key.

Baseline shell tooling was deliberately **not** given an ADR; three packages with stated reasons are
recorded in `docs/reference/software-stack.md`.

## Costs

**None.** All three packages come from Ubuntu's own repositories. Total download 1,671 kB.

## Next

Close the phase: project documentation, the handover to Phase 04, and the Definition of Done applied
item by item.
