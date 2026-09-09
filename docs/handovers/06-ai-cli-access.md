# Phase 06 Brief — AI CLI Access

- **Date:** 2026-09-09
- **Phase:** 06 — AI CLI Access
- **Author:** the Phase 06 context
- **Status:** Accepted, self-ratified under ADR-017
- **Previous handover:** [`05-docker-handover.md`](05-docker-handover.md)

## 0. Governance note

Under ADR-017, this phase owns its brief, implementation, literal Definition of Done review, and
handover. This brief is committed **before implementation begins**.

The phase begins with a useful distinction: Claude Code has already helped build this repository on
the MacBook, but neither AI CLI is installed on the reference node and neither has yet been treated
as part of the reproducible Home Lab. Prior incidental use is not Phase 06 completion.

## 1. Purpose

Install and validate Claude Code and OpenAI Codex on the headless reference node using the owner's
existing subscription entitlements, without introducing API keys, usage-based API billing, an agent
framework, or a persistent AI service.

This is an **interactive operator-tool phase**. It proves that both providers can be reached from
the node, shows where credentials and conversation state live, and teaches the permission boundary
of an AI coding agent. It does not yet turn either CLI into the executor behind Telegram or a
router; that belongs to Phases 07 and 08 and requires a different privilege and credential design.

## 2. Starting state

Verified from the repository, the Phase 05 handover, the MacBook, and a fresh SSH connection to the
node on 2026-09-09.

### Reference node

