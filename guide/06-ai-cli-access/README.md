# 06 — AI CLI Access

## Goal

Install Claude Code and OpenAI Codex on the headless Home Lab node, sign in through existing
subscriptions, and learn what authority an AI coding agent actually receives before connecting one
to a bot or router.

By the end, both commands should work interactively over SSH without an API key, and you should be
able to answer three separate questions:

1. Is the client installed?
2. Is the account authenticated through the intended billing path?
3. Does the client have a functioning local permission boundary?

Those states can disagree. They did on the reference build.

## Why this matters

Home Lab eventually wants this shape:

```text
interface -> router -> executor -> tool/model
```

Claude Code and Codex are the first model-backed tools, but Phase 06 does **not** build that
architecture yet. They run interactively as the human administrator. Phase 07 adds an unprivileged
Telegram interface; Phase 08 decides how executors fit behind it.

That separation matters because an interactive coding agent is unusually powerful. It can read
files for context, propose edits, and run commands. On this node it runs as `aleix`, an account that
has sudo and root-equivalent access to Docker. A friendly confirmation dialog does not turn that
account into a low-privilege service.

This phase therefore starts with disposable files and deliberately constrained modes.

## Subscription access is not API access

The model provider and the billing path are separate choices.

| Login path | Allowance / billing | Phase 06 |
|---|---|---|
| Claude account with Pro/Max | Claude subscription allowance | **Used** |
| Anthropic Console API key | Usage-based API billing | Not used |
| Sign in with ChatGPT | ChatGPT plan's Codex allowance | **Used** |
| OpenAI API key | Usage-based API billing | Not used |

An installed CLI does not answer which row is active. Verify with the tool's status command.

This is especially important for Claude Code: an approved `ANTHROPIC_API_KEY` environment variable
can take precedence over subscription OAuth and produce API charges. “I logged in with Pro last
week” is not evidence about today's process environment.

Subscription access also has limits. Claude and Claude Code share the plan's allowance, and Codex
usage is finite under the ChatGPT plan. A message saying a window resets at a certain time means the
client is installed and the account is known, but there is no remaining capacity in that window.
Phase 06 waits; it does not silently turn on paid overage.

On the reference build, the owner already pays 23.00 EUR/month for the ChatGPT subscription used by
Codex and 22.50 EUR/month for Claude Pro: 45.50 EUR/month total, approximately 339 DKK/month. Both
pre-date Home Lab, so Phase 06's incremental cost is 0 DKK. Existing does not mean free; it means the
project depends on a cost already being paid.

Official references checked for this phase:

