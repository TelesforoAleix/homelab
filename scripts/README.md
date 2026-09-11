# Scripts

Reproducible helper and administration scripts belong here. Prefer scripts after the underlying
manual process is understood (ADR-012).

Scripts are organised by **where they run**, which is not always where they are edited.

## Repository-wide — run anywhere, and in CI

| Script | Purpose |
|---|---|
| `boundary-gate.sh` | The ADR-029 §5 gate: refuses to let knowledge-shaped or output-shaped content sit in a public repository. Matches on **structure** — frontmatter vocabulary, concrete-versus-placeholder identifiers, path components — never on a word in prose, because ADR-029's own tables name the very paths a substring search would flag. Run `--self-test` to make it fail on planted content before trusting it; CI does that on every invocation. The working tree **fails**; history is **reported**, because history cannot be cleaned without a force-push that branch protection blocks. States its own limits in its header, including that the history scan is path-based only. |

## `macos/` — run on the MacBook

| Script | Purpose |
|---|---|
| `download-ubuntu-iso.sh` | Downloads the pinned Ubuntu Server image and verifies it two ways: against the checksum recorded in ADR-014, and against the checksum Ubuntu publishes today. Refuses to hand you an unverified file. |
| `write-ubuntu-usb.sh` | Writes a verified ISO to a USB stick. **Destructive.** Refuses to target an internal disk, rejects partition identifiers, and requires you to retype the disk identifier before writing. |
| `scan-history.sh` | Scans every blob reachable from every ref for secrets — the pre-publication gate required by ADR-021. Deliberately scans *objects*, not the working tree, because `.gitignore` is not retroactive and a secret deleted in a later commit is still in history. States its own limits in its header. |
| `backup-node.sh` | Pulls everything irreplaceable off the node — bot token, three allowlists, unit files, polkit rule, model-helper state, both OAuth credentials, network config and authorized_keys — plus mirrors of all five repositories, encrypts with `age` and writes to removable media. **Interactive by design:** it prompts for the node's sudo password every run, because a `NOPASSWD` rule or a stored key would make the backup a second root-equivalent path (ADR-022, Phase 18 brief §5). Excludes the ~366 MB of reinstallable Codex packages. |
| `verify-node-backup.sh` | Proves a backup can be restored, rather than trusting that it was written. Decrypts, checks the archive against a checksum recorded *before* encryption, extracts, and compares every file against the running node by content hash and numeric owner — then corrupts a copy by one byte and **requires its own check to fail on it**. Does not claim a bare-metal rebuild would boot; says so in its own output. |
| `preflight.sh` | Checks the safety preconditions from `docs/standards/safe-changes-headless.md` before a lockout-class change (ADR-020). Runs on the Mac deliberately: it proves both access routes from outside, the way a real connection arrives, which a script on the server cannot do. |

## `server/` — run on the Ubuntu server