| Fact | Value |
|---|---|
| Host / architecture | `homelab`, `x86_64` |
| OS | Ubuntu Server 26.04.1 LTS (`resolute`) |
| Health | `systemctl is-system-running` → `running`; no failed units |
| Memory / swap | 7.1 GiB RAM, 5.8 GiB available; 4.0 GiB swap, unused |
| Root filesystem | 232 G total, 8.2 G used (4%), 213 G available |
| Claude Code | Not installed |
| Codex CLI | Not installed |
| Node.js / npm | Not installed |
| Existing AI credentials | No Claude or Codex credential file present |
| Billing-related environment | `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, and `CODEX_ACCESS_TOKEN` all unset |
| Docker | Available, but no containers, images, volumes, or build cache inherited from Phase 05 |

The node has `curl`, Git, and ripgrep. Its repository is deliberately not cloned there; Phase 04
kept the MacBook repository as the primary development copy.

### MacBook observations

These are diagnostic context, not proof of the node's target state:

- Claude Code `2.1.266` is installed at `/opt/homebrew/bin/claude`, currently logged out.
- `/opt/homebrew/bin/codex` exists, but its npm launcher is broken because the expected platform
  binary is missing. The Phase 06 server install must be independent of this MacBook failure.
- The MacBook remains the primary development and administration interface (ADR-004).

## 3. Learning objectives

By the end of the phase, the owner should be able to explain:

1. The difference between subscription-backed CLI access and pay-as-you-go API access.
2. Why the authentication method, not just the model name, determines which allowance or bill is
   used.
3. How browser OAuth and device-code authentication work on a remote, headless machine.
4. Where each CLI stores credentials on Linux and why those files are password-equivalent secrets.
5. The difference between an AI tool's approval prompt and an operating-system security boundary.
6. What files, commands, network requests, and account data an interactive coding agent may touch.
7. How Claude and Codex report authentication, model/session state, and usage limits.
8. Why a five-hour or weekly subscription reset is normal capacity control rather than a broken
   installation.
9. Why interactive CLIs running as `aleix` are not automatically suitable executors for an
   unprivileged Telegram service.

## 4. Functional objectives

1. Install current official Linux builds of Claude Code and Codex for `aleix`, without `sudo` and
   without installing Node.js merely to host the CLIs.
2. Record the installer URLs, installer hashes observed, installed paths, and versions actually
   tested.
3. Authenticate Claude Code through the owner's Claude subscription and Codex through the owner's
   ChatGPT subscription.
4. Prove from each CLI's own status output that subscription authentication is active; redact
   account identifiers and never capture token values.
5. Run one bounded read exercise and one controlled write/review exercise with each CLI in a
   disposable Git workspace.
6. Demonstrate a denied or unapproved action so permission prompts are learned as part of the
   workflow, not after an accident.
7. Diagnose the existing broken MacBook Codex launcher and either repair it or record why it is
   deliberately left separate from the server installation.
8. Finish with no AI process, container, daemon, or network listener left running.

## 5. Decisions already fixed

### Accepted ADRs

- **ADR-004:** the MacBook remains the primary development interface; the M700 is a headless
  execution/server environment.
- **ADR-006:** build explicit router and executor layers before adopting an agent framework.
- **ADR-007:** keep model access replaceable rather than hard-coding the platform around one
  provider.
- **ADR-008:** use officially supported subscription-backed Claude Code and Codex authentication
  first; introduce direct API billing intentionally later.
- **ADR-011:** no future user-facing AI interface runs as root.
- **ADR-017:** this brief is committed before implementation and the handover must state what Phase
  07 inherits.
- **ADR-020:** the node has no console. Phase 06 is not lockout-class as scoped because it changes
  only files owned by `aleix`; any discovered need to alter networking, authentication, boot, or the
  admin account must stop and apply the safe-headless procedure first.
- **ADR-022:** Docker is available but does not need to be used. These are interactive user tools,
  not persistent services; containerizing them would complicate OAuth and project access without
  solving a phase objective.

### Installation and authentication choices

- Use each vendor's current **native macOS/Linux installer**, downloaded and inspected before
  execution. Do not use `curl | sh` directly during the reference build.
- Install into `aleix`'s home directory. Do not use `sudo`, create a service account, or grant new
  groups.
- Use Claude subscription OAuth and Codex **Sign in with ChatGPT**. On the headless node, prefer
  Codex's documented `codex login --device-auth` flow.
- Do not set or import `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY`, or other API
  billing credentials.
- Do not enable paid overage, usage credits, or a Console/API fallback merely to bypass a
  subscription usage window. Reaching a limit is recorded and the test resumes after reset.
- Do not copy the MacBook's auth cache to the node when an official device or browser flow works.
  Separate login creates a cleaner audit trail and avoids moving password-equivalent files.
- Do not use flags that bypass approvals or remove sandboxing. Examples include Claude's
  `--dangerously-skip-permissions` and unrestricted Codex sandbox/approval combinations.

Current official guidance checked when writing this brief:

- [Claude Code installation](https://code.claude.com/docs/en/installation)
- [Claude Code authentication](https://code.claude.com/docs/en/authentication)
- [Claude subscription use in Claude Code](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan)
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [Codex authentication](https://learn.chatgpt.com/docs/auth)

## 6. Decisions still open

1. Whether the current vendor auto-update channels are accepted as-is or constrained after their
   actual behavior is observed. Reproducibility requires tested versions and install method, not a
   false promise that hosted AI clients never change.
2. Whether the MacBook Codex launcher should be repaired with the native installer or removed and
   reinstalled through its existing package-management path.
3. Which smallest permission settings give a useful, comparable Claude/Codex exercise. Keep any
   configuration user-local and avoid pretending the two products have identical security models.
4. The owner's exact Claude and ChatGPT subscription plans and actual recurring prices. These must
   be supplied or verified before Phase 06 can close its cost ledger honestly.
5. Whether either CLI's subscription terms and technical behavior are appropriate for unattended
   execution. Phase 06 must not resolve that by silently turning interactive credentials into a
   service credential; carry the question to Phase 08 if still open.

## 7. Implementation scope

### In scope

- Capture pre-install health, processes, listeners, relevant environment-variable presence, and
  credential-file absence without printing secrets.
- Download both official installer scripts to a temporary directory, inspect their destinations and
  privilege behavior, record SHA-256 hashes, then run them as `aleix`.
- Ensure the user-local binary directory is available in interactive SSH shells using the smallest
  necessary shell change, if the installers do not handle it safely.
- Authenticate interactively using subscription-backed flows.
- Inspect credential **metadata only**: existence, owner, group, and mode. Never print content.
- Create a disposable Git repository containing non-sensitive fixtures; run equivalent bounded
  exercises with both CLIs; inspect diffs before accepting changes; remove the workspace afterwards.
- Document install, login/logout, status, update, diagnostics, usage-limit behavior, permission
  posture, and credential revocation/removal.
- Repair or explicitly disposition the MacBook Codex launcher.

### Out of scope

- API keys, API credits, direct API calls, gateways, model routing, fallback logic, or token-cost
  experiments.
- Telegram, bots, web interfaces, daemons, scheduled jobs, `systemd` services, CI, MCP servers,
  plugins, hooks, or unattended agents.
- Cloning the public Home Lab repository onto the node.
- Giving an AI tool blanket access to the administrator's home directory, SSH keys, Docker socket,
  or `sudo`.
- Installing an agent framework or creating the Phase 08 router/executor abstraction early.
- Running either CLI inside Docker solely because Docker is now available.

## 8. Validation / tests

### Installation and provenance

- [ ] Both installer URLs still resolve to vendor-owned HTTPS endpoints.
- [ ] Downloaded installer scripts are saved, inspected, and hashed before execution.
- [ ] Installation runs as `aleix`, not root; no system package or account change occurs.
- [ ] `command -v claude` and `command -v codex` resolve in a fresh SSH login.
- [ ] `claude --version`, `claude doctor`, and `codex --version` succeed; exact versions recorded.

### Authentication and billing boundary

- [ ] Relevant API-key environment variables remain unset.
- [ ] Claude status identifies subscription-backed login, not Console/API-key billing.
- [ ] `codex login status` identifies ChatGPT login, not API-key login.
- [ ] Credential files, if used, belong to `aleix` and are mode `0600`; contents never enter output,
  shell history, repository files, or chat.
- [ ] Logout/revocation commands and consequences are documented without destroying the working
  login during the phase.

### Agent behavior

- [ ] Each CLI reads only the disposable fixture and answers a bounded question correctly.
- [ ] Each CLI performs one controlled edit; the owner reviews the resulting Git diff.
- [ ] At least one command or edit is declined/not approved, demonstrating the approval path.
- [ ] Neither exercise uses unrestricted or approval-bypass mode.
- [ ] Usage-limit behavior is observed or documented from current official guidance, including the
  owner's real five-hour-limit event that interrupted Phase 05.

### Final host state

- [ ] No Claude or Codex process remains after the exercises.
- [ ] No new listening socket, container, systemd service, user, group, or sudo rule exists.
- [ ] Docker inventory remains zero.
- [ ] Root filesystem headroom is recorded before and after.
- [ ] `systemctl is-system-running` returns `running`; `systemctl --failed` shows no failed units.
- [ ] Fresh SSH connections work over both the Tailscale and LAN aliases.

## 9. Security considerations

### 9.1 AI coding agents execute with the operator's authority

Both CLIs run as `aleix`. That account can read its own SSH and AI credentials, invoke rootful
Docker without a password, and request `sudo`. A provider permission prompt helps the owner review a
proposed action, but it is not an operating-system identity boundary. A mistaken approval can still
have administrator-level consequences.

The phase therefore uses a fixture with no secrets, begins with default/restricted permissions, and
does not grant either agent blanket access to the home directory or Docker socket.

### 9.2 Prompts and context leave the node

Subscription-backed does not mean local. Prompts, selected file contents, command output, and other
context required for a task are sent to the chosen provider. Do not point either CLI at secrets,
private keys, credential stores, personal data, or future Second Brain content. Data controls and
retention policy must be documented at the level current official material supports; do not infer
that two providers behave identically.

### 9.3 Credential files are secrets

Current official documentation says Claude stores Linux credentials in
`~/.claude/.credentials.json` with mode `0600`. Codex may use `~/.codex/auth.json` or an operating
system credential store; file-based `auth.json` contains access tokens and must be treated like a
password. Only metadata is inspected. Neither file belongs in the public repository, backups,
screenshots, logs, or chat.

### 9.4 Subscription and API paths must not blur

An `ANTHROPIC_API_KEY` can take precedence over Claude subscription OAuth and cause API charges.
Codex also supports API-key login, but this phase forbids it. Before every billing validation, check
only whether billing-related variables are set, never their values, then use the CLI's own status
view to identify the active method.

### 9.5 Headless authentication

One-time login URLs and device codes are temporary credentials. Show them only to the owner and do
not record them. Codex device authentication is preferred. If Claude's browser callback cannot
complete from SSH, use the vendor-supported interactive fallback discovered at implementation time;
do not improvise credential copying without recording the trade-off.

### 9.6 Phase boundary

Personal OAuth credentials belonging to `aleix` must not be inherited automatically by the Phase 07
Telegram bot or a Phase 08 executor. A user-facing service must have its own unprivileged identity
and an explicit, supportable authentication model under ADR-011.

## 10. Repository changes expected

| Path | Change |
|---|---|
| `docs/handovers/06-ai-cli-access.md` | This brief |
| `scripts/server/` | Small user-scoped installer/preflight helper if repetition or safety justifies it |
| `guide/06-ai-cli-access/README.md` | Human-facing guide and reference-build experience |
| `docs/reference/ai-cli-reference.md` | Concise operational commands, auth locations, and diagnostics |
| `docs/build-log/2026-09-09-phase-06-ai-cli-access.md` | Actual install/login/test record, including failures |
| `docs/handovers/06-ai-cli-access-handover.md` | Structured handover to Phase 07 |
| Project indexes/state/cost/software docs | Update at phase close |

No credential file, login URL/code, token, account email, API key, or unredacted status dump is a
repository artifact.

## 11. Guide documentation required

The guide must explain:

- what Claude Code and Codex are in this project, and what they are not;
- native installation and why Node.js/Docker are unnecessary here;
- subscription login versus API-key billing;
- headless OAuth/device-code flow without exposing credentials;
- credential storage, logout, revocation, updates, diagnostics, and usage limits;
- a comparable disposable-workspace exercise for both tools;
- approval prompts, sandboxing, working-directory scope, and the limits of each control;
- the real reference-build failures: Claude's Phase 05 usage-window stop and the broken MacBook
  Codex launcher;
- why these operator tools are not yet the Telegram/router execution architecture.

## 12. Project documentation required

At completion, update:

- `README.md`, `ROADMAP.md`, and `CHANGELOG.md`;
- `docs/reference/project-state.md`;
- `docs/reference/software-stack.md` with installed and tested versions;
- `docs/reference/costs.md` with the owner's actual subscription costs, distinguishing total
  recurring cost from project-specific incremental cost;
- `docs/architecture/current-architecture.md` without claiming a router or service exists;
- guide, handover, build-log, script, and decision indexes as applicable.

## 13. ADRs required / possible

No new ADR is required merely to implement ADR-008.

Create one only if the phase makes a cross-phase decision about unattended subscription use,
credential ownership, auto-update policy, or the boundary between the future router and provider
CLIs. Do not smuggle such a decision into a guide or local config.

## 14. Costs

The CLI software and native installers are expected to add **0 DKK**. The existing Claude and
ChatGPT subscriptions are not free merely because they pre-date Home Lab. Before closing the phase,
record for each:

- plan name;
- actual recurring price and billing currency;
- DKK and approximate EUR equivalent where practical;
- project-specific incremental cost, expected to be zero if the plan was already owned;
- whether paid usage credits/overage are disabled or enabled.

No API or usage-credit spend is authorized by this brief.

## 15. Definition of Done

- [ ] Functional objective works.
- [ ] Configuration/setup is reproducible.
- [ ] Validation/tests have passed.
- [ ] Important security implications were considered.
- [ ] Relevant repository files are committed.
- [ ] Human-facing guide is updated.
- [ ] Project/internal documentation is updated.
- [ ] ADRs are created or updated where necessary.
- [ ] Actual costs are recorded where applicable.
- [ ] Problems, failed approaches, and lessons are recorded.
- [ ] Tested versions are recorded.
- [ ] No unexplained critical AI-generated component remains.
- [ ] `main` represents a known-working state.
- [ ] The system reports no failed units and no degraded state.
- [ ] A structured handover is written into `docs/handovers/`, stating what Phase 07 inherits.

## 16. Return handover requirements

Address the handover to **Phase 07 — Telegram Interface** and state explicitly:

1. Which CLIs and versions are installed, where, how they update, and whether any process is left
   running.
2. Which authentication **classes** are active and where credentials live, without identifiers or
   secret values.
3. The measured permission and sandbox behavior, especially that `aleix` has `docker` and `sudo`
   authority while a future Telegram service must not.
4. That subscription usage limits are shared/finite and cannot be treated as an availability SLA.
5. Whether unattended or service use of personal subscription credentials remains unresolved for
   Phase 08.
6. The exact final process, listener, Docker, disk, SSH-route, and system-health state.
7. Costs, failures, deferred controls, and any decision the next phase must not silently inherit.
