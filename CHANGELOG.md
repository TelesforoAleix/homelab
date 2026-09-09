# Changelog

This project uses this file for meaningful repository-level milestones rather than logging every commit.

## Unreleased

### Added

- Initial Home Lab repository bootstrap structure.
- Project governance and contributor rules.
- Initial ADR set based on pre-development planning.
- Guide, build-log, budget, architecture, and handover templates.
- Phase 01 brief, guide, ADRs (014 release, 015 disk layout, 016 network link), and
  install/verification scripts. The installation itself has not yet been performed.
- Phase 01 brief ratified by Project Planning (2026-09-08) with six amendments, reconciled across
  the brief, all three ADRs, the guide and project documentation. Remaining Phase 00 hardware
  validation is now Phase 01 Part A rather than a standalone phase.
- **Phase 01 complete.** Ubuntu Server 26.04.1 LTS installed on the reference node, validated by
  live output including unattended power-loss recovery. Guide corrected five times by using it;
  boot time reduced from ~145s to 23s by fixing a failed `systemd-networkd-wait-online` unit.
- Phase 01 Part A hardware identification recorded. Resolves two unknowns open since bootstrap: RAM
  layout (1 x 8 GB, one slot free) and wireless adapter (Intel Wireless-AC 8260). Adds a firmware
  task to enable CPU virtualization, found disabled. No software installed or marked as tested.

- **Phase 04 complete.** The repository was published: `github.com/TelesforoAleix/homelab`, public,
  MIT for code and CC BY-SA 4.0 for documentation (ADR-021). Until this phase it had **no remote at
  all** — 37 commits on one disk with no backup, which was a larger single point of failure than the
  single SSH key, because it held the knowledge of how to rebuild the machine. A full-history secrets
  audit ran before the first push and found nothing that had to be removed. Adds
  `scripts/macos/scan-history.sh`, the guide, `docs/reference/git-workflow.md`, and phase tags
  `phase-01` … `phase-04`. Closes two known unknowns open since bootstrap (licence, repository name).
  Four failures recorded, all of the same family — checks that report success by returning nothing;
  the worst left the scanner's private-key class silently dead and was found only by planting fake
  secrets and confirming it fired.

- **Phase 02 complete.** Linux fundamentals, taught from this machine's own files rather than from
  invented examples. Adds `docs/standards/safe-changes-headless.md` and ADR-020 — a change-safety
  standard binding on every phase from 02 onward, now that the reference node has no console and
  recovery from a lockout is physical. Adds `scripts/macos/preflight.sh`,
  `scripts/server/lab-sandbox.sh`, the guide, and `docs/reference/linux-command-reference.md`.
  Nothing on the node changed except three diagnostic packages; the sandbox was removed and its
  absence proved.
- Phase 02 found that `who` reports zero sessions and exits 0 on Ubuntu 26.04: systemd 257 removed
  utmp support, so `/run/utmp` does not exist. It was being used for the most important check in the
  new standard. Recorded in the standard itself, and the check now reports *unknown* rather than
  *zero* when it cannot tell.
- **Phase 03 complete.** Remote access: Ed25519 key-only SSH (ADR-018), Tailscale 1.102.3 with
  MagicDNS (ADR-019), VS Code Remote SSH, and the console physically removed. Closes Phase 01's
  principal open risk — the server no longer accepts password authentication. Run ahead of Phase 02
  by the owner's sequencing decision; Phase 02 is deferred, not skipped.
- Phase 03 scripts: `apply-ssh-hardening.sh` (refuses to run without an installed key, reverts
  itself if `sshd -t` fails), `install-tailscale.sh` (verifies the repository publishes for the
  running codename before touching `/etc`), `verify-remote-access.sh` (probes the running daemon
  rather than trusting `sshd -T`, and redacts account and tailnet identifiers).
- Phase 03 recorded a failure worth keeping: `sshd -T` reported password authentication disabled
  while the running server still accepted passwords. Ubuntu's `ssh.socket` uses `Accept=no`, so one
  long-running daemon serves every connection using the configuration it parsed at start. A
  configuration file is not a control until the process holding it has re-read it.
- **Phase 05 complete.** Docker Engine 29.8.0, Compose v5.5.1, and containerd 2.3.5 installed from
  Docker's official apt repository. Adds ADR-022, `guide/05-docker/`,
  `docs/reference/docker-reference.md`, `scripts/server/install-docker.sh`,
  `scripts/server/capture-network-state.sh`, `scripts/server/configure-docker-host.sh`, Docker host
  log rotation, and a committed teaching image/Compose stack. Nothing persistent is left running.
- Phase 05 established the container convention that every published port names an explicit
  interface. `-p 8080:80` is forbidden because Docker publishes with DNAT before host firewall
  `INPUT` rules. It also records that `aleix` is in the `docker` group, which is root-equivalent and
  must never be granted to service accounts.
- Phase 05 recorded a failure worth preserving: the pre-Docker network/firewall capture did not run,
  so the exact before/after ruleset diff is unrecoverable. Attribution by chain name found only
  Docker and Tailscale chains, and final reachability checks passed, but this is weaker evidence than
  the brief required.
- **The bot's Telegram profile and command menu are now set from the registry.** A phone client
  offers no autocomplete for unregistered commands, so `/ask` had to be typed from memory. The
  command list is derived from `executors.register_all()` — the same single source of truth that
  generates `/help` — and `/restart` is withheld from the default scope so a privileged action is
  not advertised to strangers. This replaced a hand-set BotFather list that had drifted for two
  phases: it advertised `/model` as "Chat with AI" while that executor was deliberately unwired, and
  omitted `/ask` entirely. Four bugs recorded, all the author's, including the **ninth** instance of
  a check reporting a confident FAIL about something it could not read — this time an environment
  variable assigned to the wrong end of a pipeline, laundered into a plausible string by a bare
  `except Exception`.

