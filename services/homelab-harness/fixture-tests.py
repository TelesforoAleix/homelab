#!/usr/bin/env python3
"""
Fixture tests for the harness — Phase 23.0.

WHAT THIS PROVES
----------------
Every refusal kind the endpoint can produce, by attempt, next to a positive
control that is the same request with only the offending element removed
(ADR-034 §14: a check that has only ever permitted is unvalidated). The
helper's own refusals -- unknown_role, ineligible, exhausted -- are surfaced
through the endpoint distinguishably (stage="helper"). And the audit file is
asserted to hold NO content: every string value matches a closed grammar, and
none of the content strings sent here can be found in it.

HOW THE HELPER IS STOOD IN FOR
------------------------------
Not with a fake. A stub UNIX socket accepts each connection and spawns the REAL
helper.py with the connection as stdin and stdout -- exactly what systemd's
Accept=yes does -- against a fixture config derived from the helper's own
config.example.json (the 15.0 discipline: derived, shape-asserted, never
hand-written) with the two CLIs replaced by a stub script. So the wire
protocol, the route table, the eligibility check and the cap reservation are
the helper's real code, and the refusals that come back through the endpoint
are the helper's real refusals. Nothing touches a real CLI or spends allowance.

The endpoint itself runs in-process on an ephemeral loopback port, from the
same harness.py the unit runs, reading a config derived from this directory's
config.example.json.

Runs on the MacBook and on the node under `install-homelab-harness.sh verify`,
as the harness's own account (helper.py is root:root 0644 under /opt, readable).

Exit 0 when every check passes; 1 otherwise. Each line is a claim.
"""

from __future__ import annotations

import copy
import http.client
import json
import os
import re
import socket
import stat
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import harness  # noqa: E402
from classify import CLASSES, classify  # noqa: E402

EXAMPLE = os.path.join(HERE, "config.example.json")

# Where the real helper.py is. Beside this directory in the repository; under
# /opt on the node. The env var wins so a runbook can point at either.
HELPER_DIR = next((d for d in (
    os.environ.get("HOMELAB_HELPER_DIR", ""),
    os.path.join(HERE, "..", "model-helper"),
    "/opt/homelab-model-helper",
) if d and os.path.isfile(os.path.join(d, "helper.py"))), None)

STUB = """#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift; fi
  shift
done
if [ -n "$out" ]; then printf 'STUB-ANSWER' > "$out"; fi
printf 'STUB-ANSWER\\n'
"""

# Content strings. Every one of these is asserted ABSENT from the audit file.
CLIENT = "fixture-client"
ROLE = "fixture-role"
QUESTION = "What is the capital of Fixtureland?"
CONTEXT_TEXT = "Fixtureland is a country invented for this test."
CONTEXT_SOURCE = "brain/notes/fixtureland.md@abc123"
SUMMARY = "fixture summary text"
CONTENT_STRINGS = (QUESTION, CONTEXT_TEXT, CONTEXT_SOURCE, SUMMARY, "STUB-ANSWER",
                   "Fixtureland", "capital", "unknown field", "attached by the runtime")

results: list[tuple[str, str]] = []


def report(status: str, name: str, note: str = "") -> None:
    results.append((status, name))
    line = f"{status:<7} {name}"
    if note:
        line += f" -- {note}"
    print(line, flush=True)


def same_shape(a, b, path: str = "") -> list[str]:
    diffs: list[str] = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in set(a) ^ set(b):
            diffs.append(f"{path}/{k}")
        for k in set(a) & set(b):
            diffs += same_shape(a[k], b[k], f"{path}/{k}")
    elif type(a) is not type(b):
        diffs.append(f"{path}: {type(a).__name__} vs {type(b).__name__}")
    return diffs


def free_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class StubHelperSocket:
    """
    An AF_UNIX listener that does what systemd does for Accept=yes: one
    helper.py process per connection, the connection as stdin/stdout, stderr
    captured as the journal. `canned` (bytes) replaces the helper with a fixed
    reply, for the "helper answered out of protocol" case.
    """

    def __init__(self, path: str) -> None:
        self.path = path
        self.config: str | None = None
        self.canned: bytes | None = None
        self.spawns = 0
        self.journal: list[str] = []
        self._lock = threading.Lock()
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.bind(path)
        self._sock.listen(8)
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self) -> None:
        while True:
            conn, _ = self._sock.accept()
            threading.Thread(target=self._one, args=(conn,), daemon=True).start()

    def _one(self, conn: socket.socket) -> None:
        try:
            if self.canned is not None:
                conn.recv(65536)
                conn.sendall(self.canned)
                return
            env = dict(os.environ, HOMELAB_MODEL_HELPER_CONFIG=self.config or "")
            with self._lock:
                self.spawns += 1
            proc = subprocess.run([sys.executable, os.path.join(HELPER_DIR, "helper.py")],
                                  stdin=conn.fileno(), stdout=conn.fileno(),
                                  stderr=subprocess.PIPE, env=env, timeout=60, text=True)
            with self._lock:
                self.journal.extend(proc.stderr.splitlines())
        finally:
            conn.close()


