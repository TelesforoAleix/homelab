# Model helper

A one-request-per-connection service that makes model calls on the bot's behalf.

It exists for a single reason: **`homelab-bot` cannot read either AI credential,
and must not gain the ability.** That was proved by attempting it in Phase 07 and
it is still proved on every run of `verify-telegram-bot.sh`. So the model call
happens here, as `aleix`, who already holds the credentials, and the bot asks
over a UNIX socket.

## Files

| File | Role |
|---|---|
| `helper.py` | The socket handler. Two operations: `ping`, `ask`. Not a shell. |
| `providers.py` | The provider abstraction plus Claude and Codex implementations |
| `limits.py` | Per-hour and per-day call caps, file-backed, `flock`-protected |
| `config.example.json` | Copy to `/etc/homelab-model-helper/config.json` |

## The protocol

Request — one JSON object, one line, then EOF:

```json
{"v": 1, "op": "ask", "user_id": 123, "question": "...", "context": "..."}
```

Response — one JSON object, one line:

```json
{"ok": true,  "provider": "claude", "model": "haiku", "text": "..."}
{"ok": false, "kind": "exhausted", "message": "...", "detail": ["..."]}
{"ok": false, "kind": "error", "message": "..."}
```

`op: "ping"` proves the socket works **without making a model call**, so the
install-time connectivity check costs no allowance.

Note what the caller cannot say: it cannot name a provider, a model, a binary,
a file or a path. All of those come from the root-owned config file. The wire
carries a question and nothing that selects behaviour.

## Cheapest models, and why these

| Provider | Model | Why |
|---|---|---|
| Claude | `haiku` | Cheapest tier. Works on Claude Pro; the alias is undocumented in `--help` but functional |
| Codex | `gpt-5.6-luna` | The subscription's mini tier. The binary's own catalogue records it as the replacement for **GPT-5.4 Mini** |

`gpt-5.4-mini` is in the CLI's embedded model catalogue but is **rejected** on a
ChatGPT account: *"The 'gpt-5.4-mini' model is not supported when using Codex
with a ChatGPT account."* A model appearing in the catalogue does not mean the
subscription can use it.

## The model has no tools

Both CLIs are agents; unrestricted they read files and run commands as `aleix`.
Tool use is disabled at the CLI and each call is given a fresh empty working
directory. This was verified with a canary file rather than assumed — see
`providers.py` and the Phase 09 build log.