- **Phase 09 complete.** The model executor, connected — `/ask <question>` answers from Telegram
  using the existing subscriptions. The design problem was that `homelab-bot` **provably cannot read
  either AI credential** (a Phase 07 property proved by attempting the read), so the call moved to a
  separate service running as `aleix` that the bot asks over a UNIX socket. The bot gained no group,
  no sudoers entry and no read access to `/home/aleix`; `id homelab-bot` is byte-identical and
  `ss -tln` still shows **6 listeners** — a UNIX socket is a file, not a port. Access control lives
  in the socket unit (`SocketGroup=homelab-bot`, mode 0660), not in Python, because a rule in a unit
  file cannot be bypassed by a bug in the program it protects. Two providers with independent usage
  limits and automatic fallback, which earned itself immediately: Claude was exhausted when the first
  live `/ask` ran and Codex answered it. Cheapest models by default (`haiku`, `gpt-5.6-luna`). The
  model gets **no tools**, verified with a canary file rather than assumed, and its output is never
  dispatched — tested by asking the model to emit `/restart ssh.service`, which it did, with no
  effect. Only the question and the five `/status` figures leave the machine; logs are excluded
  because anything that can write a log line could otherwise choose what gets sent. Owner-initiated
  only, which is the constraint that substitutes for the still-unresolved licensing question:
  **Phase 12 must not make unattended calls without a new ADR.** Adds ADR-025, the guide,
  `services/model-helper/`, `model_client.py`, two systemd units and a guarded installer. Nine
  problems recorded, most of them the author's — including an exhaustion pattern written from
  guesses that misread a normal limit as a mystery, and suppressing the evidence needed to diagnose
  it while calling that a security decision.

- **Phase 07's restart limit is fixed.** `StartLimitIntervalSec` sat in `[Service]`, where systemd
  ignores it; the running unit had a 10s window against a `RestartSec=10` policy, so five starts
  could never land inside it and the limit was **unreachable**. Found by `systemd-analyze verify`,
  which `install-telegram-bot.sh` now runs on every install. `StartLimitBurst=5` *is* accepted in
  `[Service]`, so half the setting worked and `systemctl show` reported a plausible pair — which is
  how it survived two phases.

- **Phase 08 complete.** The structure behind the interface: a registry-based router with six
  executors at three capability levels, and **two allowlists** separating authentication from
  authorisation. **One privileged action, performed by an account that gained nothing** — `id
  homelab-bot` is byte-identical to Phase 07 with zero sudoers entries, scoped by a polkit rule to
  one user, one unit and one verb plus a second allowlist inside the bot. polkit rather than sudo
  because `NoNewPrivileges=yes` refuses setuid outright, and because a malformed polkit rule denies
  where a malformed sudoers file breaks `sudo` on a console-less node. The model executor is
  registered and **deliberately unwired**; ADR-008 covers interactive use only, and Phase 09 must
  decide. Adds ADR-024, the guide, `router.py`, `executors.py`, the polkit rule and two guarded
  scripts. Five problems recorded, three of them the author's — including a test that asked the
  admin to restart `tailscaled` and then reported a pass because nobody answered.

- **Phase 07 complete.** The first thing the node does *for* its owner: a read-only Telegram status
  bot. Delivered as a native systemd service rather than a container, running as a dedicated account
  in no privileged group, scoring 1.3 OK on `systemd-analyze security`. Long polling means it opens
  **no listening socket**, which is what makes a network service acceptable on a node with no
  firewall. Standard library only; the bot never forks a process. Isolation proved by attempted
  access rather than asserted from directives. Adds ADR-023, the guide, `bot.py`, a hardened unit,
  and two guarded scripts. Five problems recorded, four of them the author's — including hardening
  that stopped a system-info reporter reading system info, an unguarded exception that turned the
  bot into a restart loop on a console-less node, and a verifier that reported a confident `FAIL`
  about a file it lacked permission to see.

- **Phase 06 complete.** Claude Code `2.1.236` stable and Codex CLI `0.153.4` installed as native,
  user-scoped operator tools and authenticated through existing Claude Pro and ChatGPT
  subscriptions. Adds `guide/06-ai-cli-access/`, `docs/reference/ai-cli-reference.md`,
  `scripts/server/install-ai-clis.sh`, and `scripts/server/verify-ai-cli-access.sh`. Ubuntu
  `bubblewrap` `0.11.1-1ubuntu0.1` supplies Codex's Linux sandbox. No API key, API billing, Node.js,
  daemon, listener, or persistent container was added.
- Phase 06 recorded three boundaries through real failures: Codex device authorization had to be
  enabled before generating a fresh code; a model call can exit `0` even when its local sandbox
  fails; and valid Claude Pro authentication does not imply capacity remains in the current
  five-hour window. The MacBook's broken npm Codex install was also replaced after its platform
  executable proved missing. A consumed one-time Claude authorization code was mistakenly pasted
  into the agent conversation; it never entered the repository, and the build log records the
  correct direct-to-terminal handling.

### Changed

- **Governance model replaced (ADR-017).** The separate Project Planning context is retired; phases
  are self-contained and sequential, and the repository is the sole governance authority. Each phase
  now writes its own brief before implementation and a handover addressed to the next phase.
  Historical documents referencing the old model are retained unchanged.
- Definition of Done gains a system-health item — Phase 01 passed every functional test on a machine
  that was quietly degraded.
- Repository bootstrap moved into Phase 00 so implementation history can be documented from the beginning.
