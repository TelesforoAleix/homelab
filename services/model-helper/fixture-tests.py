#!/usr/bin/env python3
"""
Fixture tests for the model helper — Phase 15.0, extended by Phase 15.1.

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
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from providers import CHAT_ENVELOPE_TOKEN_ALLOWANCE  # noqa: E402
from spend import SpendGovernor, maximum_cost  # noqa: E402

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


class FakeGateway:
    """Local HTTP endpoint. It never opens a connection off this machine."""

    def __init__(self) -> None:
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                n = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(n)
                try:
                    body = json.loads(raw)
                except ValueError:
                    body = None
                outer.requests.append(body)
                status = outer.status
                payload = outer.payload
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(payload).encode("utf-8"))

            def log_message(self, _format, *_args):
                return

        self.requests: list[dict] = []
        self.status = 200
        self.payload = {
            "id": "fake-generation",
            "choices": [{"message": {"role": "assistant", "content": "FAKE-GATEWAY-ANSWER"}}],
            "usage": {
                "prompt_tokens": 20,
                "completion_tokens": 5,
                "total_tokens": 25,
                "prompt_tokens_details": {"cached_tokens": 3},
                "cache_creation_input_tokens": 2,
                "cost": 0.0000094,
            },
        }
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    @property
    def endpoint(self) -> str:
        return f"http://127.0.0.1:{self.server.server_port}/v1/chat/completions"

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


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

    def __init__(self, gateway: FakeGateway) -> None:
        self.dir = tempfile.mkdtemp(prefix="homelab-p150-fixture-")
        self.stub = os.path.join(self.dir, "stub-cli")
        with open(self.stub, "w", encoding="utf-8") as fh:
            fh.write(STUB)
        os.chmod(self.stub, stat.S_IRWXU)
        self.credentials = os.path.join(self.dir, "credentials")
        os.mkdir(self.credentials, 0o700)
        with open(os.path.join(self.credentials, "gateway-key"), "w", encoding="utf-8") as fh:
            fh.write("fixture-only-not-a-real-key\n")
        os.chmod(os.path.join(self.credentials, "gateway-key"), 0o400)
        with open(EXAMPLE, encoding="utf-8") as fh:
            self.example = json.load(fh)
        self.gateway = gateway

    def config(self, name: str, *, unattended: bool | None = None,
               caps: dict | None = None, initialize_spend: bool = True) -> str:
        cfg = copy.deepcopy(self.example)
        cfg.pop("_format", None)
        for entry in cfg["providers"].values():
            if "bin" in entry:
                entry["bin"] = self.stub
            if unattended is not None:
                entry["unattended"] = unattended
        cfg["providers"]["gateway"]["endpoint"] = self.gateway.endpoint
        cfg["state_file"] = os.path.join(self.dir, f"calls-{name}.json")
        cfg["spend"]["state_file"] = os.path.join(self.dir, f"spend-{name}.json")
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
        if initialize_spend:
            SpendGovernor.initialize(cfg["spend"]["state_file"])
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
    env = dict(os.environ, HOMELAB_MODEL_HELPER_CONFIG=config_path,
               CREDENTIALS_DIRECTORY=os.path.join(os.path.dirname(config_path), "credentials"))
    proc = subprocess.run(
        [sys.executable, HELPER],
        input=json.dumps(req) + "\n",
        capture_output=True, text=True, env=env, timeout=60,
    )
    line = proc.stdout.strip().splitlines()
    reply = json.loads(line[0]) if line else {"ok": False, "kind": "no-reply"}
    return reply, proc.stderr


def base_ask(**extra) -> dict:
    # The bot's exact payload, read from services/telegram-bot/model_client.py
    # ask(): v, op, user_id, question, context. Test 6 sends this and nothing
    # else, so a change to the bot's client shows up here as a failure.
    return {"v": 1, "op": "ask", "user_id": 1, "question": QUESTION,
            "context": "fixture", **extra}


def main() -> int:
    gateway = FakeGateway()
    b = Bench(gateway)
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

    # ---- Phase 15.1 brief §8 rows 1--8: fake gateway + governor ---------
    def read_cfg(path: str) -> dict:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)

    def write_cfg(path: str, cfg: dict) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)

    def utility(*, unattended: bool = False) -> dict:
        return base_ask(role="utility", unattended=unattended,
                        request_id="1" * 32)

    # Rows 1 and 2. Each target window is the first low ceiling in the fixed
    # hour -> day -> week -> month check order; the positive control raises
    # only that ceiling and sends the identical request.
    for unattended in (False, True):
        kind = "unattended" if unattended else "attended"
        for window in ("hour", "day", "week", "month"):
            path = b.config(f"row-{1 if not unattended else 2}-{window}")
            cfg = read_cfg(path)
            for w in ("hour", "day", "week", "month"):
                cfg["spend"]["budgets"][kind][w] = "1.00"
            cfg["spend"]["budgets"][kind][window] = "0"
            write_cfg(path, cfg)
            before = len(gateway.requests)
            refused, _ = ask(path, utility(unattended=unattended))
            no_call = len(gateway.requests) == before
            named = window in " ".join(refused.get("detail", []) or [])
            cfg["spend"]["budgets"][kind][window] = "1.00"
            write_cfg(path, cfg)
            passed, _ = ask(path, utility(unattended=unattended))
            if refused.get("ok") is False and no_call and named and passed.get("ok"):
                report("ok", f"row {1 if not unattended else 2}: {kind} {window} refusal + positive control",
                       f"refusal={refused.get('detail')} raised ceiling -> ok")
            else:
                report("FAIL", f"row {1 if not unattended else 2}: {kind} {window}",
                       f"refused={refused} no_call={no_call} passed={passed}")

    # Row 3: the two money budgets are independent.
    independent = b.config("row-3")
    cfg = read_cfg(independent)
    cfg["spend"]["budgets"]["unattended"]["hour"] = "0"
    write_cfg(independent, cfg)
    denied, _ = ask(independent, utility(unattended=True))
    owner, _ = ask(independent, utility(unattended=False))
    if denied.get("ok") is False and owner.get("ok"):
        report("ok", "row 3: unattended exhausted; attended call passes",
               f"unattended={denied.get('detail')} attended={owner.get('cost')}")
    else:
        report("FAIL", "row 3: budget independence", f"unattended={denied} attended={owner}")

    # Row 4: absence, malformed JSON and unreadable state each refuse before
    # the fake gateway. The positive claim is the request count, not an error.
    row4_cases = []
    for case in ("absent", "malformed", "unreadable"):
        path = b.config(f"row-4-{case}", initialize_spend=False)
        state = read_cfg(path)["spend"]["state_file"]
        if case == "malformed":
            with open(state, "w", encoding="utf-8") as fh:
                fh.write("not-json\n")
        elif case == "unreadable":
            SpendGovernor.initialize(state)
            os.chmod(state, 0)
        before = len(gateway.requests)
        reply, _ = ask(path, utility())
        if case == "unreadable":
            os.chmod(state, 0o600)
        row4_cases.append(reply.get("kind") == "governor_unavailable"
                          and len(gateway.requests) == before)
    if all(row4_cases):
        report("ok", "row 4: absent/malformed/unreadable ledger fail closed",
               "kind=governor_unavailable each; fake requests +0")
    else:
        report("FAIL", "row 4: ledger failures", f"cases={row4_cases}")

    # Row 5: persist a reservation without settling (the helper-kill state),
    # prove it blocks, age it beyond RuntimeMaxSec, then prove automatic release.
    persisted = b.config("row-5")
    cfg = read_cfg(persisted)
    model = cfg["providers"]["gateway"]["models"]["luna"]
    amount = maximum_cost(len("Context:\nfixture\n\nQuestion:\nfixture question".encode())
                          + CHAT_ENVELOPE_TOKEN_ALLOWANCE,
                          model["max_output_tokens"], model["price"])
    for w in cfg["spend"]["budgets"]["attended"]:
        cfg["spend"]["budgets"]["attended"][w] = str(amount)
    write_cfg(persisted, cfg)
    gov = SpendGovernor(cfg["spend"]["state_file"],
                        cfg["spend"]["budgets"],
                        cfg["spend"]["reservation_timeout_seconds"])
    reserved = gov.reserve(route="utility", provider="gateway", model="luna",
                           unattended=False, amount=amount, request_id="2" * 32)
    before = len(gateway.requests)
    blocked, _ = ask(persisted, utility())
    ledger = json.load(open(cfg["spend"]["state_file"], encoding="utf-8"))
    ledger["calls"][0]["ts"] = time.time() - 271
    with open(cfg["spend"]["state_file"], "w", encoding="utf-8") as fh:
        json.dump(ledger, fh)
    passed, err = ask(persisted, utility())
    if reserved[0] and blocked.get("ok") is False and len(gateway.requests) == before + 1 \
            and passed.get("ok") and "stale reservation released" in err:
        report("ok", "row 5: reservation persists and stale reservation releases",
               "fresh blocked with fake +0; aged reservation logged; next call passed")
    else:
        report("FAIL", "row 5: persistent reservation", f"blocked={blocked} passed={passed} err={err}")

    # Row 6: config-load refusal names both the model and missing/bad field.
    bad_price = b.config("row-6-price")
    cfg = read_cfg(bad_price)
    del cfg["providers"]["gateway"]["models"]["luna"]["price"]["cache_write"]
    write_cfg(bad_price, cfg)
    reply, err = ask(bad_price, utility())
    price_named = (not reply.get("ok") and "models.luna.price.cache_write" in err)
    bad_vendor = b.config("row-6-vendor")
    cfg = read_cfg(bad_vendor)
    cfg["providers"]["gateway"]["models"]["luna"]["id"] = "not-approved/model"
    write_cfg(bad_vendor, cfg)
    reply, err = ask(bad_vendor, utility())
    vendor_named = (not reply.get("ok") and "models.luna.id vendor" in err)
    if price_named and vendor_named:
        report("ok", "row 6: incomplete price and unapproved vendor fail config load",
               "both errors name gateway/luna and the failing field")
    else:
        report("FAIL", "row 6: registry validation",
               f"price_named={price_named} vendor_named={vendor_named}")

    # Row 7: an HTTP 429 is exhausted, and neither reservation remains.
    row7 = b.config("row-7")
    gateway.status = 429
    before = len(gateway.requests)
    reply, _ = ask(row7, utility())
    cfg = read_cfg(row7)
    spend_state = json.load(open(cfg["spend"]["state_file"], encoding="utf-8"))
    count_state = b.counter(row7)
    released = (spend_state["calls"] and spend_state["calls"][-1]["status"] == "released")
    count_released = not count_state.get("gateway")
    if reply.get("kind") == "exhausted" and len(gateway.requests) == before + 1 \
            and released and count_released:
        report("ok", "row 7: HTTP 429 releases count and money reservations",
               "kind=exhausted; ledger status=released; count entry absent")
    else:
        report("FAIL", "row 7: reservation release",
               f"reply={reply} released={released} count={count_state}")

    row7_auth = b.config("row-7-auth")
    gateway.status = 401
    reply, _ = ask(row7_auth, utility())
    cfg = read_cfg(row7_auth)
    auth_state = json.load(open(cfg["spend"]["state_file"], encoding="utf-8"))
    if reply.get("kind") == "provider_error" \
            and auth_state["calls"][-1]["status"] == "released":
        report("ok", "provider errors: HTTP 401 is distinct from HTTP 429",
               "401 kind=provider_error; 429 kind=exhausted; both released")
    else:
        report("FAIL", "provider errors: HTTP 401 distinction", f"reply={reply}")

    row7_uncertain = b.config("row-7-uncertain")
    gateway.status = 500
    reply, _ = ask(row7_uncertain, utility())
    cfg = read_cfg(row7_uncertain)
    uncertain_state = json.load(open(cfg["spend"]["state_file"], encoding="utf-8"))
    uncertain_count = b.counter(row7_uncertain)
    if reply.get("kind") == "error" \
            and uncertain_state["calls"][-1]["status"] == "settled" \
            and uncertain_state["calls"][-1]["settled_usd"] \
            == uncertain_state["calls"][-1]["reserved_usd"] \
            and uncertain_count.get("gateway"):
        report("ok", "uncertain HTTP failure retains count and settles maximum",
               "HTTP 500 kind=error; reservation settled at maximum")
    else:
        report("FAIL", "uncertain HTTP failure settlement",
               f"reply={reply} ledger={uncertain_state} count={uncertain_count}")

    # Authorized S2 diagnostic: retain only the gateway's bounded type/code
    # identifiers. Neither free-text message nor param may reach the journal.
    diagnostic = b.config("gateway-error-diagnostic")
    success_payload = gateway.payload
    message_sentinel = "SYNTHETIC-MESSAGE-MUST-NOT-REACH-JOURNAL"
    param_sentinel = "SYNTHETIC-PARAM-MUST-NOT-REACH-JOURNAL"
    gateway.status = 403
    gateway.payload = {
        "error": {
            "type": "access_denied",
            "code": "insufficient_credits",
            "message": message_sentinel,
            "param": param_sentinel,
        }
    }
    reply, err = ask(diagnostic, utility())
    safe_metadata = "gateway_error_type=access_denied" in err \
        and "gateway_error_code=insufficient_credits" in err
    content_absent = message_sentinel not in err and param_sentinel not in err \
        and message_sentinel not in json.dumps(reply) \
        and param_sentinel not in json.dumps(reply)
    if reply.get("kind") == "error" and safe_metadata and content_absent:
        report("ok", "gateway error diagnostic logs only type/code",
               "synthetic message and param absent from journal and reply")
    else:
        report("FAIL", "gateway error diagnostic redaction",
               f"reply={reply} safe_metadata={safe_metadata} content_absent={content_absent}")

    # Row 8: exact request-body capture. Luna's reasoning=none is represented
    # by omitting the optional reasoning object; no provider/model is caller data.
    gateway.status = 200
    gateway.payload = success_payload
    gateway.requests.clear()
    row8 = b.config("row-8")
    reply, _ = ask(row8, utility())
    captured = gateway.requests[-1] if gateway.requests else {}
    fields_exact = set(captured) == {
        "model", "messages", "max_tokens", "providerOptions"
    }
    pin_exact = captured.get("providerOptions") == {
        "gateway": {"only": ["openai"]}
    }
    serialized = json.dumps(captured).lower()
    host_data_absent = not any(x in serialized for x in
                               ("/etc/", "/home/", ".service", "hostname"))
    if reply.get("ok") and fields_exact and pin_exact and host_data_absent:
        report("ok", "row 8: fake gateway request body captured exactly",
               json.dumps(captured, separators=(",", ":")))
    else:
        report("FAIL", "row 8: request body", f"reply={reply} body={captured}")

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

    gateway.close()
    failed = [n for s, n in results if s != "ok"]
    print()
    if failed:
        print(f"{len(failed)} of {len(results)} checks did not pass.")
        return 1
    print(f"All {len(results)} checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