class Bench:
    def __init__(self) -> None:
        self.dir = tempfile.mkdtemp(prefix="homelab-p230-fixture-")
        self.stub_cli = os.path.join(self.dir, "stub-cli")
        with open(self.stub_cli, "w", encoding="utf-8") as fh:
            fh.write(STUB)
        os.chmod(self.stub_cli, stat.S_IRWXU)
        with open(os.path.join(HELPER_DIR, "config.example.json"), encoding="utf-8") as fh:
            self.helper_example = json.load(fh)
        with open(EXAMPLE, encoding="utf-8") as fh:
            self.harness_example = json.load(fh)
        self.helper = StubHelperSocket(os.path.join(self.dir, "helper.sock"))
        self.audit_path = os.path.join(self.dir, "audit.jsonl")
        self.port = free_port()
        self.posts = 0

    # --- helper fixture config, derived from the helper's example ------------
    def helper_config(self, name: str, *, unattended: bool | None = None,
                      caps: dict | None = None) -> str:
        cfg = copy.deepcopy(self.helper_example)
        cfg.pop("_format", None)
        for entry in cfg["providers"].values():
            if "bin" in entry:
                entry["bin"] = self.stub_cli
            if unattended is not None:
                entry["unattended"] = unattended
        cfg["state_file"] = os.path.join(self.dir, f"calls-{name}.json")
        if caps is not None:
            cfg["caps"] = caps
        base = copy.deepcopy(self.helper_example)
        base.pop("_format", None)
        diffs = same_shape(base, cfg)
        if diffs:
            raise SystemExit(f"HELPER FIXTURE SHAPE DRIFT: {diffs}")
        # The one addition after the shape check: a route for the agent role
        # this fixture sends (brief §6.8 -- one route per exercised role).
        cfg["routes"][ROLE] = list(cfg["routes"][cfg["default_route"]])
        path = os.path.join(self.dir, f"helper-{name}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)
        return path

    # --- the endpoint, in-process --------------------------------------------
    def harness_config(self, **overrides) -> dict:
        cfg = copy.deepcopy(self.harness_example)
        cfg.pop("_format", None)
        cfg["listen"]["port"] = self.port
        cfg["helper_socket"] = self.helper.path
        cfg["audit_file"] = self.audit_path
        cfg.update(overrides)
        base = copy.deepcopy(self.harness_example)
        base.pop("_format", None)
        # audit_file is null in the example (meaning $STATE_DIRECTORY) and a
        # path here; the one key exempted from the shape check.
        diffs = same_shape({k: v for k, v in base.items() if k != "audit_file"},
                           {k: v for k, v in cfg.items() if k != "audit_file"})
        if diffs:
            raise SystemExit(f"HARNESS FIXTURE SHAPE DRIFT: {diffs}")
        path = os.path.join(self.dir, "harness.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)
        return harness.load_config(path)

    def start(self) -> None:
        self.server = harness.Harness(self.harness_config())
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def post(self, body, *, client: str | None = CLIENT, raw: bytes | None = None,
             path: str = "/v1/request") -> tuple[int, dict]:
        data = raw if raw is not None else json.dumps(body).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if client is not None:
            headers[harness.CLIENT_HEADER] = client
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=60)
        conn.request("POST", path, body=data, headers=headers)
        resp = conn.getresponse()
        payload = json.loads(resp.read().decode("utf-8"))
        conn.close()
        self.posts += 1
        return resp.status, payload

    def get(self, path: str) -> tuple[int, dict]:
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        conn.request("GET", path)
        resp = conn.getresponse()
        payload = json.loads(resp.read().decode("utf-8"))
        conn.close()
        return resp.status, payload

    def audit_lines(self) -> list[dict]:
        if not os.path.exists(self.audit_path):
            return []
        with open(self.audit_path, encoding="utf-8") as fh:
            return [json.loads(l) for l in fh if l.strip()]


def base_request(**extra) -> dict:
    req = {"v": 1, "kind": "question", "role": ROLE, "question": QUESTION,
           "context": [{"text": CONTEXT_TEXT, "source": CONTEXT_SOURCE}],
           "summary": SUMMARY}
    req.update(extra)
    return req


def expect_refusal(b: Bench, name: str, body, kind: str, *, stage: str = "endpoint",
                   named: str | None = None, client=CLIENT, raw=None) -> dict:
    """A refusal of the given kind, with no helper spawned for endpoint refusals."""
    before = b.helper.spawns
    status, reply = b.post(body, client=client, raw=raw)
    after = b.helper.spawns
    ok = (reply.get("ok") is False and reply.get("kind") == kind
          and reply.get("stage") == stage and status == harness.STATUS_FOR_KIND[kind]
          and "request_id" in reply)
    if stage == "endpoint":
        ok = ok and before == after
    if named is not None:
        ok = ok and named in str(reply.get("message", ""))
    if ok:
        report("ok", name, f"kind={kind} stage={stage} http={status} "
                          f"helper_spawns {before}->{after} message={reply.get('message')!r}")
    else:
        report("FAIL", name, f"reply={reply} http={status} helper_spawns {before}->{after}")
    return reply


def expect_ok(b: Bench, name: str, body, **kw) -> dict:
    status, reply = b.post(body, **kw)
    if reply.get("ok") and reply.get("text") == "STUB-ANSWER" and status == 200 \
            and reply.get("class") == "question" and "request_id" in reply:
        report("ok", name, f"{reply.get('provider')}/{reply.get('model')} "
                          f"request_id={reply['request_id'][:8]}…")
    else:
        report("FAIL", name, f"reply={reply} http={status}")
    return reply


def main() -> int:
    if HELPER_DIR is None:
        print("UNKNOWN  helper.py not found (set HOMELAB_HELPER_DIR); nothing was tested")
        return 1
    b = Bench()
    print(f"bench {b.dir}")
    print(f"helper {HELPER_DIR}")
    b.helper.config = b.helper_config("control", unattended=True)
    b.start()

    # ---- 0. loopback refused in code, enums match the helper --------------
    try:
        b.harness_config(listen={"host": "0.0.0.0", "port": b.port})
        report("FAIL", "config: non-loopback listen.host is refused")
    except ValueError as exc:
        report("ok", "config: non-loopback listen.host is refused", str(exc))
    sys.path.insert(0, HELPER_DIR)
    import helper as helper_mod  # noqa: E402
    if helper_mod.HINTS == harness.HINTS and helper_mod.MAX_SUMMARY_CHARS == harness.MAX_SUMMARY_CHARS:
        report("ok", "hints: the endpoint's enums are the helper's enums")
    else:
        report("FAIL", "hints: enums drifted", f"{helper_mod.HINTS} vs {harness.HINTS}")

    # ---- 1. health, then the positive control -------------------------------
    status, reply = b.get("/health")
    if status == 200 and reply.get("ok") and reply.get("service") == "homelab-harness":
        report("ok", "GET /health answers without touching the helper")
    else:
        report("FAIL", "GET /health", f"{status} {reply}")
    before = b.helper.spawns
    status, reply = b.get("/health/helper")
    if status == 200 and reply.get("helper") == "reachable" and b.helper.spawns == before + 1:
        report("ok", "GET /health/helper pings the helper (no model call)",
               f"providers={reply.get('providers')}")
    else:
        report("FAIL", "GET /health/helper", f"{status} {reply}")

    before = b.helper.spawns
    ctrl = expect_ok(b, "test 3: positive control -- question, routed role -> ok", base_request())
    journal = [l for l in b.helper.journal if "outcome=ok" in l]
    if b.helper.spawns == before + 1 and journal and f"route={ROLE}" in journal[-1] \
            and f"user=harness:{CLIENT}" in journal[-1]:
        report("ok", "test 3: helper journal shows route=<role> and user=harness:<client>",
               journal[-1])
    else:
        report("FAIL", "test 3: helper journal", str(journal[-1:]))
    line = b.audit_lines()[-1]
    if line["request_id"] == ctrl["request_id"] and line["outcome"] == "ok" \
            and line["question_len"] == len(QUESTION) and line["context_items"] == 1 \
            and line["output_len"] == len("STUB-ANSWER") and line["cost"] is None \
            and line["peer"] is None and line["client_declared"] == CLIENT:
        report("ok", "test 3: audit line has ids and lengths, cost null, peer null",
               json.dumps(line))
    else:
        report("FAIL", "test 3: audit line", json.dumps(line))

    # ---- 2. identity in the body, refused by name ---------------------------
    for field, value in (("client", "workbench"), ("user", "aleix"), ("user_id", 1),
                         ("origin", "telegram"), ("request_id", "abc"), ("peer", 1000),
                         ("identity", "owner"), ("ts", "2026-01-01T00:00:00Z")):
        expect_refusal(b, f"test 2: body field {field!r} -> identity_in_body",
                       base_request(**{field: value}), "identity_in_body", named=field)

    # ---- unknown fields, the 15.0 pattern: named --------------------------------
    for field, value in (("model", "opus"), ("provider", "codex"), ("bin", "/bin/sh"),
                         ("path", "/etc/passwd"), ("route", "owner-interactive")):
        expect_refusal(b, f"unknown field {field!r} -> bad_request, named",
                       base_request(**{field: value}), "bad_request", named=field)

    # ---- shape: each required thing removed, next to the control above -------
    expect_refusal(b, "missing X-Homelab-Client header -> bad_request",
                   base_request(), "bad_request", client=None, named=harness.CLIENT_HEADER)
    expect_refusal(b, "client label outside the grammar -> bad_request",
                   base_request(), "bad_request", client="Work Bench!", named=harness.CLIENT_HEADER)
    req = base_request(); del req["role"]
    expect_refusal(b, "missing role -> bad_request (never defaulted to the owner's route)",
                   req, "bad_request", named="role")
    expect_refusal(b, "wrong v -> bad_request", base_request(v=2), "bad_request", named="'v'")
    expect_refusal(b, "not JSON -> bad_request", None, "bad_request", raw=b"{not json")
    expect_refusal(b, "kind outside the declarable set -> bad_request",
                   base_request(kind="unclassifiable"), "bad_request", named="kind")
    expect_refusal(b, "context item with an extra key -> bad_request",
                   base_request(context=[{"text": "x", "path": "/etc"}]), "bad_request", named="context[0]")
    expect_refusal(b, "unattended not boolean -> bad_request",
                   base_request(unattended="yes"), "bad_request", named="unattended")

    # ---- too_large, each next to the same request one unit smaller -----------
    limit = b.server.cfg["max_question_chars"]
    expect_refusal(b, f"question of {limit + 1} chars -> too_large",
                   base_request(question="?" * (limit + 1)), "too_large", named="question")
    expect_ok(b, f"control: question of {limit} chars -> ok", base_request(question="?" * limit))
    n = b.server.cfg["max_context_items"]
    expect_refusal(b, f"{n + 1} context items -> too_large",
                   base_request(context=[{"text": "x"}] * (n + 1)), "too_large", named="context")
    expect_ok(b, f"control: {n} context items -> ok", base_request(context=[{"text": "x"}] * n))
    big = json.dumps(base_request(summary="s" * 100)).encode()
    pad = b.server.cfg["max_body_bytes"] - len(big) + 1
    expect_refusal(b, "body over max_body_bytes -> too_large (refused before parsing)",
                   None, "too_large", raw=big + b" " * pad, named="body")

    # ---- test 4: hints carried, never selecting; bad hint refused here --------
    plain = expect_ok(b, "test 4a: plain question", base_request())
    hinted = expect_ok(b, "test 4b: same with priority=critical, severity=critical, complexity=high",
                       base_request(priority="critical", severity="critical", complexity="high"))
    ok_lines = [l for l in b.helper.journal if "outcome=ok" in l]
    same = (plain.get("provider"), plain.get("model")) == (hinted.get("provider"), hinted.get("model"))
    logged = ok_lines and "priority=critical" in ok_lines[-1] and "complexity=high" in ok_lines[-1]
    if same and logged:
        report("ok", "test 4: hints reached the helper's journal; provider/model identical",
               ok_lines[-1])
    else:
        report("FAIL", "test 4: hints", f"same={same} logged={logged}")
    expect_refusal(b, "hint outside its enum -> bad_request at the endpoint, no helper spawn",
                   base_request(priority="medium"), "bad_request", named="priority")

    # ---- tests 6, 7: the taxonomy's refusals, each with its control ----------
    expect_refusal(b, "test 6: kind=task -> needs_decomposition (T1)",
                   base_request(kind="task"), "needs_decomposition")
    expect_refusal(b, "test 7: kind=command -> not_a_request (C1)",
                   base_request(kind="command"), "not_a_request")
    req = base_request(question="/restart ssh.service"); del req["kind"]
    expect_refusal(b, "test 7: '/restart ssh.service', no kind -> not_a_request (C2)",
                   req, "not_a_request")
    expect_refusal(b, "kind=question but capabilities named -> needs_decomposition (T2)",
                   base_request(capabilities=["repository-write"]), "needs_decomposition")
    expect_refusal(b, "kind=question but 'Refactor the parser…' -> needs_decomposition (T3)",
                   base_request(question="Refactor the parser to stream tokens."), "needs_decomposition")
    expect_refusal(b, "kind=question but a numbered list of steps -> needs_decomposition (T4)",
                   base_request(question="Please:\n1. open the file\n2. change the port"),
                   "needs_decomposition")
    req = base_request(question="the weather in Berlin tomorrow"); del req["kind"]
    expect_refusal(b, "no kind, no signal -> unclassifiable (U)", req, "unclassifiable")
    expect_ok(b, "control: same text with kind=question -> ok (Q0)",
              base_request(question="the weather in Berlin tomorrow"))
    req = base_request(); del req["kind"]
    expect_ok(b, "control: no kind, 'What is…?' -> ok (Q1)", req)
    req = base_request(question="Berlin has a capital?"); del req["kind"]
    expect_ok(b, "control: no kind, ends with '?' -> ok (Q2)", req)

    # The rule labels in the audit line match classify()'s own verdicts.
    drift = []
    for line in b.audit_lines():
        if line.get("class") not in CLASSES + (None,):
            drift.append(line["class"])
    if not drift:
        report("ok", "every audit line's class is in the closed taxonomy")
    else:
        report("FAIL", "audit class outside taxonomy", str(drift))

    # ---- test 5 + helper refusals, surfaced with stage=helper -----------------
    before = b.helper.spawns
    reply = expect_refusal(b, "test 5: role not in routes -> unknown_role, stage=helper",
                           base_request(role="no-such-role"), "unknown_role", stage="helper",
                           named="no-such-role")
    if b.helper.spawns == before + 1 and any("outcome=unknown_role" in l for l in b.helper.journal):
        report("ok", "test 5: the helper was asked and refused; no cap spent (helper journal)")
    else:
        report("FAIL", "test 5: helper journal", str(b.helper.journal[-3:]))

    b.helper.config = b.helper_config("ineligible", unattended=False)
    expect_refusal(b, "helper ineligible: unattended=true vs providers unattended:false",
                   base_request(unattended=True), "ineligible", stage="helper")
    b.helper.config = b.helper_config("control2", unattended=True)
    expect_ok(b, "control: same unattended=true vs unattended:true -> ok", base_request(unattended=True))

    caps = {"per_hour": 2, "per_day": 2, "owner_reserve": {"per_hour": 2, "per_day": 2}}
    b.helper.config = b.helper_config("floor", unattended=True, caps=caps)
    reply = expect_refusal(b, "helper exhausted: unattended budget is zero under the owner reserve",
                           base_request(unattended=True), "exhausted", stage="helper")
    if isinstance(reply.get("detail"), list) and any("reserve" in d for d in reply["detail"]):
        report("ok", "exhausted: the helper's detail list came through verbatim", str(reply["detail"]))
    else:
        report("FAIL", "exhausted detail", str(reply))
    expect_ok(b, "control: same request not unattended -> ok from the reserve",
              base_request(unattended=False))
    b.helper.config = b.helper_config("control3", unattended=True)

    # ---- helper unavailable: two ways --------------------------------------------
    b.helper.canned = b"this is not json\n"
    expect_refusal(b, "helper answers out of protocol -> helper_unavailable, stage=endpoint",
                   base_request(), "helper_unavailable")
    b.helper.canned = None
    real_path = b.server.cfg["helper_socket"]
    b.server.cfg["helper_socket"] = os.path.join(b.dir, "no-such.sock")
    expect_refusal(b, "helper socket absent -> helper_unavailable, stage=endpoint",
                   base_request(), "helper_unavailable")
    b.server.cfg["helper_socket"] = real_path
    expect_ok(b, "control: helper back -> ok", base_request())

    # ---- the audit file: one line per POST, the schema, and NO CONTENT --------
    lines = b.audit_lines()
    if len(lines) == b.posts:
        report("ok", f"audit: exactly one line per request ({len(lines)})")
    else:
        report("FAIL", "audit: line count", f"{len(lines)} lines for {b.posts} requests")
    bad_keys = [l for l in lines if tuple(l) != harness.Audit.FIELDS]
    if not bad_keys:
        report("ok", "audit: every line has exactly the schema's fields, in order")
    else:
        report("FAIL", "audit: field set drift", str(bad_keys[:1]))

    # Closed grammars. A value that is a string must be one of these; anything
    # else is a free-text field, which the schema forbids.
    grammars = {
        "request_id": re.compile(r"^[0-9a-f]{32}$"),
        "ts": re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$"),
        "client_declared": harness.KEY_RE,
        "role": harness.KEY_RE,
        "provider": harness.KEY_RE,
        "model": re.compile(r"^[a-z0-9][a-z0-9.-]{0,63}$"),
        "kind_declared": re.compile(r"^(question|task|command)$"),
        "class": re.compile("^(" + "|".join(CLASSES) + ")$"),
        "rule": re.compile(r"^(C1|C2|T1|T2|T3|T4|Q0|Q1|Q2|U)$"),
        "outcome": re.compile("^(ok|" + "|".join(harness.ENDPOINT_KINDS + harness.HELPER_KINDS) + ")$"),
        "stage": re.compile(r"^(endpoint|helper)$"),
        "priority": re.compile("^(" + "|".join(harness.HINTS["priority"]) + ")$"),
        "severity": re.compile("^(" + "|".join(harness.HINTS["severity"]) + ")$"),
        "complexity": re.compile("^(" + "|".join(harness.HINTS["complexity"]) + ")$"),
    }
    free_text = []
    for l in lines:
        for k, v in l.items():
            if isinstance(v, str):
                g = grammars.get(k)
                if g is None or not g.match(v):
                    free_text.append((k, v))
            elif not isinstance(v, (int, bool, type(None))):
                free_text.append((k, type(v).__name__))
    if not free_text:
        report("ok", "audit: every string value matches a closed grammar; no free-text field exists")
    else:
        report("FAIL", "audit: free-text value", str(free_text[:3]))
    with open(b.audit_path, encoding="utf-8") as fh:
        blob = fh.read()
    hits = [s for s in CONTENT_STRINGS if s in blob]
    if not hits:
        report("ok", f"audit: none of {len(CONTENT_STRINGS)} content strings appears in the file "
                     "(question, context, source, summary, answer, refusal messages)")
    else:
        report("FAIL", "audit: content found", str(hits))

    # ---- the endpoint never names a provider or model ------------------------------
    names = re.compile(r"claude|codex|haiku|gpt-|openai|anthropic", re.I)
    hits = []
    for f in ("harness.py", "classify.py", "config.example.json"):
        with open(os.path.join(HERE, f), encoding="utf-8") as fh:
            for i, l in enumerate(fh, 1):
                if names.search(l):
                    hits.append(f"{f}:{i}")
    if not hits:
        report("ok", "grep: no provider or model name in harness.py, classify.py, config.example.json")
    else:
        report("FAIL", "grep: provider/model named", str(hits))

    # ---- classify() alone: the README's worked examples, by hand -------------
    table = [
        ("What is a systemd socket unit?", None, (), "question", "Q1"),
        ("the weather in Berlin tomorrow", "question", (), "question", "Q0"),
        ("Refactor the parser to stream tokens.", "question", (), "task", "T3"),
        ("Compare the two adapters", None, ("repository-read",), "task", "T2"),
        ("/restart ssh.service", None, (), "command", "C2"),
        ("Please:\n1. open the file\n2. change the port", None, (), "task", "T4"),
        ("the weather in Berlin tomorrow", None, (), "unclassifiable", "U"),
        ("Berlin has a capital?", None, (), "question", "Q2"),
        ("Explain the volume-dependent contract", "task", (), "task", "T1"),
        ("What is X", "command", (), "command", "C1"),
    ]
    wrong = [(q, classify(q, kind_declared=k, capabilities=c)) for q, k, c, cls, rule in table
             if classify(q, kind_declared=k, capabilities=c) != (cls, rule)]
    if not wrong:
        report("ok", f"classify(): all {len(table)} worked examples from README.md classify as the table says")
    else:
        report("FAIL", "classify(): table drift", str(wrong))

    failed = [n for s, n in results if s != "ok"]
    print()
    if failed:
        print(f"{len(failed)} of {len(results)} checks did not pass.")
        return 1
    print(f"All {len(results)} checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