| Script | Purpose |
|---|---|
| `verify-install.sh` | Produces a Markdown report of the server's real state — hardware, LVM layout, network, services, versions — for pasting into `docs/`. Deliberately never prints netplan file contents, which hold the Wi-Fi passphrase in cleartext. |
| `apply-ssh-hardening.sh` | Installs the key-only sshd configuration (ADR-018). Refuses to run if the invoking user has no `authorized_keys` entry, reverts itself if `sshd -t` rejects the result, and reloads sshd — because the running daemon does not re-read its configuration on its own. |
| `install-tailscale.sh` | Adds Tailscale's apt repository and installs it. Derives the codename from `/etc/os-release` and refuses to continue unless the repository declares `Origin: Tailscale` and the running architecture, so an unsupported release becomes a recorded problem rather than a silent fallback (ADR-014). |
| `install-docker.sh` | Adds Docker's apt repository and installs Docker Engine plus the Compose v2 plugin. Treats the install as lockout-class because Docker rewrites packet-filtering rules, verifies repository origin/suite/architecture/component before touching apt, and writes log rotation before the daemon first starts. |
| `capture-network-state.sh` | Captures redacted network, route, socket, iptables, ip6tables and nftables state before/after lockout-class changes. Output is designed to be safe to paste: MAC addresses and the tailnet name are redacted. |
| `configure-docker-host.sh` | Applies Phase 05 host settings after Docker install: `vm.swappiness = 10` and `aleix` in the `docker` group. Treats the group change as lockout-class because it touches the admin account, and records Docker group root-equivalence. |
| `install-ai-clis.sh` | Stages the official Claude Code and Codex native installers for review, records their SHA-256 hashes, then verifies and runs the exact staged files as a non-root user. Refuses Linux root execution and does not install Node.js or configure credentials. |
| `verify-ai-cli-access.sh` | Verifies CLI versions, subscription authentication class, absent API-billing variables, credential file metadata, and lack of persistent AI processes/services. Deliberately never prints credential values or account identifiers. |
| `lab-sandbox.sh` | Creates and destroys the disposable Phase 02 practice environment — a passwordless `nologin` user, a group, a setgid directory, and a systemd unit with no `[Install]` section so it can never run at boot. Refuses to create anything colliding with a real account, and refuses to delete any account not carrying the marker it writes. |
| `install-telegram-bot.sh` | Deploys the Phase 07 status bot: a dedicated unprivileged account, root-owned code the bot cannot modify, and a hardened unit. Refuses to run with fewer than two sessions (a boot-time unit is lockout-class), and re-checks on **every** run that the service account is in no privileged group — not only at creation. |
| `install-bot-escalation.sh` | Grants the bot exactly one privileged action via a polkit rule scoped to one user, one unit and one verb. Validates scope and brace balance before installing, checks polkit's journal for load errors, then **proves the grant in both directions** — restarting the permitted unit, and confirming three access-critical units are denied *and that the reason is a denial*. |
| `verify-telegram-bot.sh` | Proves the bot's posture by **attempting** each forbidden access rather than reading directives. Checks its own privilege first and reports `UNKNOWN` for anything it cannot determine — added after it reported a confident `FAIL` about a file it had no permission to see. |
| `install-model-helper.sh` | Deploys the Phase 09 model helper — the service that makes model calls as `aleix` so the bot never holds a credential. Installs code root-owned so the account that runs it cannot rewrite it, and proves the boundary both ways: a probe running **as `homelab-bot` inside the bot's own systemd sandbox** must reach the socket, and `homelab-bot` must still fail to read both OAuth credentials. Reports errno rather than a verdict, because EROFS, EACCES and ENOENT need different fixes. |
| `configure-telegram-bot-profile.sh` | Sets the bot's name, descriptions and **command list** so a phone client offers autocomplete. The command list is derived from the executor registry, not typed out, so adding an executor updates the menu with nobody editing a list. `/restart` is withheld from the default command scope — not as access control (the allowlist does that) but so a privileged action is not advertised to strangers. The token never reaches curl's `argv`, and all output passes through a redactor. `show` is the default and makes no writing call. |
| `verify-remote-access.sh` | Reports the live remote-access posture. Probes the **running** SSH daemon over the network rather than trusting `sshd -T`, warns when configuration is newer than the daemon, and redacts the Tailscale account and tailnet suffix so its output is safe to paste. |

## Conventions

- `set -euo pipefail` unless a script must survive missing optional tools, in which case say why.
- Destructive operations require an explicit target and an explicit confirmation. Never a default.
- Anything whose output is meant to be pasted into the repository must be safe to paste: no secrets.
  That includes identity leaking in from third-party tools — `verify-remote-access.sh` redacts the
  Tailscale account and tailnet name, which `tailscale status` prints against every node.
- A script that changes a security control should verify the **running system**, not the file it
  just wrote. Phase 03 shipped a correct configuration to a daemon that never re-read it.
- A check that cannot determine an answer must say **unknown**, never a plausible-looking zero.
  Phase 02's session check first used `who`, which reports no sessions and exits 0 on Ubuntu 26.04
  because systemd 257 removed utmp support. Being confidently wrong is worse than erroring.
- **An error is not a negative result.** `grep` exit 2 is not exit 1. Phase 04's private-key check
  passed a pattern beginning with dashes, so grep parsed it as options and failed — and because the
  code discarded stderr and treated any non-match as clean, the most important class in the scanner
  was silently dead. Inspect exit status; refuse to produce a verdict a check could not support.
- **A detector that has only ever reported "clean" is unvalidated.** It has been shown it can say
  *fine*; it has never been shown it can say *not fine*. Plant a positive case somewhere disposable
  and confirm it fires. That is how the bug above was found, four checks into the same failure family
  across three phases.
- **A test must assert on the reason, not the outcome.** "The command failed" and "the account was
  denied" are different claims and only one is evidence. Phase 08's escalation test printed
  `ok ... cannot restart ssh.service` when what had happened was that a polkit agent prompted the
  admin and nobody answered — a pass for the wrong reason, and one that asked a human to restart
  `tailscaled` on a console-less node. Never let a test raise an interactive prompt
  (`--no-ask-password`), and grep the output for the expected refusal.
- **Any command whose output you will act on is a check** — including the one-off typed at a
  terminal. Phase 08 read `setpriv: Operation not permitted` as a negative result about a security
  property, four minutes after writing that exact lesson into the build log. The committed scripts
  held; the failure moved to the least reviewed code in the project.
- **Check your own privilege before reporting a result.** Phase 07's verifier reported
  `FAIL: token does not exist` about a file in a `0750` directory it could not traverse, while the
  service was authenticating with that token. That is the **fifth** instance of this family, after
  `sshd -T`, `who`, and two Phase 04 scanner bugs — written after the rule had been documented four
  times. Intention has failed repeatedly; make `UNKNOWN` a result the report can express.
