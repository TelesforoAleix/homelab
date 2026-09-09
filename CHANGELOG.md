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
