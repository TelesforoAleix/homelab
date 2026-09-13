# ADR-048: The model socket's consumers are a group

- **Status:** Accepted 2026-09-13 (Phase 23.0 S4). Validation rows 10, 14 and 18 of the 23.0 brief OBSERVED on the node 2026-09-13: `getent group homelab-model` = `homelab-bot,homelab-harness`; `/ask` answered before the change, after the socket and bot restart, and after a locked reboot, with the 15.0 fixture 19/19; `sudo -u nobody` probing the socket → `PermissionError errno=13`. Proposed the same day at S1.
- **Date:** 2026-09-13
- **Supersedes:** none. Amends the access-control paragraph of ADR-025 (the socket's group is no longer the bot's own group); ADR-025's principle — access is the socket unit, not code — is unchanged.
- **Superseded by:** none

## Context

Phase 09 built the model helper as a UNIX socket, `/run/homelab-model-helper.sock`, whose
access control is the socket inode: `aleix:homelab-bot:0660`, set by `SocketUser=`/`SocketGroup=`
/`SocketMode=` in a committed unit file, so the kernel refuses `connect(2)` to anyone who is neither
`aleix` nor the bot (ADR-025). The design point, stated in the socket unit's header, was that
**the bot was not added to any group** — the socket was given the group the bot already had, and
`id homelab-bot` unchanged was a Definition-of-Done item.

That worked because there was one consumer. Phase 23.0 adds a second: the harness, the endpoint
that forwards `question`-class requests from local clients to the helper. Per ADR-047 and the
service-security baseline §3, the harness runs as **its own account**, `homelab-harness` — never
`aleix`, never `homelab-bot`. It therefore cannot connect to the socket as it stands. The Phase
15.0 handover foresaw this and set the rule: *"if 23.0 needs the helper, that is a socket-unit
decision with its own ADR, not a `usermod`"*.

## Decision

**The socket's group becomes a dedicated system group, `homelab-model`, whose one meaning is
"may ask the model helper". Every consumer is a member; the socket stays `0660`.**

Concretely, in `config/systemd/homelab-model-helper.socket`:

```ini
SocketUser=aleix
SocketGroup=homelab-model      # was homelab-bot
SocketMode=0660
```

and on the node: `groupadd --system homelab-model`; `usermod -aG homelab-model homelab-bot`;
the harness account is created with `--groups homelab-model`. `getent group homelab-model` is the
access list and reads exactly `homelab-bot,homelab-harness`.

What this keeps:

- **Access is a committed line plus a group, not code** (ADR-025). The helper still performs no
  caller check; the kernel does.
- **The Phase 09 property that the caller cannot name a program.** The wire protocol is untouched;
  a new consumer gains the ability to ask a routed question and nothing else.
- **Each consumer keeps its own account and its own trust boundary.** The bot is still `homelab-bot`
  with no AI credential; the harness is `homelab-harness` with no credential at all.

What this changes:

- `id homelab-bot` now shows two groups, `homelab-bot homelab-model`. The Phase 09 DoD item
  "unchanged" is superseded by this ADR's "exactly its own group plus `homelab-model`", which
  `install-model-helper.sh verify` checks as an exact set, not a superset.
- The bot's running process must be **restarted** after the `usermod`: supplementary groups are
  fixed at `exec`, so a bot started before the membership existed gets `EACCES` on its next `/ask`.
  `install-model-helper.sh group` does the restart; the 23.0 brief's S2 order was corrected to say so.
- The next consumer is a group membership with a `# WHY` in its unit and a row in
  `services/model-helper/README.md`'s consumers table — not a new mechanism and not a new ADR.

## Alternatives considered

1. **Run the harness as `homelab-bot`.** Rejected by the 23.0 brief §5 and the baseline §3: one
   account for two trust boundaries. The watchdog's reuse of `homelab-bot` is a named exception for a
   unit that *sends* alerts; a unit that *accepts requests* from other processes is a different
   boundary and gets its own account.
2. **Add `homelab-harness` to the `homelab-bot` group.** A `usermod` that makes a group mean two
   things — "is the bot" and "may ask the helper". The next reader of `getent group homelab-bot`
   cannot tell which members are there for which reason, and the bot's own files (`0640`, group
   `homelab-bot`) become readable by the harness. Forbidden by the 15.0 handover for exactly this
   reason.
3. **A second socket for the harness** (`/run/homelab-model-helper-harness.sock`, group
   `homelab-harness`). Keeps groups single-purpose without a new group, but doubles the socket units,
   the `MaxConnections` budget and the install/verify surface, and the two sockets would drive the
   same template unit with the same caps — two doors into one room. A group is the smaller change.
4. **`SupplementaryGroups=homelab-model` in each consumer's unit** instead of `/etc/group`
   membership. Attractive because it is declarative in the committed unit. Rejected for 23.0
   because `getent group` would then *not* be the access list — membership would be split between
   `/etc/group` and unit files, and the 23.0 brief's test 10 reads `getent group`. Revisit if a
   consumer ever needs the membership only while its unit runs.
5. **A filesystem ACL on the socket** (`setfacl -m u:homelab-harness:rw`). Not expressible in the
   socket unit; would have to be applied after every socket restart (the inode is re-created) by a
   hook that is itself code. Rejected.

## Consequences

- **Easier:** adding a consumer is one membership and one `# WHY`; the access list is one command.
- **Widened:** the helper's consumers grow from one account to two. The helper's per-provider caps
  are now a **shared budget** — the endpoint's calls count against the same `per_hour`/`per_day` as
  the owner's `/ask`. This is why the 23.0 brief §6.7 keeps the bot's `/ask` independent of the
  endpoint for now, and why the caps are the only budget until a governor exists (ADR-033 §5).
- **The group is a boundary only as strong as its membership.** A stray `usermod -aG homelab-model`
  is the failure mode; `install-model-helper.sh verify` and `install-homelab-harness.sh verify` both
  check the membership as an exact set, and the 23.0 handover lists this as an open risk not to be
  inherited silently.
- **Unchanged:** the Workbench cannot reach the socket (no `AF_UNIX` in its unit, ADR-047), and
  `aleix` can (socket owner) — neither is affected by the group.

## Validation / revisit trigger

Validation, from the 23.0 brief §8 — all three OBSERVED on the node 2026-09-13 (S2), which is what moved this ADR to Accepted:

- Row 10: `id homelab-harness` shows no `aleix`, `docker`, `sudo`; `getent group homelab-model`
  = `homelab-bot,homelab-harness`.
- Row 14: `/ask` from Telegram works before and after the change; the 15.0 fixture is still 19/19.
- Row 18: `sudo -u nobody` probing the socket is refused with `EACCES` — the group is the boundary.
- `install-homelab-harness.sh verify`'s `GET /health/helper` reaches the helper **as the harness
  account, inside its sandbox**, with `op: ping` (no model call).

Revisit if: a consumer needs membership only while running (alternative 4); a consumer must be
prevented from reaching a *subset* of routes (the group cannot express that — that is a helper
change, or 23.3's identity machinery); or the count of consumers passes three, at which point the
shared caps stop being a budget anyone can reason about and ADR-033 §5's governor is overdue.
