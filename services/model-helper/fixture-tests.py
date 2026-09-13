#!/usr/bin/env python3
"""
Fixture tests for the model helper — Phase 15.0.

WHAT THIS PROVES, AND WHAT IT DELIBERATELY CANNOT
-------------------------------------------------
The eligibility check (ADR-026 §3) will permit every real call this project
makes today: both subscription providers are `unattended: true`. A check that
has only ever permitted is unvalidated. So the refusal is proved here against a
FIXTURE provider set `unattended: false`, next to a positive control that is the
same request against the same provider set `true`. Test 1 without test 2 proves
nothing -- a refusal because the fixture is broken looks exactly like a refusal
because the check works.

Nothing here touches a real CLI or spends allowance. The provider binaries are
replaced by a stub script that answers "STUB-ANSWER". Everything else -- the
config loader, the route table, the eligibility check, the cap reservation, the
fallback loop -- is the real code path in helper.py, driven the way systemd
drives it: one JSON line on stdin, one JSON line on stdout, journal on stderr.

THE FIXTURE IS DERIVED FROM THE REAL FORMAT, NOT WRITTEN BY HAND
----------------------------------------------------------------
Learned 2026-09-10: a hand-written fixture that drifts from the real format
produces a confident negative indistinguishable from a finding. So the fixture
config is config.example.json with exactly three things substituted -- the two
binaries, the state file, and the `unattended` value under test -- and the
result is asserted to have the SAME key set, recursively, as the example. If a
later phase renames a field in the example, this file fails loudly rather than
quietly testing a shape the helper no longer reads.

Runs on the MacBook (no node, no socket) and on the node under
`install-model-helper.sh verify`, as the helper's own account.

Exit 0 when every test passes; 1 otherwise. Each line is a claim.
"""

from __future__ import annotations

import concurrent.futures
import copy
import json
import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "helper.py")
EXAMPLE = os.path.join(HERE, "config.example.json")

# The stub stands in for both CLIs. Codex is called with `-o FILE` and the real
# provider reads the answer from that file, so the stub honours it; Claude reads
# stdout. Anything else on argv is ignored.
STUB = """#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift; fi
  shift
done
if [ -n "$out" ]; then printf 'STUB-ANSWER' > "$out"; fi
printf 'STUB-ANSWER\\n'
"""

QUESTION = "fixture question"

results: list[tuple[str, str]] = []


def report(status: str, name: str, note: str = "") -> None:
    results.append((status, name))
    line = f"{status:<7} {name}"
    if note:
        line += f" -- {note}"
    print(line, flush=True)


def same_shape(a, b, path: str = "") -> list[str]:
    """Recursive key-set comparison; returns the differences, empty if none."""
    diffs: list[str] = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in set(a) ^ set(b):
            diffs.append(f"{path}/{k}")
        for k in set(a) & set(b):
            diffs += same_shape(a[k], b[k], f"{path}/{k}")
    elif type(a) is not type(b):
        diffs.append(f"{path}: {type(a).__name__} vs {type(b).__name__}")
    return diffs


