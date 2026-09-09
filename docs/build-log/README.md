# Build Log

This directory records what actually happened while building the reference Home Lab.

Unlike the guide, build-log entries may include dead ends, mistakes, unexpected hardware behavior, and changes of mind.

## Suggested naming

```text
YYYY-MM-DD-short-topic.md
```

Use [`../templates/build-log-template.md`](../templates/build-log-template.md).

## Recent entries

- [`2026-09-09-phase-08-router-executors.md`](2026-09-09-phase-08-router-executors.md) — the
  escalation boundary. Five problems: a brief that specified a mechanism the runtime forbids
  (second phase running), a test that asked the admin to restart `tailscaled` and then reported a
  pass for the wrong reason, an audit claim about polkit that measurement disproved, and the same
  reason-versus-outcome mistake repeated four minutes after writing the lesson down.
- [`2026-09-09-phase-07-telegram-bot.md`](2026-09-09-phase-07-telegram-bot.md) — the first service
  this project wrote. Five problems, four of them the author's: hardening that stopped a system-info
  reporter reading system info, an unguarded exception that became a restart loop on a console-less
  node, a disk figure double the truth and entirely plausible, and a verifier that reported a
  confident `FAIL` about a file it lacked permission to see — the fifth instance of that family.
- [`2026-09-09-phase-06-ai-cli-access.md`](2026-09-09-phase-06-ai-cli-access.md) — native Claude
  Code and Codex installation, subscription authentication, sandbox exercises, the broken MacBook
  launcher, and the difference between login health and available model capacity.
- [`2026-09-09-phase-05-docker-install.md`](2026-09-09-phase-05-docker-install.md) — Docker install
  on a console-less node, including the missing before-capture failure and the Docker/Tailscale
  packet-filtering baseline Phase 13 inherits.
