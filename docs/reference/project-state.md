# Current Project State

- **Project:** Home Lab
- **Governance:** Self-contained sequential phases; the repository is the sole authority (ADR-017)
- **Current phase:** 09 — Model Executor, subscription-backed (**complete**, 2026-09-09). Next:
  **Phase 18 — Foundations** (backup plus the ADR-015 encryption decision plus an SSH recovery
  path), then Phase 15.0 (generalise the model router), the repository split, and Phase 10
  (Knowledge). Voice was **moved out of Phase 09 to Phase 17** at the owner's request; the roadmap
  records the reason rather than being quietly rewritten.
- **Architecture decisions taken 2026-09-10**, ahead of Phase 18 and carried into its brief per
  ADR-017: ADR-026 (multi-provider model access), ADR-027 (the agent contract), ADR-028 (the project
  contract) and ADR-029 (repository topology). These define how this repository — the **AI OS** —
  relates to a separate public `factory` repository holding agent, skill and workflow definitions,
  and to private repositories holding knowledge and products. No implementation has been done
  against them yet.
- **Repository:** [`github.com/TelesforoAleix/homelab`](https://github.com/TelesforoAleix/homelab) —
  **public** since 2026-09-09 (ADR-021). MIT for code, CC BY-SA 4.0 for documentation.
- **Reference node:** Lenovo ThinkCentre M700 Tiny
- **Target OS:** Ubuntu Server 26.04.1 LTS (ADR-014)
- **Current implementation state:** Ubuntu Server 26.04.1 LTS on the reference node, administered
  entirely remotely. `ssh homelab` reaches it over Tailscale by MagicDNS name, authenticated by an
  Ed25519 key; passwords, keyboard-interactive and root login are all refused. VS Code Remote SSH
  works. Docker Engine and Compose are installed, with no persistent containers running. Claude Code
  and Codex are installed as interactive `aleix`-scoped tools and authenticated through existing
  subscriptions; neither is a service. **The node now runs its first service**: a read-only Telegram
  status bot as the unprivileged `homelab-bot` account, long-polling so it opens **no listening
  socket**. **The monitor and keyboard have been physically removed** — the node is genuinely
  headless and cold-boots to a reachable state in 24.4s.

## Phase 01 status

| Item | State |
|---|---|
| Phase 01 brief | **Ratified** by Project Planning 2026-09-08 with six amendments, all reconciled (`docs/handovers/01-ubuntu-server.md` §0.1) |
| Guide | ✅ Complete (`guide/01-ubuntu-server/README.md`), including reference-build experience and tested versions — filled in by performing the install, which corrected it five times |
| Scripts | Written and syntax-checked; USB writer safety guards tested |
| ADR-014 / 015 / 016 | **Accepted**, all amended 2026-09-08 per ratification |
| Phase 00 hardware prerequisite | ✅ **Closed** 2026-09-08 — identification and physical validation both complete |
| Installation on hardware | ✅ **Complete** 2026-09-08 |
| Validation | ✅ **Passed**, including unattended power-loss recovery |
| Handover | ✅ [`01-ubuntu-server-handover.md`](../handovers/01-ubuntu-server-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-08 — `77476eb` |

### Phase 00 closure

Phase 00's documentation and governance work was complete at bootstrap. Its remaining
hardware-verification checks were executed as **Phase 01 Part A**, as Project Planning ruled in
amendment 2 — no separate hardware implementation phase or working context was needed.

The agreed closure condition was that the Part A checklist be recorded in
`docs/reference/hardware.md`, with this file and `ROADMAP.md` updated to say so. That has been done.

**Status 2026-09-08: CLOSED.** Both halves of Part A are complete. Identification recorded RAM
layout, storage, wireless adapter and CPU; physical validation confirmed USB ports, video output and
acceptable fan noise. **Phase 00 is finished** — see `ROADMAP.md`.

## Accepted high-level decisions

See `docs/decisions/` for full ADRs. Current direction includes:

- used budget hardware as the reference platform;
- M700 as orchestration/infrastructure node;
- Ubuntu Server LTS as the hard requirement; 26.04.1 LTS as the *tested* reference build, with its
  ISO and checksum pinned for reproducibility rather than as a constraint (ADR-014);
- whole-disk LVM without full-disk encryption, chosen for unattended headless boot — a
  reference-build trade-off rather than a universal recommendation (ADR-015);
- Wi-Fi as the reference node's *initial* network link, with Ethernet preferred where practical, a
  documented installer fallback path, and reliability to be validated (ADR-016);
- MacBook-driven remote development;
- SSH keys + Tailscale + VS Code Remote SSH;
- model-agnostic architecture;
- explicit router/executor layers before agent frameworks;
- subscription-backed Claude Code/Codex first where officially supported;
- Telegram as first remote interface;
- knowledge storage separate from agents;
- unprivileged user-facing services;
- progressive automation;
- Docker as the container runtime baseline, rootful with non-root containers and explicit-interface
  port publishing (ADR-022);
- known-working `main` branch;
- **metered multi-provider model access as the target substrate**, vendor deliberately unnamed, with
  models as configuration and per-provider unattended eligibility enforced by the router (ADR-026);
- **agents declare a need, never a model**; Factory declares and homelab enforces; declared tools
  are intersected with caller authorisation so an agent is never a privilege escalation path
  (ADR-027);
- **The Factory is stateless method; each project carries its own state** and references Factory
  definitions rather than copying them (ADR-028);
- **four repositories, split on method versus output** — `homelab` and `factory` public, `brain` and
  the product repository private (ADR-029).

## Recently resolved (Phase 01 Part A, 2026-09-08)

- ✅ **M700 RAM module layout** — **1 × 8 GB, one of two slots occupied.** Open since project
  bootstrap. Upgrade path is now 8+8 = 16 GB, with 8+16 = 24 GB optional. **No upgrade is required
  before or during Phase 01.**
- ✅ **Wireless adapter model** — **Intel Dual Band Wireless-AC 8260 (802.11ac).** Uses the in-tree
  `iwlwifi` driver with `iwlwifi-8000C` firmware, which ships in Ubuntu's `linux-firmware` package.
  The ADR-016 risk that the installer cannot see the card is **substantially reduced**; the fallback
  path is retained but is now unlikely to be needed.

## Known unknowns

- Exact versions of tools to be installed in future phases. Docker/Compose/containerd and both Phase
  06 AI CLIs are now recorded.
- ~~Exact Claude/ChatGPT subscription costs to record in the ledger.~~ **Closed 2026-09-09** —
  23.00 EUR/month for the ChatGPT subscription used by Codex and 22.50 EUR/month for Claude Pro.
- ~~Public repository license.~~ ✅ **Closed 2026-09-09** by Phase 04 — MIT for code, CC BY-SA 4.0
  for documentation (ADR-021).
- ~~Final GitHub repository owner/name if different from `homelab`.~~ ✅ **Closed 2026-09-09** —
  `TelesforoAleix/homelab`, public.
- ~~Whether 2FA is enabled on the GitHub account.~~ ✅ **Closed 2026-09-09** — verified enabled
  (`two_factor: true`) after adding the two read-only scopes needed to ask. Primary email is
  **private**, and all commits use the GitHub noreply address.

## Phase 07 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`07-telegram.md`](../handovers/07-telegram.md), committed as `54a33d2` before implementation |
| Service | ✅ `homelab-telegram-bot.service` — native systemd, enabled, running |
| Account | ✅ `homelab-bot` uid 999, `nologin`, no home, **no privileged group** |
| Hardening | ✅ `systemd-analyze security` → **1.3 OK** |
| Exposure | ✅ **No listening socket.** Long polling, outbound HTTPS only; `ss -tln` unchanged |
| Isolation | ✅ Proved by attempted access — cannot read `/home/aleix`, either AI credential, the Docker socket, or its own token |
| Reboot test | ✅ Started 7s after boot, **0 restarts**; recovered from a DNS-not-ready window unaided in 56s |
| ADR-023 | ✅ **Accepted** |
| Guide | ✅ [`guide/07-telegram/`](../../guide/07-telegram/README.md) |
| Verifier | ✅ 0 failures, 0 warnings |
| Handover | ✅ [`07-telegram-handover.md`](../handovers/07-telegram-handover.md) |

**Read-only by design, with no escalation built.** Phase 08 owns the executor pattern; widening the
service account is its decision to make deliberately, not to inherit.

## Phase 08 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`08-router-executors.md`](../handovers/08-router-executors.md), committed as `0d2ff86` |
| Router | ✅ Registry-based, in-process; authorisation check in one function |
| Executors | ✅ Six, at three capability levels; `/help` generated from the registry |
| Authorisation | ✅ Two allowlists; privileged enforced as a **subset** at startup |
| Escalation | ✅ polkit, scoped to **one user, one unit, one verb**; **zero sudoers entries** |
| Second gate | ✅ Unit allowlist inside the bot, independent of polkit |
| Account | ✅ `id homelab-bot` **byte-identical to Phase 07** |
| Denied | ✅ `ssh`, `tailscaled`, `systemd-networkd` — asserted on the reason, not just failure |
| Audit | ✅ Two independent records (bot + systemd PID 1). **polkit logs denials only** |
| Model executor | ✅ Registered, **deliberately unwired** — Phase 09 connected it (ADR-025) |
| Exposure | ✅ Still **1.3 OK**; listeners still 6 |
| Reboot test | ✅ 24.4s; service and grant both survived, proved end-to-end |
| ADR-024 | ✅ **Accepted** |
| Handover | ✅ [`08-router-executors-handover.md`](../handovers/08-router-executors-handover.md) |

**Two Phase 07 properties were traded deliberately:** the bot now forks (`/restart` execs
`systemctl`), and `AF_UNIX` is permitted (needed to reach PID 1). Neither opens the Docker socket,
which is `root:docker 0660` to an account in no group but its own.

## Phase 09 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017 (`351f825`).

| Item | State |
|---|---|
| Brief | ✅ [`09-model-executor.md`](../handovers/09-model-executor.md), committed as `351f825` |
| Credential boundary | ✅ `homelab-bot` **still cannot read either OAuth file** — tested by attempting it |
| How the call is made | ✅ `homelab-model-helper`, runs as `aleix`, socket-activated, one process per connection |
| Access control | ✅ The socket's group and mode (`aleix:homelab-bot:660`), enforced by the kernel — **not** a check in Python |
| Account | ✅ `id homelab-bot` **byte-identical**; no group, no sudoers entry, no `/home/aleix` access |
| Listeners | ✅ `ss -tln` still **6** — a UNIX socket adds none |
| Providers | ✅ Two, independent limits, automatic fallback. **Only exhaustion falls back; a hard error does not** |
| Models | ✅ Cheapest by default: `haiku`, `gpt-5.6-luna` (`gpt-5.4-mini` is rejected on a ChatGPT account) |
| Tool suppression | ✅ Verified with a canary file inside the working directory, against a positive control |
| Model output | ✅ Never dispatched — proved by asking the model to emit `/restart ssh.service`, which it did, with no effect |
| What is sent | ✅ Question + the five `/status` figures only; prompt printed verbatim |
| Caps | ✅ 6/hour, 30/day per provider, enforced **before** the call; lock proved with 10 racing processes |
| Fallback | ✅ Proved against a **genuinely exhausted** Claude, not a mock |
| Exposure | ✅ Bot still **1.3 OK** |
| ADR-025 | ✅ **Accepted** |
| Handover | ✅ [`09-model-executor-handover.md`](../handovers/09-model-executor-handover.md) |

**A second service now runs as the human's account.** It is the only one, and it is the concession
that keeps the credential out of the bot. Three hardening directives are deliberately absent, with
reasons in the unit: `MemoryDenyWriteExecute` (both CLIs ship a JIT), `RestrictNamespaces` (Codex's
sandbox is built from namespaces) and `SystemCallFilter` (unmeasured surface).

**A Phase 07 defect was found and fixed here:** `StartLimitIntervalSec` was in `[Service]`, where
systemd ignores it. The effective window was 10s against `RestartSec=10`, so the restart limit was
**unreachable** for two phases. `install-telegram-bot.sh` now runs `systemd-analyze verify` on
every install.

## Open risks carried forward

> **The repository is now public.** Everything below is publicly documented. That is intentional for
> a reference implementation, and the controls are real — SSH is key-only with `PermitRootLogin no`
> — but the cost of leaving a known weakness open has risen, and a *new* secret committed from here
> on is a disclosure, not a mistake that can be quietly amended.


- ~~SSH password authentication~~ — ✅ **closed 2026-09-09** by Phase 03 (ADR-018). The server
  advertises `publickey` only.
- **Single SSH key, no backup, and no console.** Phase 03 removed the monitor and left one Ed25519
  key as the only way in. New debt, owned by Phase 13. Phase 02 did not close this — it made
  lockout-class changes *recoverable while remote access still works* (ADR-020), which is a different
  thing from a recovery path.
- **The reference node still has no backup of any kind.** Phase 04 gave the *repository* an offsite
  copy; it did nothing for the machine. If the SSD fails, the node is rebuilt from the guide. That is
  survivable by design, but it should not be mistaken for "backup is handled".
- **The volume group has no free extents.** The root LV consumes all 235.4 G, so storage cannot be
  grown by `lvextend`; it needs another disk. Found in Phase 02, not owned by any phase yet.
- **Docker consumes the root LV.** Logs are bounded by `/etc/docker/daemon.json`, and Phase 05
  finished with Docker inventory at zero, but images, containers, volumes and build cache all land on
  the root filesystem.
- **`aleix` is in the `docker` group.** This is root-equivalent access without a password prompt.
  Accepted for the sole administrator in ADR-022; must never be granted to service accounts.
- **Personal AI OAuth credentials now exist in `/home/aleix`.** Both files are mode `0600`, but a
  process running as `aleix` can read them and the root filesystem is not encrypted. Phase 07 did
  not inherit them and Phase 09 did not either — but Phase 09 **did** add a service running as
  `aleix`, so a process that can read them now starts on demand (ADR-025). Whether personal
  subscription credentials are
  supported or appropriate for unattended execution.
- **Subscription inference is capacity-limited, not an availability SLA.** Claude reached its
  five-hour session limit during Phase 06 despite valid authentication. User-facing services need
  an explicit failure policy rather than an assumed always-available executor.
- **Claude Code automatically updates on its stable channel.** Tested versions remain recorded, but
  client behavior can drift between phases. Re-run the constrained fixture and record the new
  version after a material update.
- **Rootful Docker without user-namespace remapping.** Container root maps to host root; mitigated by
  non-root container defaults and Compose hardening. Phase 13 should revisit rootless Docker or
  userns-remap on its merits.
- **Docker and Tailscale now both own packet-filtering chains.** Docker publishes with DNAT before
  host firewall `INPUT` rules, so Phase 13 must design firewalling around Docker rather than
  assuming `ufw deny` controls published container ports.
- **IPv4/IPv6 forwarding policy is asymmetric.** IPv4 `FORWARD` is `DROP`; IPv6 `FORWARD` is
  `ACCEPT`. Not reachable today because IPv6 forwarding is disabled and Docker bridge IPv6 is off,
  but Phase 13 must not assume symmetry.
- **Node key expiry deliberately disabled** on the Tailscale node (ADR-019) — a security control
  traded for availability. Phase 13 must revisit it rather than inherit it.
- **The Telegram allowlist is per-deployment state on the node**, in no backup. New in Phase 07.
- **Telegram is a third party.** Every bot message transits and is stored on their infrastructure.
  Acceptable for uptime and disk figures; a reason not to extend the bot toward anything sensitive
  without revisiting. Phases 08 and 10.
- **One thing can now change the system.** `/restart chrony`, scoped two ways and proved. Phase 07's
  property that a compromise could leak information but not act **no longer holds** (ADR-024).
- **The licensing question is still unresolved, and is now an *accepted risk* rather than an avoided
  one.** ADR-008 covers interactive use only, and nothing since has established whether automating a
  personal subscription falls within either provider's terms. Phase 09 avoided the question with a
  constraint — owner-initiated calls only (ADR-025 §9). **On 2026-09-10 the owner decided to accept
  the risk for the interim** and ADR-026 superseded §9: subscription providers may serve unattended
  calls, with eligibility now a per-provider field the router enforces. The disagreement is recorded
  in ADR-026 §5 rather than smoothed over — rate limiting bounds *capacity*, not terms, and the
  residual exposure is account action or throttling. **The control that makes this reversible is the
  `unattended` field, which must not be removed** just because every current entry is `true`.
- **Data now leaves the machine on every `/ask`** — the owner's question plus the five `/status`
  figures, to Anthropic or OpenAI. Bounded deliberately: no logs, no file contents, no journal.
  Widening that context needs its own ADR, because anything able to write a log line could
  otherwise choose what gets sent (prompt injection). The backup and encryption decisions
  (ADR-015) must account for this.
- **The subscription allowance is a shared resource, and the bot spends it.** Not money — capacity.
  Both subscriptions hit their limits during Phase 09 itself. Capped at 6/hour and 30/day per
  provider, enforced before the call, but the bot and the owner draw from the same bucket.
- **A service now runs as `aleix`.** `homelab-model-helper` is the only one, and it exists so the
  credential stays out of `homelab-bot`. `aleix` can `sudo` and is in the `docker` group, so this
  process is a more valuable target than the bot; `NoNewPrivileges=yes` is retained and three
  further directives are deliberately absent with reasons recorded in the unit.
- **No alerting on the bot.** If it dies at 3am, nothing says so — and bounded logging means a quiet
  journal does not mean a healthy service.
- Wi-Fi is a single point of failure for *both* access routes. `eno1` is present and unused.
- No encryption at rest (ADR-015), which compounds with the cleartext Wi-Fi passphrase (ADR-016).
  Phase 13 should treat these together.
- **Phase 10 must not silently inherit ADR-015.** Once the node stores significant sensitive or
  personal Second Brain data, encryption at rest must be reconsidered on its merits — and converting
  an unencrypted root filesystem after the fact usually means a reinstall.

## Phase 02 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`02-linux-fundamentals.md`](../handovers/02-linux-fundamentals.md), committed before implementation |
| Standard | ✅ [`safe-changes-headless.md`](../standards/safe-changes-headless.md), referenced from `AGENTS.md` |
| ADR-020 | ✅ **Accepted** — change safety on a console-less node |
| Guide | ✅ [`guide/02-linux-fundamentals/`](../../guide/02-linux-fundamentals/README.md) |
| Command reference | ✅ [`linux-command-reference.md`](linux-command-reference.md) |
| Scripts | ✅ `scripts/macos/preflight.sh`, `scripts/server/lab-sandbox.sh` — both run on the real machine |
| Tooling | ✅ `tree` 2.3.1-1, `ncdu` 1.22-1build1, `ripgrep` 15.1.0-1ubuntu1 |
| Validation | ✅ All checks passed with captured output; sandbox created, exercised and removed |
| Handover | ✅ [`02-linux-fundamentals-handover.md`](../handovers/02-linux-fundamentals-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-09 — `0e26859` |

**What Phase 02 deliberately did not teach**, so no later phase assumes it: no networking changes
were practised, no `sudoers` editing, no firewalling, no backup or restore, and no LVM growth. Those
were classified Tier 3 — studied by reading, not by changing — because the node has no console and
Phase 13 will have a better safety net.

## Phase 04 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`04-git-github.md`](../handovers/04-git-github.md), committed before implementation |
| Pre-publication audit | ✅ Two independent scanners over all 220 blobs; **no secrets found, none removed** |
| Scanner validation | ✅ 6/6 planted secrets detected — after a bug that left the private-key class dead |
| ADR-021 | ✅ **Accepted** — publication, visibility and the licence split |
| Licences | ✅ `LICENSE` (MIT), `LICENSE-docs` (CC BY-SA 4.0) |
| Publication | ✅ `github.com/TelesforoAleix/homelab`, **public**, all 4 merge commits intact |
| Pull request | ✅ [#1](https://github.com/TelesforoAleix/homelab/pull/1), merged with `--merge` |
| Guide | ✅ [`guide/04-git-github/`](../../guide/04-git-github/README.md) |
| Workflow reference | ✅ [`git-workflow.md`](git-workflow.md) |
| Scripts | ✅ `scripts/macos/scan-history.sh` |
| Validation | ✅ All 16 checks passed with captured output |
| Handover | ✅ [`04-git-github-handover.md`](../handovers/04-git-github-handover.md) |

**Deliberately not adopted**, so no later phase assumes otherwise: no branch protection on `main`, no
commit signing, no CI/GitHub Actions, no clone of the repository on the reference node. Reasoning in
[`git-workflow.md`](git-workflow.md).

## Phase 05 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`05-docker.md`](../handovers/05-docker.md), committed before implementation |
| Implementation | ✅ Docker Engine 29.8.0, Compose v5.5.1, containerd 2.3.5 from Docker's official apt repository |
| ADR-022 | ✅ **Accepted** — Docker runtime and container conventions |
| Host configuration | ✅ `/etc/docker/daemon.json` log rotation, `vm.swappiness = 10`, `aleix` in `docker` group |
| Guide | ✅ [`guide/05-docker/`](../../guide/05-docker/README.md) |
| Reference | ✅ [`docker-reference.md`](docker-reference.md) |
| Scripts | ✅ `install-docker.sh`, `capture-network-state.sh`, `configure-docker-host.sh` |
| Validation | ✅ Learning exercises passed; no persistent containers/images/volumes/build cache remain |
| Handover | ✅ [`05-docker-handover.md`](../handovers/05-docker-handover.md) |

**Important evidence gap:** the pre-Docker network/firewall capture did not run, so the intended
before/after ruleset diff is unrecoverable. Phase 05 recorded this as a failure. Current chain
attribution is clean — Docker chains and Tailscale chains only — and final reachability checks
passed, but that is weaker than the diff the brief required.

**Conventions established:** rootful Docker; containers default to non-root; Compose services should
drop capabilities, use `no-new-privileges`, and use read-only filesystems where practical; every
published port names an interface; never grant the `docker` group to service accounts.

## Phase 06 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | [`06-ai-cli-access.md`](../handovers/06-ai-cli-access.md), committed before implementation |
| Implementation | Claude Code `2.1.236` stable and Codex CLI `0.153.4`, native user-scoped installs |
| Authentication | Claude Pro subscription OAuth and Codex Sign in with ChatGPT; no API keys |
| Linux sandbox | Ubuntu `bubblewrap` `0.11.1-1ubuntu0.1`; AppArmor restriction left enabled |
| MacBook Codex | Broken npm `0.118.0` package removed; standalone `0.153.4` active |
| Guide | [`guide/06-ai-cli-access/`](../../guide/06-ai-cli-access/README.md) |
| Reference | [`ai-cli-reference.md`](ai-cli-reference.md) |
| Scripts | `install-ai-clis.sh`, `verify-ai-cli-access.sh` |
| Host impact | No daemon, unit, listener, container, Node.js runtime, or API billing path added |
| Handover | [`06-ai-cli-access-handover.md`](../handovers/06-ai-cli-access-handover.md) |

**Boundary established:** these are interactive tools belonging to the administrator. Phase 07's
Telegram process must run under a separate unprivileged identity with no access to `/home/aleix`,
the Docker group, or either OAuth file. Connecting providers to unattended executors remains Phase
08 work.

## Phase 03 status

**Complete 2026-09-09.** Brief committed before implementation per ADR-017.

| Item | State |
|---|---|
| Brief | ✅ [`03-remote-access.md`](../handovers/03-remote-access.md), committed before implementation |
| Implementation | ✅ Key-only SSH, Tailscale 1.102.3, VS Code Remote SSH, console removed |
| Validation | ✅ All checks passed, re-run after a headless cold boot |
| ADR-018 / ADR-019 | ✅ **Accepted** |
| Guide | ✅ [`guide/03-remote-access/`](../../guide/03-remote-access/README.md) |
| Handover | ✅ [`03-remote-access-handover.md`](../handovers/03-remote-access-handover.md) |
| `main` known-working | ✅ **Merged** 2026-09-09 — `5804da6` |

**Sequencing:** the owner chose on 2026-09-09 to run Phase 03 ahead of Phase 02. Phase 01 named SSH
password authentication as its principal open risk, and Phase 02 is a long documentation-heavy phase
that would have left that risk open throughout. Phase 03 also gives Phase 02 a better environment to
be carried out in: key-based login, a stable `ssh homelab` alias, VS Code Remote SSH, and no attached
console. **Phase 02 is deferred, not skipped, and keeps its number.**

## Superseded planning note

The block below was written when Phase 01 closed, before the sequencing decision above. It is kept
rather than rewritten (`PROJECT.md` §11).

**Its instruction has since been discharged.** Phase 02 ran on 2026-09-09 and wrote its brief first,
committing `docs/handovers/02-linux-fundamentals.md` as `6ddf2a5` before any implementation existed.
The block is retained as the record of what was expected, not as an outstanding action.

**Phase 01 is complete and merged. Phase 02 has not started.**

1. **The Phase 02 context writes its own brief** at `docs/handovers/02-linux-fundamentals.md`, using
   `docs/templates/phase-brief-template.md`, and **commits it before implementation begins**
   (ADR-017).

   > Phase 01 began with no brief at all and the phase context had to draft one mid-flight. Under
   > the new model nobody else will write it, so this is now the phase's own first task rather than
   > something to wait for.

2. ~~Review Phase 01's recommended roadmap changes.~~ **Actioned 2026-09-08**, since ADR-017 left
   them with no recipient:
   - system-health assertion added to the Definition of Done in `PROJECT.md` and
     `docs/standards/definition-of-done.md`;
   - the Tailscale documentation warning written into the Phase 03 roadmap entry;
   - the ADR-015 revisit requirement written into the Phase 10 roadmap entry.

3. Sequencing is the owner's call. Phase 02 (Linux Fundamentals) is next by number; Phase 03 (Remote
   Access) closes Phase 01's principal open risk — SSH password authentication.

## Starting state for the next phase

Re-verified 2026-09-09 at the close of **Phase 09**.

| Fact | Value |
|---|---|
| Host | `homelab`, Lenovo M700 Tiny |
| OS | Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic |
| Primary access | `ssh homelab` → MagicDNS over Tailscale |
| Fallback access | `ssh homelab-lan` → `192.168.1.57` on the LAN |
| Authentication | **Public key only.** No passwords, no keyboard-interactive, no root login |
| Tailnet | `100.71.62.71`; node key expiry disabled |
| Admin user | `aleix`, sudo-capable; **`sudo` requires a password — no `NOPASSWD`** |
| Docker access | `aleix` is in `docker` group `983`; this is root-equivalent (ADR-022) |
| Storage | LVM, 232 GB root, 8.9 GB used, 212 GB available (5%), unencrypted |
| Health | `systemctl is-system-running` → `running`, no failed units |
| Tooling | `tmux` 3.6, `htop`, `jq`, `git`, `vim`, `nano`, `less`, `lsof`, `tree`, `ncdu`, `ripgrep`, Docker 29.8.0, Compose v5.5.1, containerd 2.3.5, Claude Code 2.1.236, Codex CLI 0.153.4, `bubblewrap` 0.11.1 |
| AI authentication | Claude `claude.ai` / first-party / Pro; Codex `Logged in using ChatGPT`; relevant API-key variables unset |
| AI credential files | `/home/aleix/.claude/.credentials.json` and `/home/aleix/.codex/auth.json`, both mode `0600`, owner `aleix:aleix`; contents never captured |
| AI processes/services | None; both CLIs are interactive operator commands |
| Docker inventory | 0 images, 0 containers, 0 local volumes, 0 build cache |
| **Services** | **`homelab-telegram-bot.service`** — active, enabled, **0 restarts**. **`homelab-model-helper.socket`** — active, enabled; templated service instantiated per connection |
| Model helper socket | `/run/homelab-model-helper.sock`, `aleix:homelab-bot`, mode `660` |
| Model access | `/ask` works. Claude `haiku`, Codex `gpt-5.6-luna`; caps 6/hour, 30/day per provider |
| Restart limit | **`StartLimitIntervalUSec=5min`** on the running unit — was silently 10s until Phase 09 fixed it |
| Service account | `homelab-bot` uid 999; groups: `homelab-bot` only. Not `sudo`, not `docker`, not `adm` |
| Service hardening | `systemd-analyze security` → **1.3 OK** |
| Listening | **6 sockets; `:22` only off-box.** Everything else on loopback or the tailnet. Docker, the AI CLIs and the bot published nothing — the bot long-polls outbound. **Unchanged by Phase 09: the model helper uses a UNIX socket, which is a file, not a port** |
| Swappiness | `vm.swappiness = 10` |
| Boot | **24.4s** cold, headless, to reachable |
| **Console** | **Unplugged, not absent.** DRM connectors all `disconnected` and the cable is removed, but six video outputs are present, `getty@tty1` is enabled **and active**, `usbhid` is loaded, and the machine is in the owner's room with a monitor and keyboard available. **Corrected 2026-09-10** — earlier text said `None`, which overstated it and made lockout look unrecoverable |

Reproduce with `scripts/server/verify-install.sh` (Phase 01 base) and
`scripts/server/verify-remote-access.sh` (Phase 03 posture; run under `sudo` for a complete report).

> **The console is gone.** This is now a written standard rather than a warning:
> [`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md), adopted as
> ADR-020 and referenced from `AGENTS.md`. Apply it before any change touching network, remote
> access, authentication, boot, or the admin account. `scripts/macos/preflight.sh` checks the parts
> a machine can check.
