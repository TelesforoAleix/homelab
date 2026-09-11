# ADR-036: Factory Workbench's write path — a local server over a CLI engine

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** none. **Refines** ADR-035 §7, which it satisfies literally.
- **Superseded by:** none

## Context

ADR-035 established that Factory Workbench executes Factory project operations while a configured
backend executes AI. It said local Workbench *"binds to `127.0.0.1`"* and left the implementation
open. The Phase 20.0 brief made that §6.1, *"the decision that shapes the phase"*, and required it be
decided and justified before anything was built on it.

**Factory had already framed this decision and it was not noticed until now.** `roadmap.md` V1.5's
exit criterion reads *"No write actions are introduced before the CLI/server/webview bridge
decision"*; `design/open-questions.md` asks *"Should the first bridge be CLI-first?"*; and
`design/paperclip-style-management-interface.md` decomposes it into a Phase 4 CLI bridge
(`DASH-301`–`304`) followed by a Phase 5 writable control plane (`DASH-401`–`405`). This ADR resolves
that existing question rather than posing a new one.

Three facts constrain the answer, established by reading `factory` at `97ccb86`:

1. **A browser page cannot spawn `git`, `gh`, or a test runner.** Acceptance steps 4, 9, 10 and 12
   require exactly that. Factory's own analysis already lists these as out of browser reach.
2. **Browser writes require `showDirectoryPicker({ mode: "readwrite" })`, which is Chromium-only.**
   A browser-write Workbench cannot save on Firefox or Safari.
3. **`dashboard.js:223` is a hand-rolled ~25-line YAML subset parser** (`parseLooseYaml`). It handles
   top-level scalars and simple lists and **silently drops** nested maps, multi-line strings and
   inline collections. It does not error; it returns incomplete data.

Fact 3 is the one that was nearly missed. It is harmless in a read-only viewer and is a correctness
bug in a writable one: a real YAML library on the write side and `parseLooseYaml` on the read side
are two different definitions of *"what is a valid record"*, and they diverge the first time a record
nests.

## Decision

### 1. The CLI is the write engine; the server is a surface in front of it

Every write — record creation, status change, assignment, approval, review, release, and every git
operation — goes through **one validated code path**. That path is a `factory` CLI.

A **local server on `127.0.0.1`** sits in front of it and serves the dashboard, so the dashboard can
act directly: click to approve, assign, advance. The server does not implement writes. It calls the
same engine the CLI calls.

```text
browser (127.0.0.1)  ──HTTP──▶  server  ──▶  write engine  ──▶  ops/ + git
terminal             ─────────────────────▶  write engine  ──▶  ops/ + git
```

**The property that matters is that adding or removing a surface changes no write semantics.** A
webview, a second client, or a headless test harness are all additional callers of the same engine.
This is what keeps ADR-035 §4's adapter reasoning honest at the record layer too.

### 2. The owner chose click-to-act over the smaller phase, knowingly

Three options were put to the owner during Phase 20.0's §6.1 checkpoint. **The owner chose the local
server**, accepting a larger phase to get a writable interface now.

| Option | Ships | Cost |
|---|---|---|
| CLI-first, dashboard read-only | CLI + existing viewer | Two surfaces: view in browser, act in terminal |
| CLI-first + action composer | CLI + a UI that copies commands | Interactive-feeling; still not click-to-act |
| **CLI + local server** ← **chosen** | CLI + server + writable UI | A port, a runtime, this ADR |

The rejected options are recorded because they remain the fallback if the server proves troublesome:
the engine boundary in §1 means retreating to CLI-only costs the server, not the write path.

**This satisfies ADR-035 §7 literally** rather than reinterpreting it.

### 3. The server parses; the browser stops parsing

The server reads `ops/` and serves **JSON** to the browser. The browser no longer parses YAML.

This gives the system **exactly one parser and one validator**, which is the direct answer to fact 3.
`parseLooseYaml` is retired from the write path. It may be kept only as a degraded `file://` fallback
for viewing without the server running, and if it is kept, **it must be labelled as lossy** — a
partial parse that renders a record as though it were complete is worse than a refusal to render it.

### 4. Python, on the stdlib where possible

The write engine and the server are **Python**.