- **Report what was actually examined**, not just the conclusion. Phase 04's scanner reported all
  sixteen classes clean while having searched zero of 213 blobs. It now prints the count and refuses
  to report a verdict on an empty corpus.
- **A directive a tool ignores is not a directive, and it will not tell you.** Phase 07 put
  `StartLimitIntervalSec` in `[Service]`, where systemd ignores it and starts the unit anyway. The
  effective window was 10s against a `RestartSec=10` policy, so five starts could never fall inside
  it: the restart-loop protection was not merely misconfigured, it was **unreachable**, for two
  phases. `StartLimitBurst=5` *is* valid in `[Service]`, so half the setting worked and
  `systemctl show` reported a plausible pair. Found in Phase 09 by running `systemd-analyze verify`,
  which `install-telegram-bot.sh` now does on every install and prints the output of. Reading the
  file more carefully would not have found this; asking the tool did.
- **"Do not show the user" and "do not record it" are different decisions.** Phase 09 kept raw
  provider output out of the Telegram reply — correct, it carries absolute paths and the reply
  leaves the machine — and thereby logged it nowhere. The first real failure arrived with no
  evidence anywhere. Suppressing something from a user-facing message says nothing about where it
  should be written down; the journal is usually the answer.
- **A branch exercised only against invented input is untested.** Phase 09's exhaustion detector was
  built from one provider's observed wording plus guesses at the other's. The guesses missed
  Claude's actual phrase — `session limit` — so a completely normal condition was reported as an
  unrecognised failure and no fallback was attempted. The observed half was right and the guessed
  half was wrong, which is the Phase 04 scanner lesson in new clothing.
- **The first control you think of often varies two things at once.** Phase 09 tested that
  `--tools ""` disables model tools by asking the model to read a file *outside* the working
  directory. It was refused with the flag and also refused without it — for a different reason. The
  discriminating test used a canary **inside** the working directory, where the only difference
  between the two runs was the flag.
- **A capability a tool advertises is not a capability your account has.** The Codex binary's
  embedded catalogue lists `gpt-5.4-mini`; a ChatGPT subscription rejects it outright. Enumerating
  what a CLI knows about is not the same as discovering what it is entitled to use.
- **Every network call needs a timeout, including the one you are sure is fast.**
  `configure-telegram-bot-profile.sh` shipped its first draft with no `--max-time`, and its first
  real run hung until Ctrl-C. The cause was not logic: identical Telegram API calls from this node
  measured between **207ms and 8.9 seconds**, because both access routes share one Wi-Fi adapter.
  A call with no bound is a call that can hang forever, and a script that can hang forever cannot be
  put in a verification path. Do not add `--retry` instead — that hides the very variance that makes
  the timeout necessary.
- **Address-family selection is a measurement, not a default.** The same script now passes `--ipv4`
  because this host has **no working global IPv6 route** — `curl -6 https://api.telegram.org/` fails
  in 9ms while the node's only IPv6 address is the Tailscale one. `api.telegram.org` publishes AAAA
  records, so leaving selection to chance means sometimes racing toward an address that cannot work.
  The flag carries the measurement in a comment so it can be removed deliberately when that changes.
- **An empty response is not a result.** The same script's `show` mode now says
  "no response within 30s — network, not configuration" rather than printing an empty block, because
  a blank section reads as "Telegram has nothing set", which is a completely different claim.
- **An exception handler that returns a plausible value is how this project's oldest bug keeps
  coming back.** `configure-telegram-bot-profile.sh` read API fields with
  `FIELD="$f" api "$m" | python3 -c '... os.environ["FIELD"] ...'`. In a pipeline, `VAR=val cmd1 |
  cmd2` sets the variable for **cmd1 only**, so python never received `FIELD`, raised `KeyError`, and
  a bare `except Exception` converted that into the string `"<unreadable>"`. The caller compared
  that string to the expected value and printed **FAIL** — reporting a bug in the check as a defect
  in the thing checked. The values had almost certainly been set correctly.

  That is the **ninth** instance, after `sshd -T`, `who`, two Phase 04 scanner bugs, the Phase 07
  verifier, the Phase 08 escalation test, the Phase 08 `setpriv` misread and the Phase 09 installer's
  group check — and it was written in the same session in which two of those were documented.
  Reading the rule is demonstrably not sufficient. What works is structural: **a reader returns a
  value or returns nothing with a non-zero status, never a sentinel string**, and the caller has
  three branches — matched, differs, could-not-check. Validate all three against crafted input
  before trusting any of them.
- **Pick timeout numbers from measurements, not from what sounds generous.** The same script's first
  `--connect-timeout 10` failed on a real write with `Connection timed out after 10001 ms`, on a
  node whose identical API calls had already been measured at up to 8.9s. The decision to have a
  timeout was right; the number was a guess inside the observed spread.
