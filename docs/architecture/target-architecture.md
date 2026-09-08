# Target Architecture Direction

This is a direction, not a promise that every component will be installed.

```text
Interfaces
├── Telegram
├── future web/API interfaces
└── other inputs
        │
        ▼
      Router
        │
        ├── Claude executor
        ├── Codex executor
        ├── controlled shell/tools
        ├── knowledge retrieval
        └── future executors/providers
                │
                ▼
     Services / Models / Data
        ├── hosted models
        ├── databases
        ├── automation
        ├── project/personal knowledge
        └── optional future CUDA node
```

## Principles

- Model-agnostic routing.
- Explicit interface/router/executor boundaries.
- Controlled privilege separation.
- Storage separate from intelligence.
- Progressive containerization and automation.
- Optional local-AI node rather than forcing GPU workloads onto the M700.

Do not convert this diagram into a shopping list. Components are introduced only when a phase has a concrete requirement.