- It is homelab's existing service ground — `services/telegram-bot`, `services/model-helper` — so the
  owner already operates it, which is what `AGENTS.md`'s comprehensibility standard asks for.
- `http.server` is in the standard library, so the server itself adds no dependency.
- Python 3 is more reliably present on an adopter's machine than Node.

**"One language everywhere" was considered and is no longer load-bearing.** It would have been the
strongest argument for Node — matching the existing `dashboard.js` and sharing a parser — but §3
removes parsing from the browser, so there is nothing left to share. The dashboard stays vanilla JS
with no build step.

A YAML library is the **one accepted dependency**. Hand-rolling a second parser is precisely the
mistake being corrected.

### 5. The boundary that does not move

ADR-035 §2 is unchanged and this ADR must not be read as widening it: **Workbench holds no homelab
credential, no model registry, and no tool implementation.** A server does not change that. It
listens on the loopback interface only, has no application login because the OS user boundary is
sufficient for a single-user local tool, and **is not exposed publicly** (ADR-035 §7).

Factory's own safety rules are adopted rather than reinvented: no automatic commits, **no broad
filesystem write path**, show the source file for every rendered object, and every write validated
and audited with actor, timestamp and git visibility (`DASH-405`).

## Alternatives considered

**CLI-first, dashboard stays read-only.** Recommended by the assistant and **overruled by the owner**,
who wanted the interface to be interactive rather than a viewer beside a terminal. Recorded as a
disagreement; §1's engine boundary keeps it reversible.

**A server that implements writes directly, with no CLI engine underneath.** Simpler by one layer,
and rejected: it makes the server the only way to write, so tests, scripts and any future surface
must go through HTTP. The engine boundary costs little now and is expensive to introduce later.

**Node rather than Python.** Genuinely close, and it wins if the browser keeps parsing records. §3
removes that, and Python's advantages — the owner's operating ground, stdlib HTTP, adopter
availability — then decide it.

**Keep `parseLooseYaml` and write only what it can read.** Rejected: it constrains the record schema
to a parser's accidental limits, and it would be discovered as a constraint rather than chosen as
one. `v0-operating-objects.md` already anticipates nesting.

**A VS Code webview.** Factory's `DASH-401` lists it as an option. Deferred, not rejected: it is
another surface in front of the same engine and can be added without revisiting this ADR.

## Consequences

**Easier.** The dashboard becomes operational rather than informational — V3's control plane, which
Factory planned and never built. Every surface added later is a client of one engine.

**Harder.** Phase 20.0 is larger than its minimum: a server, a runtime, a port, and this ADR, none of
which the acceptance project strictly needed. The owner accepted that trade explicitly.

**Newly required.** A long-running local process, with whatever that implies for starting, stopping
and diagnosing it; a single YAML dependency; and a JSON contract between server and browser that is
now an interface with two sides.

**Constrained.** Writes may not bypass the engine, including from the server. The browser may not
parse records. Loopback only, no public exposure, and ADR-035 §2's boundary is untouched.

**Deferred.** The VS Code webview; any hosted Workbench and the application authentication it would
need; whether `parseLooseYaml` survives as a labelled degraded fallback or is deleted.

## Validation / revisit trigger

Proved by attempt, each against a planted positive control:

1. The server listens on **`127.0.0.1` only** — checked with `ss`/`lsof`, not inferred from
   configuration.
2. A write issued through the server and the identical write issued through the CLI produce
   **byte-identical** `ops/` output. If they differ, §1's engine boundary is not real.
3. A record containing **nested structure** round-trips through write and read without loss — the
   specific failure fact 3 predicts.
4. A write that fails validation leaves `ops/` **unchanged**, and says why.
5. Stopping the server leaves every prior write intact and inspectable in git.

**Revisit if:**

- the server accumulates logic the CLI does not have, which means §1 has eroded and writes have two
  definitions again;
- the single YAML dependency grows into several, or a database is proposed — Factory's own guardrail
  is *"do not introduce a database before YAML/JSON/Markdown state proves insufficient"*;
- a hosted Workbench is wanted, which reopens authentication and exposure (ADR-035 §7);
- Python proves to be the wrong choice for adopters in practice, which would be evidence about
  distribution rather than about this ADR's structure.
