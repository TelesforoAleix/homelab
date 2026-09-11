# Instructions for AI Agents

Read these files before material work:

1. `PROJECT.md`
2. `ROADMAP.md`
3. `docs/reference/target-architecture.md` — what the system is meant to *be*
4. `docs/reference/project-state.md`
5. the relevant phase handover/brief under `docs/handovers/`
6. relevant ADRs under `docs/decisions/`

## Operating rules

- Treat the repository as the canonical project memory.
- Do not contradict accepted ADRs silently. If a decision needs changing, propose a new ADR that supersedes the old one.
- Do not invent current system state. Verify from repository files or live system output when available.
- Keep `guide/` explanatory and `docs/` operational.
- Prefer minimal, comprehensible implementations before frameworks or additional services.
- Do not add Redis, PostgreSQL, n8n, queues, gateways, or other infrastructure merely because they are common in AI stacks. Add them only when the phase has a concrete need.
- Never commit secrets, tokens, passwords, private keys, environment files containing credentials, or personal data.
- Never make a Telegram/user-facing service root by default.
- Treat destructive shell commands, privilege changes, firewall changes, package removal, database destruction, Docker pruning, shutdown, and reboot as high-impact operations requiring explicit justification and appropriate confirmation/control.
- **The reference node is headless, with a console available on demand.** The monitor and keyboard
  are detached by choice; the connectors are present and console login is tested. Before any change
  touching network, remote access, authentication, boot, or the admin account, apply
  [`docs/standards/safe-changes-headless.md`](docs/standards/safe-changes-headless.md) (ADR-041,
  superseding ADR-020). Classifying the change is the control; the checklist only helps once you have
  noticed it applies. **Lockout-class means recovery needs physical access** — a cost, not a
  catastrophe. An operation no physical access recovers from needs a verified restore first.
- Record versions tested and meaningful validation results.
- Update costs when a phase creates a new paid dependency.
- Record failures and reversals rather than hiding them.
- Keep changes scoped to the current phase. A cross-phase change is recorded as an ADR and carried
  into the next phase's brief, never applied silently (ADR-017).

## AI-generated work standard

AI generation is expected. For important components, produce enough explanation/tests/documentation that a technically curious non-sysadmin owner can understand what the component does and safely modify it later.

## Phase structure

Phases are self-contained and sequential; there is no separate planning context (ADR-017). Each phase
writes its own brief from `docs/templates/phase-brief-template.md` and **commits it before
implementation begins**.

## Phase completion

Use `docs/templates/phase-handover-template.md` and the Definition of Done in `PROJECT.md` before
declaring a phase complete. Apply the checklist literally — it is the only standing quality check.
The handover must state what the next phase inherits.
