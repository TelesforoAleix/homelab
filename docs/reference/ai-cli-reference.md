# AI CLI Reference

Operational counterpart to [`guide/06-ai-cli-access/README.md`](../../guide/06-ai-cli-access/README.md).
The guide explains the model and the trade-offs; this is the page to use while operating or
diagnosing the installed tools.

- **Claude Code:** `2.1.236` stable, installed for `aleix`
- **Codex CLI:** `0.153.4`, installed for `aleix`
- **Authentication:** Claude subscription OAuth and Codex Sign in with ChatGPT
- **API keys:** none configured by Phase 06
- **Services:** none; both are interactive commands, not daemons

## Command paths

Both launchers are under the user's local binary directory:

```text
/home/aleix/.local/bin/claude
/home/aleix/.local/bin/codex
```

An interactive `ssh homelab` terminal reads `/home/aleix/.bashrc`, where the Codex installer added
`~/.local/bin` to `PATH`. A one-line remote command does not reach that late `.bashrc` block:

```bash
ssh homelab 'claude --version'                    # command not found
ssh homelab '~/.local/bin/claude --version'       # works
```

Use the absolute path in scripts and remote one-liners. Do not change the admin shell merely to
hide this distinction.

## Install or update

The project helper separates download/review from execution:

```bash
# From the repository on the MacBook
scp scripts/server/install-ai-clis.sh homelab:/tmp/

# On the server, as aleix (never sudo)
bash /tmp/install-ai-clis.sh stage /tmp/ai-cli-installers

# Read the files and compare the displayed hashes before this step
bash /tmp/install-ai-clis.sh install /tmp/ai-cli-installers
```

The staged hashes from the 2026-09-09 reference build were:

```text
3a68d3406cf674e17bed1733a4dcf37805e2e47d87417700007d7e1aa766a944  claude-install.sh
ba92dd27e5c06f0d3bbc58bfa4b9cfb6599cd2742fbb1f92a2765e6c07dedb5a  codex-install.sh
```

These identify what was reviewed; they are **not permanent expected hashes**. Vendor installer
content changes. A future run stages and reviews its own exact files.

The upstream endpoints are:

```text
https://claude.ai/install.sh
https://chatgpt.com/codex/install.sh
```

The Claude installer was run with the `stable` channel. `claude doctor` reported a native install
with automatic updates enabled on that channel. Both installers verify downloaded release artifacts
against vendor-published SHA-256 data and install without root. Re-run the reviewed install flow to
update Codex or to deliberately verify the current Claude installer and record new tested versions.

## Login and status

### Claude Code

```bash
claude auth login --claudeai       # subscription OAuth, not Console API billing
claude auth status
claude auth logout
```

For a status excerpt safe to paste into an operational log:

```bash
claude auth status |
  jq '{loggedIn, authMethod, apiProvider, subscriptionType}'
```

Expected authentication class on the reference node:

```json
{
  "loggedIn": true,
  "authMethod": "claude.ai",
  "apiProvider": "firstParty",
  "subscriptionType": "pro"
}
```

Do not use `--console` in Phase 06. That selects API usage billing.

### Codex

The reference node is headless, so use device authorization:

```bash
codex login --device-auth
codex login status
codex logout
```

Expected status:

```text
Logged in using ChatGPT
```

Device authorization must first be enabled in ChatGPT Security Settings. Login codes and OAuth
URLs are temporary credentials: do not save them in notes, logs, screenshots, or the repository.

## Billing boundary

Check presence only. Never print the values:

```bash
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
```

An approved `ANTHROPIC_API_KEY` can take precedence over a Claude subscription login and cause API
charges. Codex also supports API-key login. Phase 06 uses neither.

Subscription allowance is finite. A limit response with a reset time is an account-capacity event,
not an installation failure. Do not work around it by enabling usage credits or switching to API
billing unless the owner explicitly changes the cost decision.

## Credential metadata

Linux file locations on this node:

```text
/home/aleix/.claude/.credentials.json
/home/aleix/.codex/auth.json
```

Both were mode `0600`, owned by `aleix:aleix`. Verify metadata without reading content:

```bash
stat -c '%n mode=%a owner=%U:%G' \
  ~/.claude/.credentials.json \
  ~/.codex/auth.json
```

