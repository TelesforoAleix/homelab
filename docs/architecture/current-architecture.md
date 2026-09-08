# Current Architecture

**State:** Pre-development / repository bootstrap

At this point the architecture is primarily a planned reference design rather than an installed server stack.

## Physical roles

```text
MacBook Pro
    │
    │ development / administration interface
    ▼
Lenovo ThinkCentre M700 Tiny
    │
    └── planned Ubuntu Server orchestration node
```

## Confirmed architectural direction

```text
Interface
   ↓
Router
   ↓
Executor
   ↓
Tool / Model / Service
```

The first remote interface is planned to be Telegram. Initial model executors are planned around Claude Code CLI and OpenAI Codex CLI where officially supported through existing subscriptions.

## Not implemented yet

- Ubuntu Server
- persistent remote-access configuration
- Docker/Compose baseline
- Telegram bot
- router/executor code
- knowledge/RAG services
- automation
- local GPU node

Update this document when a phase changes the actually deployed architecture.