- [Claude Code installation](https://code.claude.com/docs/en/installation)
- [Claude Code authentication](https://code.claude.com/docs/en/authentication)
- [Using Claude Code with Pro or Max](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan)
- [Codex CLI installation](https://learn.chatgpt.com/docs/codex/cli)
- [Codex authentication](https://learn.chatgpt.com/docs/auth)
- [Codex sandbox prerequisites](https://learn.chatgpt.com/docs/sandboxing)

## Reference-build choice

The M700 uses:

- vendor-native Linux installers, downloaded for inspection instead of piped directly to a shell;
- a user-scoped installation under `/home/aleix` with no sudo;
- Claude Code's delayed `stable` channel;
- Codex's current standalone release;
- Claude subscription OAuth selected explicitly with `--claudeai`;
- Codex Sign in with ChatGPT through device-code authorization;
- Ubuntu's `bubblewrap` package for the Codex Linux sandbox;
- no Node.js, npm, Docker container, API key, daemon, or persistent AI process.

Native installers suit this phase better than npm. Node.js would exist only to host two commands,
not because Home Lab needs a JavaScript runtime yet. Docker would add OAuth mounts and workspace
mapping without creating a service boundary: a container with the administrator's source tree and
credentials mounted into it still has the valuable things.

## Alternatives

### npm or a package manager

Both tools have had package-manager installation paths. They can be reasonable on a workstation
that already manages Node or Homebrew deliberately. The reference node had neither Node nor npm,
and both vendors currently offer native installers.

Package-manager identity still needs checking before cleanup. On the reference MacBook, Codex's
standalone installer saw `/opt/homebrew/bin/codex` and guessed “brew-managed.” It was actually an npm
global package installed under Homebrew's Node prefix. Accepting the offered cask removal would have
run the wrong uninstall command.

### Direct APIs

APIs are the right interface for many unattended services: explicit credentials, request schemas,
metering, and provider-supported automation. They are intentionally deferred. Starting there would
mix CLI learning with API architecture and usage billing, contradicting ADR-008.

### Local models

Local inference avoids sending prompts to a hosted provider, but the M700 is an orchestration node
with 8 GB RAM, not a serious local inference machine. Local models remain a later comparison, not a
substitute smuggled into this phase.

## Prerequisites

- Ubuntu Server 20.04 or newer for Claude Code; the reference build uses Ubuntu 26.04.1 LTS.
- `x86_64` or another architecture supported by both installers.
- `curl`, Git, and outbound HTTPS.
- `jq` for a safely reduced Claude auth-status view.
- `bubblewrap` on Linux for Codex sandboxing.
- A Claude plan that includes Claude Code; the reference login reports Pro.
- A ChatGPT account with Codex access and device authorization enabled in Security Settings.
- A non-sensitive disposable directory for the first exercises.

No repository clone is required on the node. The canonical Home Lab checkout remains on the
MacBook.

## 1. Establish the baseline

Do not print environment-variable values or credential content:

```bash
ssh homelab

command -v claude || echo 'claude absent'
command -v codex || echo 'codex absent'
command -v node || echo 'node absent'
command -v npm || echo 'npm absent'

for variable in \
  ANTHROPIC_API_KEY \
  ANTHROPIC_AUTH_TOKEN \
  CLAUDE_CODE_OAUTH_TOKEN \
  OPENAI_API_KEY \
  CODEX_ACCESS_TOKEN
do
  if printenv "$variable" >/dev/null 2>&1; then
    echo "$variable: SET"
  else
    echo "$variable: unset"
  fi
done

systemctl is-system-running
systemctl --failed --no-pager
df -h /
```

The reference node began healthy, with all five variables unset and both credential files absent.

## 2. Stage and inspect the installers

From the repository on the MacBook:

```bash
scp scripts/server/install-ai-clis.sh homelab:/tmp/
```

Then on the server, as `aleix`:

```bash
bash /tmp/install-ai-clis.sh stage /tmp/ai-cli-installers
```

This downloads without executing. It checks shell syntax and writes `SHA256SUMS` beside the exact
files. Read them before continuing:

```bash
less /tmp/ai-cli-installers/claude-install.sh
less /tmp/ai-cli-installers/codex-install.sh

rg -n '\b(sudo|su |doas|apt|dnf|yum|apk)\b' /tmp/ai-cli-installers
rg -n '(\.local|/usr|install|checksum|sha256|PATH|profile)' /tmp/ai-cli-installers
```

The review should establish:

- which vendor endpoints provide release files;
- which paths under the home directory will change;
- whether either script invokes sudo or a system package manager;
- how release checksums are obtained and validated;
- whether a shell profile will be edited;
- which update channel/version is selected.

Now execute the exact staged files:

```bash
bash /tmp/install-ai-clis.sh install /tmp/ai-cli-installers
```

The helper verifies `SHA256SUMS` again and asks before execution. Never run it through sudo.

Open a new interactive SSH terminal, then check:

```bash
command -v claude
claude --version
command -v codex
codex --version
```

`claude doctor` on the reference node reported a native installation with automatic updates enabled
on the stable channel. That is convenient, but it also means the binary can change between phases.
Record and re-test the actual version after a material update.

### Why a remote one-liner says “command not found”

This works in an interactive terminal but not as a bare remote command:

```bash
ssh homelab 'claude --version'       # command not found on this host
```

Ubuntu's `.bashrc` returns early for a non-interactive shell. The installer's `~/.local/bin` PATH
block is later in the file, so that one-liner never sees it. Use the absolute path:

```bash
ssh homelab '~/.local/bin/claude --version'
ssh homelab '~/.local/bin/codex --version'
```

Interactive terminals and non-interactive commands are different execution environments. Keeping
that visible is healthier than changing the admin account's shell startup to make a demo prettier.

## 3. Install the Codex Linux sandbox prerequisite

Current official Codex guidance says Linux and WSL2 should provide `bubblewrap` through the system
package manager:

```bash
sudo apt install bubblewrap
```

On Ubuntu 26.04, the AppArmor profile already exists at
`/etc/apparmor.d/bwrap-userns-restrict`; no global weakening of
`kernel.apparmor_restrict_unprivileged_userns` is required.

Verify:

```bash
bwrap --version
aa-status | grep bwrap || true
sysctl kernel.apparmor_restrict_unprivileged_userns
```

Do not “fix” this by setting the AppArmor restriction to `0`. Installing the small distribution
package gives Codex the named sandbox binary and policy that the OS knows how to confine. On the
reference node, `/usr/bin/bwrap` is root-owned mode `0755`, not setuid.

## 4. Authenticate without an API key

### Claude subscription

On the server:

```bash
claude auth login --claudeai
```

The headless terminal prints an OAuth URL. Open it on the MacBook, approve the request, and paste the
one-time code back into the waiting terminal. Do not save either value.

Verify only the non-personal fields:

```bash
claude auth status |
  jq '{loggedIn, authMethod, apiProvider, subscriptionType}'
```

The reference build showed `authMethod: claude.ai`, `apiProvider: firstParty`, and
`subscriptionType: pro`.

### Codex through ChatGPT

First enable device-code authorization in ChatGPT Security Settings. Then:

```bash
codex login --device-auth
```

Open the displayed URL on the MacBook and type the one-time code. If the account setting was enabled
after a code was generated, cancel and generate a fresh code.

Verify:

```bash
codex login status
# Logged in using ChatGPT
```

### Credential metadata, never content

```bash
stat -c '%n mode=%a owner=%U:%G' \
  ~/.claude/.credentials.json \
  ~/.codex/auth.json
```

Both should be `mode=600 owner=aleix:aleix`. That is all this validation needs to know.

### Logging out or responding to exposure

Do not use logout as a diagnostic command. It intentionally removes the local authenticated session,
so the next model-backed command requires a new browser/device login:

```bash
claude auth logout
codex logout
```

If a credential file, OAuth URL, or one-time code may have been exposed, log out, use the provider
account's current security/session controls to revoke access, then authenticate again. Merely
deleting a file on the node does not prove the provider-side token was revoked.

### Conversation and operational state

Credential files are not the only local state. The reference node also created directories such as:

```text
~/.claude/sessions
~/.codex/log
~/.codex/shell_snapshots
~/.codex/tmp
```

Do not assume they contain only harmless metadata, and do not publish them. The exercise flags
`--no-session-persistence` and `--ephemeral` avoid resumable exercise sessions. They do not promise
that no logs, caches, temporary files, or update metadata are written anywhere under the clients'
state directories.

## 5. Build a disposable exercise

Use synthetic text, not the administrator's home directory or the real project:

```bash
fixture=/tmp/phase06-ai-cli-lab
install -d -m 700 "$fixture"

printf '%s\n' \
  '# Phase 06 Fixture' \
  '' \
  'This disposable project compares two interactive AI CLIs.' \
  'The validation phrase is: subscription CLI.' > "$fixture/README.md"

printf '%s\n' amber cobalt fern > "$fixture/inventory.txt"

git -C "$fixture" init
git -C "$fixture" config user.name 'Phase 06 Fixture'
git -C "$fixture" config user.email 'fixture@invalid.example'
git -C "$fixture" add README.md inventory.txt
git -C "$fixture" commit -m 'fixture baseline'
```

The local Git identity is intentionally fake and scoped only to the disposable repository.

## 6. Exercise Claude conservatively

Read-only, with customization and session persistence disabled:

```bash
cd /tmp/phase06-ai-cli-lab

claude -p \
  --safe-mode \
  --no-session-persistence \
  --permission-mode plan \
  --tools Read \
  --max-turns 3 \
  'Read README.md and report its validation phrase.'
```

Then try asking it to modify `inventory.txt` without changing the restricted flags. It should not
silently perform the edit. This is the denied-action exercise.

For one controlled write in this synthetic fixture, keep print mode non-persistent, expose only the
read/edit tools, request one exact line change, and review it immediately:

```bash
claude -p \
  --safe-mode \
  --no-session-persistence \
  --permission-mode acceptEdits \
  --tools "Read,Edit" \
  --max-turns 4 \
  'Append exactly one line containing violet to inventory.txt. Change nothing else.'

git diff -- inventory.txt
```

### What this exercise actually showed

All three runs behaved correctly on **permission**. The third did not behave correctly on
**precision**, and that is the more useful result.

| Exercise | Outcome |
|---|---|
| Read, plan mode, `--tools Read` | Returned the exact phrase. Tree clean. |
| Write requested, plan mode, `--tools Read` | **Refused.** File SHA-256 identical before and after. |
| Write permitted, `acceptEdits`, `--tools "Read,Edit"` | Wrote `violet` — **and an unrequested blank line**. |

The instruction was *"Append exactly one line containing violet. Change nothing else."* The baseline
was three lines (`amber`, `cobalt`, `fern`); the result was five. Worse, the model's summary said it
was "leaving the existing content (including the blank line 4) unchanged" — **there was no blank
line 4**. It described the file wrongly and reported success.

Nothing outside `inventory.txt` was touched, so the tool grant held. But notice what the tool grant
did and did not buy you:

> **Narrow tooling is a containment control, not a correctness control.** It limits what an agent
> *may* touch. It says nothing about whether the permitted action was the right one, and nothing
> about whether the summary you are reading is true.

The thing that caught this was `git diff` against a baseline committed **before** the run — a
two-second check on a three-line file. On a real change, that review is the only thing standing
between a confident summary and a wrong repository.

**Review the diff, not the summary.** That is the habit worth taking from this phase, and it is why
the fixture is a Git repository rather than a loose directory.

`acceptEdits` automatically accepts edits, so use it only for this disposable, narrowly tooled
exercise. For ordinary interactive work, use `--permission-mode manual`, approve one operation at a
time, and do not select “always allow,” enable bypass mode, or broaden the working directory.

## 7. Exercise Codex conservatively

Read-only and ephemeral:

```bash
codex exec \
  --ephemeral \
  --ignore-user-config \
  --sandbox read-only \
  --cd /tmp/phase06-ai-cli-lab \
  'Read README.md and report its validation phrase.'
```

Ask for a file edit with the same read-only mode and verify the Git tree stays clean. Then permit a
single controlled write inside the fixture:

```bash
codex exec \
  --ephemeral \
  --ignore-user-config \
  --sandbox workspace-write \
  --cd /tmp/phase06-ai-cli-lab \
  'Append exactly one line containing azure to inventory.txt. Change nothing else.'

git -C /tmp/phase06-ai-cli-lab diff -- inventory.txt
```

The exact CLI may report an approval policy alongside the sandbox. Read both. The sandbox is the
enforced boundary; the approval policy decides when a request crosses it.

## 8. Validate and clean up

Copy and run the repository verifier:

```bash
# MacBook
scp scripts/server/verify-ai-cli-access.sh homelab:/tmp/

# Server, after both test sessions have exited
bash /tmp/verify-ai-cli-access.sh
```

Review the fixture diff, then remove only that explicit disposable directory:

```bash
rm -rf /tmp/phase06-ai-cli-lab
```

Finally, from the MacBook:

```bash
ssh -o ControlPath=none homelab true
ssh -o ControlPath=none homelab-lan true
```

Phase 06 does not touch network configuration, but every phase still finishes by proving the node is
healthy and reachable.

## Security notes

### Credentials are ordinary Linux files

On macOS, a client may use the system keychain. On this Linux server, both credentials are files in
the administrator's home directory. Mode `0600` stops other Unix users; it does not stop a process
already running as `aleix`.

Do not print, parse, copy, back up into a public location, or expose:

- `~/.claude/.credentials.json`;
- `~/.codex/auth.json`;
- browser OAuth URLs or one-time device codes;
- account email addresses or unredacted status output.

### Context is sent off the node

These are hosted models. Prompts, chosen file content, tool results, and other task context leave the
node for the selected provider. Subscription-backed means “covered by that account's allowance,”
not “runs locally.” Do not point either tool at SSH keys, future personal knowledge data, or secrets.

### Approval is not identity isolation

Claude and Codex have different controls and vocabulary. Neither changes the Linux user. A command
approved for `aleix` can use whatever `aleix` can use, including the Docker socket. The Phase 07 bot
must be a different user and must not receive these personal OAuth files.

### Never use the bypass flags here

Do not use:

```text
claude --dangerously-skip-permissions
codex --dangerously-bypass-approvals-and-sandbox
```

Those switches have legitimate uses inside an external sandbox designed for them. The administrator
account on a real headless server is not that sandbox.

## Reference-build experience

Six failures made the conceptual boundaries visible:

1. Codex device login first failed because the account-level device authorization setting was off.
   Enabling it required a newly generated code.
2. The MacBook's stale npm Codex package retained its directory and launcher while its platform
   executable was absent. Replacing it with the standalone build fixed `ENOENT`.
3. The standalone installer guessed the stale path was Homebrew-managed and offered the wrong
   uninstall command. Inspection prevented that cleanup mistake.
4. Codex authenticated and reached its model, but the first read failed because Linux `bubblewrap`
   was missing. Worse, the command exited `0`; output and filesystem state, not exit status alone,
   revealed the failure.
5. Claude authenticated successfully while inference remained blocked until its five-hour Pro
   session allowance reset at 18:00 UTC. No API-billed fallback was introduced.
6. The Claude one-time authorization code was pasted into the agent conversation before being
   entered into the waiting terminal. It was consumed and never entered the repository, but it was
   still a credential-handling mistake. Paste future codes directly into the terminal.

There was also a smaller shell lesson: a new interactive terminal found both commands, while a new
non-interactive SSH one-liner did not. “Fresh connection” is not a complete description of shell
startup behavior.

## Tested versions

| Component | Tested with | Requirement |
|---|---|---|
| Ubuntu Server | 26.04.1 LTS | Claude documents Ubuntu 20.04+; both vendors support Linux |
| Claude Code (server) | 2.1.236, stable channel | Exact version not pinned |
| Codex CLI (server) | 0.153.4 | Exact version not pinned |
| Codex CLI (MacBook) | 0.153.4 standalone | Exact version not pinned |
| Bubblewrap | 0.11.1-1ubuntu0.1 | Required for reliable Codex sandboxing on this Linux node |

The tested version records a known experience; it is not a promise that a hosted AI client or its
default model remains unchanged.

## Next phase

Phase 07 builds the minimal Telegram interface. It inherits working operator CLIs, but not permission
to use their personal credentials or run as `aleix`. The bot stays deterministic and unprivileged;
provider-backed executors remain Phase 08 work.