The files contain renewable access credentials. Treat them like passwords. Never use `cat`, `jq`,
`cp` into the repository, or a recursive home-directory backup that publishes them.

### Local state beyond credentials

Observed state directories include:

```text
/home/aleix/.claude/sessions
/home/aleix/.codex/log
/home/aleix/.codex/shell_snapshots
/home/aleix/.codex/tmp
```

Treat the entire `.claude` and `.codex` trees as potentially sensitive, even when auth files are
excluded. `--no-session-persistence` and `--ephemeral` avoid a resumable exercise session; they are
not a promise that the clients write no logs, caches, temporary files, or update metadata.

### Logout and suspected exposure

```bash
claude auth logout
codex logout
```

These are destructive to the local authenticated session, not health checks. The next model-backed
use requires login again. If an OAuth file or one-time code may have been exposed, log out, use the
provider account's current security/session controls to revoke access, and authenticate again.
Deleting the local file alone is not evidence that a provider-side token has been revoked.

## Restricted exercises

### Claude read-only

Run only in a directory containing non-sensitive files:

```bash
claude -p \
  --safe-mode \
  --no-session-persistence \
  --permission-mode plan \
  --tools Read \
  --max-turns 3 \
  'Read README.md and summarize it in one sentence.'
```

`--safe-mode` disables user/project customizations such as hooks, plugins, MCP servers, and skills.
`plan` prevents implementation, and `--tools Read` narrows the available tool set.

For one synthetic controlled edit without creating a resumable session:

```bash
claude -p \
  --safe-mode \
  --no-session-persistence \
  --permission-mode acceptEdits \
  --tools "Read,Edit" \
  --max-turns 4 \
  'Append exactly one line containing violet to inventory.txt. Change nothing else.'
```

`acceptEdits` is appropriate here only because the workspace is disposable, the tool set is narrow,
and the exact Git diff is reviewed immediately. Use `manual` for ordinary interactive work.

### Codex read-only

```bash
codex exec \
  --ephemeral \
  --ignore-user-config \
  --sandbox read-only \
  --cd /path/to/disposable/repository \
  'Read README.md and summarize it in one sentence.'
```

On Linux, Ubuntu's `bubblewrap` package is installed (`0.11.1-1ubuntu0.1`). Codex may mention a
bundled fallback, but on this node the fallback could not create its sandbox while
`kernel.apparmor_restrict_unprivileged_userns = 1`. The distribution `bwrap` binary works with the
already-present `/etc/apparmor.d/bwrap-userns-restrict` profile. `/usr/bin/bwrap` is root-owned mode
`0755`, with no setuid bit.

Important automation trap: the failed sandbox run exited `0` after printing
`Unable to read README.md: the sandbox failed to start.` Do not treat process status alone as proof
that an AI task achieved its objective. Validate the output or expected filesystem state.

## Permission model

The safe default is a constrained workspace and explicit review:

| Tool | Restricted read | Workspace write | Never use on this host |
|---|---|---|---|
| Claude | `--permission-mode plan --tools Read` | interactive/manual approval or a narrow allowed-tool set in a disposable workspace | `--dangerously-skip-permissions` |
| Codex | `--sandbox read-only` | `--sandbox workspace-write` with normal approvals | `--dangerously-bypass-approvals-and-sandbox` |

An approval prompt and a sandbox are different controls. An approval asks a human; a functioning
sandbox enforces a boundary. Both tools still run under the Linux identity `aleix`, which has sudo
and root-equivalent Docker access. Do not point them at the whole home directory or assume a denied
prompt turns that account into a service sandbox.

## Diagnostics

```bash
claude --version
claude doctor
claude auth status | jq '{loggedIn, authMethod, apiProvider, subscriptionType}'

codex --version
codex login status

bash /tmp/verify-ai-cli-access.sh
```

Codex login diagnostics live under its configured log directory. Inspect logs locally and redact
before sharing; do not paste an auth cache or token-bearing trace.

## Not a service boundary

These credentials belong to the human administrator. Phase 07's Telegram process must run as a
separate unprivileged account and must not inherit `/home/aleix`, the Docker group, or these OAuth
files. Phase 08 must decide separately whether personal subscription-backed CLIs are supported and
appropriate for unattended executor use.
