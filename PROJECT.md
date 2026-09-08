# Home Lab — Project Contract

This file is the concise working contract for the Home Lab repository. Humans and AI agents should read it before making material changes.

## 1. Purpose

Home Lab is a learning-first, self-hosted AI infrastructure project. It progressively builds a modular platform where different interfaces can submit requests, different models or agents can process them, and controlled tools/services can execute work.

The repository serves three purposes:

1. Run the actual reference Home Lab.
2. Teach others how and why it was built.
3. Preserve enough state and documentation that the system can be reproduced or replaced.

## 2. Audience

Primary audience: business/technical users who are comfortable with computers and some programming, but are not experienced Linux/system administration engineers.

The guide should explain enough to support good decisions without becoming a general-purpose textbook.

## 3. Reference implementation

Canonical node:

- Lenovo ThinkCentre M700 Tiny
- Intel Core i5-6600T
- 8 GB DDR4 at project bootstrap; verified in Phase 01 Part A as 1 × 8 GB with one slot free
- 256 GB SSD
- Wi-Fi + Bluetooth
- Purchased used for 700 DKK

Role: orchestration, infrastructure, agents, databases/services, and project storage — not serious local LLM inference.

Primary development interface: MacBook Pro.

Target OS: Ubuntu Server LTS, headless.

Remote workflow: SSH + SSH keys + Tailscale + VS Code Remote SSH.

## 4. Architecture principles

- Remain model-agnostic.
- Start with an explicit `interface -> router -> executor -> tool/model` architecture.
- Build the simple mechanisms manually before evaluating large agent frameworks.
- Keep storage/knowledge separate from the intelligence consuming it.
- Increasingly containerize services where that improves reproducibility and isolation.
- Do not make user-facing bot services root.
- Separate privileged execution from interfaces and routers.
- Gate destructive actions until an explicit safer control model exists.
- Add infrastructure only when a concrete problem justifies learning/using it.

## 5. AI model strategy

Initial AI tooling:

- Claude Code CLI where supported through the user's existing subscription.
- OpenAI Codex CLI where supported through the user's existing ChatGPT subscription.

Later phases may intentionally compare direct APIs, gateways, hosted providers, local models, routing, and fallback strategies.

Do not hard-code the system architecture around one model provider.

## 6. Development philosophy

AI tools may generate substantial code, configuration, tests, and documentation. This is intentional.

However, an important component is not complete merely because an AI generated it or because it appears to run. Before completion it should be:

- understandable at the level required to operate and modify it;
- testable;
- documented;
- reproducible;
- reviewed for meaningful security implications.

Use progressive automation: perform a process manually when doing so is useful for understanding; automate it once the mechanism is understood and repetition provides value.

## 7. Documentation model

### `guide/`
Human-facing learning material. Explain what is being done, why, what alternatives exist, and then provide reproducible commands/configuration.

### `docs/`
Operational project truth. Keep it concise. Record architecture, ADRs, current state, build history, actual costs, tested versions, and phase handovers.

Do not duplicate long explanatory material from `guide/` into `docs/`.

## 8. Repository workflow

- `main` should represent a known-working state.
- Use `feature/<name>` for unfinished product/infrastructure work.
- Use `experiment/<name>` for exploratory work that may be discarded.
- Keep commits scoped and understandable.
- Do not commit secrets, credentials, access tokens, private keys, or production data.
- Scripts/configuration should replace repetitive manual commands where practical, but the guide should still explain what automation does.

## 9. Version policy

Document versions actually tested.

Distinguish clearly between:

- **Tested with:** the version used by the reference implementation.
- **Requires:** a hard compatibility requirement.

Avoid unnecessary exact pinning.

## 10. Budget policy

Record:

- actual reference-build spending;
- one-time hardware/software costs;
- recurring subscription costs;
- usage-based API/gateway/token costs;
- rough reproduction ranges where useful;
- DKK and EUR where practical.

The reference build prioritizes used hardware and budget-friendly choices.

## 11. Failure transparency

Meaningful mistakes and reversals should be documented with:

1. Initial assumption or choice.
2. What happened.
3. What was learned.
4. What changed.

Do not rewrite project history to make it look linear.

## 12. Definition of Done

A phase is complete when all applicable items are satisfied:

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
- [ ] A structured handover is written into `docs/handovers/`, stating what the next phase inherits.

## 13. Governance

**The repository is the sole governance authority.** Phases are self-contained and run one after
another; each phase context owns its own brief, implementation and handover. See ADR-017, which
supersedes the earlier two-context model.

Each phase:

1. **Writes its brief first**, from `docs/templates/phase-brief-template.md`, and commits it *before*
   implementation begins. A brief written afterwards is documentation, not governance.
2. Implements, validating against the Definition of Done in §12 **literally, item by item**. It is
   now the only standing check on phase quality.
3. **Writes a handover** into `docs/handovers/`, addressed to the next phase, explicitly stating open
   risks, unsatisfied controls, and decisions the next phase must not silently inherit.

A cross-phase architectural decision is **recorded as an ADR** and carried into the next phase's
brief. It is never applied silently inside a phase.

Where an older document says "escalate to Project Planning", read it as "record an ADR and carry it
into the next phase's brief". Those documents are historical and are not rewritten (§11).
