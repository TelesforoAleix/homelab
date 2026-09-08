# 00 — Project Overview

## What are we building?

Home Lab is a small self-hosted AI platform built progressively on inexpensive hardware. It starts as an orchestration server using hosted AI models and grows into a laboratory for agents, tool execution, knowledge retrieval, automation, model routing, security, and potentially local AI.

A simplified long-term direction is:

```text
Interfaces
   ↓
Router
   ↓
Executors / Agents
   ↓
Models + Tools + Knowledge + Services
```

## Why build it manually?

Large agent frameworks can hide useful complexity. Because the objective is learning, Home Lab begins with simple explicit components and introduces abstractions only after the underlying mechanism is understood.

## Reference workflow

```text
MacBook Pro
    │
    │ SSH / Tailscale / VS Code Remote
    ▼
M700 — Ubuntu Server
    │
    ├── Git repository
    ├── Docker / Compose
    ├── services
    ├── model CLIs / APIs
    ├── agents / executors
    └── knowledge / project files
```

## What this project is not

- A race to deploy a polished personal assistant.
- A benchmark for running the largest possible local model on cheap hardware.
- A prescription that every reader must buy the same Lenovo model.
- A production security reference architecture from day one.

Instead it is a documented reference build that becomes more robust as capabilities are introduced.

## How to use the repository

Follow the numbered guides for implementation. Use the M700 build as the canonical example while applying the hardware-selection criteria to your own machine.