class Bench:
    """One temp directory: stub binary, fixture configs, counter file."""

    def __init__(self) -> None:
        self.dir = tempfile.mkdtemp(prefix="homelab-p150-fixture-")
        self.stub = os.path.join(self.dir, "stub-cli")
        with open(self.stub, "w", encoding="utf-8") as fh:
            fh.write(STUB)
        os.chmod(self.stub, stat.S_IRWXU)
        with open(EXAMPLE, encoding="utf-8") as fh:
            self.example = json.load(fh)

    def config(self, name: str, *, unattended: bool | None = None,
               caps: dict | None = None) -> str:
        cfg = copy.deepcopy(self.example)
        cfg.pop("_format", None)
        for entry in cfg["providers"].values():
            entry["bin"] = self.stub
            if unattended is not None:
                entry["unattended"] = unattended
        cfg["state_file"] = os.path.join(self.dir, f"calls-{name}.json")
        if caps is not None:
            cfg["caps"] = caps
        # The shape assertion. `_format` is documentation, not format.
        base = copy.deepcopy(self.example)
        base.pop("_format", None)
        diffs = same_shape(base, cfg)
        if diffs:
            raise SystemExit(f"FIXTURE SHAPE DRIFT: {diffs}")
        path = os.path.join(self.dir, f"config-{name}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)
        return path

    def counter(self, config_path: str) -> dict:
        with open(config_path, encoding="utf-8") as fh:
            state = json.load(fh)["state_file"]
        if not os.path.exists(state):
            return {}
        with open(state, encoding="utf-8") as fh:
            raw = fh.read().strip()
        return json.loads(raw) if raw else {}

    def calls(self, config_path: str) -> int:
        return sum(len(v) for v in self.counter(config_path).values()
                   if isinstance(v, list))


def ask(config_path: str, req: dict) -> tuple[dict, str]:
    """Drive helper.py exactly as systemd does: one line in, one line out."""
    env = dict(os.environ, HOMELAB_MODEL_HELPER_CONFIG=config_path)
    proc = subprocess.run(
        [sys.executable, HELPER],
        input=json.dumps(req) + "\n",
        capture_output=True, text=True, env=env, timeout=60,
    )
    line = proc.stdout.strip().splitlines()
    reply = json.loads(line[0]) if line else {"ok": False, "kind": "no-reply"}
    return reply, proc.stderr


def base_ask(**extra) -> dict:
    return {"v": 1, "op": "ask", "user_id": 1, "question": QUESTION,
            "context": "fixture", **extra}


def main() -> int:
    b = Bench()
    print(f"bench {b.dir}")
    print(f"example {EXAMPLE}")

    # ---- Fixture shape (brief §8, fixture discipline) ---------------------
    ineligible = b.config("ineligible", unattended=False)
    control = b.config("control", unattended=True)
    with open(ineligible, encoding="utf-8") as fh:
        entry = json.load(fh)["providers"]["claude"]
    report("ok", "fixture shape == config.example.json shape (recursive key set)",
           f"fixture provider entry: {json.dumps(entry)}")

    # ---- Tests 1, 2, 3: refusal, positive control, no cap spent -----------
    before = b.calls(ineligible)
    reply, err = ask(ineligible, base_ask(unattended=True))
    after = b.calls(ineligible)
    if reply.get("ok") is False and reply.get("kind") == "ineligible":
        report("ok", "test 1: unattended ask vs unattended:false -> refused",
               f"kind={reply['kind']} message={reply.get('message')!r}")
    else:
        report("FAIL", "test 1: unattended ask vs unattended:false", f"reply={reply}")
    # Only meaningful if test 1 refused ON THE REASON. A counter that stays at
    # zero because the helper crashed before the cap is not a passed test.
    if reply.get("kind") == "ineligible" and before == after == 0:
        report("ok", "test 3: the refusal consumed no cap", f"counter {before} -> {after}")
    else:
        report("FAIL", "test 3: the refusal consumed no cap", f"counter {before} -> {after}")
    if "outcome=ineligible" in err:
        report("ok", "test 1: journal names the reason",
               [l for l in err.splitlines() if "outcome=ineligible" in l][0])
    else:
        report("FAIL", "test 1: journal names the reason", err.strip()[-300:])

    before = b.calls(control)
    reply, err = ask(control, base_ask(unattended=True))
    after = b.calls(control)
    if reply.get("ok") and reply.get("text") == "STUB-ANSWER":
        report("ok", "test 2: same ask vs unattended:true -> permitted (positive control)",
               f"{reply.get('provider')}/{reply.get('model')} counter {before} -> {after}")
    else:
        report("FAIL", "test 2: positive control", f"reply={reply} err={err.strip()[-300:]}")

    # ---- Test 6: old-style ask -------------------------------------------
    reply, err = ask(control, base_ask())
    if reply.get("ok") and reply.get("text") == "STUB-ANSWER":
        report("ok", "test 6: Phase 09 ask (no role, no flag) still works",
               f"{reply.get('provider')}/{reply.get('model')}")
    else:
        report("FAIL", "test 6: Phase 09 ask", f"reply={reply}")

    # ---- Test 8: the caller tries to name things ------------------------
    for field, value in (("model", "opus"), ("provider", "codex"),
                         ("bin", "/bin/sh"), ("path", "/etc/passwd"),
                         ("route", "owner-interactive")):
        before = b.calls(control)
        reply, _ = ask(control, base_ask(**{field: value}))
        after = b.calls(control)
        # The message must NAME the field: a generic error (e.g. a broken
        # config) would otherwise pass this test without testing anything.
        named = field in str(reply.get("message", ""))
        if reply.get("ok") is False and reply.get("kind") == "error" and named and before == after:
            report("ok", f"test 8: field {field!r} on the wire is rejected",
                   f"message={reply.get('message')!r}, no cap spent")
        else:
            report("FAIL", f"test 8: field {field!r}", f"reply={reply} counter {before}->{after}")

    # ---- Test 11: hints never select --------------------------------------
    def route_line(stderr: str) -> str:
        for l in stderr.splitlines():
            if " outcome=ok" in l:
                return l
        return ""
    plain_reply, plain_err = ask(control, base_ask())
    hint_reply, hint_err = ask(control, base_ask(priority="critical", complexity="high",
                                                 severity="critical", summary="hard task"))
    same = (plain_reply.get("provider"), plain_reply.get("model")) == \
           (hint_reply.get("provider"), hint_reply.get("model"))
    logged = "priority=critical" in hint_err and "complexity=high" in hint_err
    if hint_reply.get("ok") and same and logged:
        report("ok", "test 11: hints logged, route identical",
               f"plain: {route_line(plain_err)}\n        hints: {route_line(hint_err)}")
    else:
        report("FAIL", "test 11: hints", f"same={same} logged={logged} reply={hint_reply}")
    reply, _ = ask(control, base_ask(priority="urgent!!"))
    if reply.get("ok") is False and reply.get("kind") == "error" \
            and "priority" in str(reply.get("message", "")):
        report("ok", "test 11b: a hint outside its enum is a bad request",
               f"message={reply.get('message')!r}")
    else:
        report("FAIL", "test 11b: bad hint value", f"reply={reply}")

    # ---- Test 12: unknown role ------------------------------------------
    before = b.calls(control)
    reply, err = ask(control, base_ask(role="no-such-role"))
    after = b.calls(control)
    if reply.get("ok") is False and reply.get("kind") == "unknown_role" and before == after:
        report("ok", "test 12: unknown role refused, no cap spent",
               f"message={reply.get('message')!r}")
    else:
        report("FAIL", "test 12: unknown role", f"reply={reply} counter {before}->{after}")
    reply, _ = ask(control, base_ask(role="owner-interactive"))
    if reply.get("ok"):
        report("ok", "test 12b: a known role routes")
    else:
        report("FAIL", "test 12b: known role", f"reply={reply}")

    # ---- Tests 5 and 7: the owner's floor -----------------------------------
    # per provider: 3/day, reserve 2 -> unattended may spend 1 per provider.
    # The route has two providers, so the unattended budget is 2 in total.
    caps = {"per_hour": 3, "per_day": 3, "owner_reserve": {"per_hour": 2, "per_day": 2}}
    floor = b.config("floor", unattended=True, caps=caps)
    unattended_budget = 2
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        outs = list(pool.map(lambda _: ask(floor, base_ask(unattended=True))[0], range(10)))
    won = sum(1 for r in outs if r.get("ok"))
    kinds = sorted({r.get("kind") for r in outs if not r.get("ok")})
    if won == unattended_budget and kinds == ["exhausted"]:
        report("ok", "test 7: ten racing unattended asks, exactly the budget won",
               f"won={won} losers={kinds}")
    else:
        report("FAIL", "test 7: racing unattended asks", f"won={won} losers={kinds}")
    reply, _ = ask(floor, base_ask(unattended=True))
    detail = " ".join(reply.get("detail", []) or [])
    if reply.get("ok") is False and reply.get("kind") == "exhausted" and "reserve" in detail:
        report("ok", "test 5a: unattended budget exhausted, refusal names the reserve",
               f"detail={detail!r}")
    else:
        report("FAIL", "test 5a: unattended exhausted", f"reply={reply}")
    reply, _ = ask(floor, base_ask())
    if reply.get("ok"):
        report("ok", "test 5: owner-initiated ask still succeeds from the reserve",
               f"{reply.get('provider')}/{reply.get('model')}")
    else:
        report("FAIL", "test 5: owner ask from the reserve", f"reply={reply}")

    # ---- Old config format is refused, not guessed ------------------------
    old = os.path.join(b.dir, "config-phase09.json")
    with open(old, "w", encoding="utf-8") as fh:
        json.dump({"providers": ["claude", "codex"],
                   "claude": {"bin": b.stub, "model": "haiku"},
                   "codex": {"bin": b.stub, "model": "x"},
                   "caps": {"per_hour": 6, "per_day": 30},
                   "state_file": os.path.join(b.dir, "calls-old.json")}, fh)
    reply, err = ask(old, base_ask())
    if reply.get("ok") is False and "misconfigured" in reply.get("message", ""):
        report("ok", "Phase 09 config shape is refused with a config error",
               err.strip().splitlines()[0] if err.strip() else "")
    else:
        report("FAIL", "Phase 09 config shape", f"reply={reply}")

    failed = [n for s, n in results if s != "ok"]
    print()
    if failed:
        print(f"{len(failed)} of {len(results)} checks did not pass.")
        return 1
    print(f"All {len(results)} checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
