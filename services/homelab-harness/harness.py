"""
Home Lab harness — the endpoint. Phase 23.0, layers 1, 2 and 9.

WHAT THIS PROCESS IS
--------------------
One always-running, loopback-only HTTP service that accepts a normalised
request from any local client, attaches the runtime's own record of where it
came from, classifies it cheaply (classify.py), hands a `question` to the model
helper over the Phase 15.0 wire protocol, returns the result to the client with
the request id, and writes one audit line per request. Nothing else.

WHAT IT DOES NOT HOLD, AND WHY
------------------------------
No credential. The model call happens in the helper, as `aleix`, behind a
UNIX socket whose group is the access control (ADR-025; ADR-048 makes that
group `homelab-model` and this account a member). A compromised harness can
therefore do two things: ask the helper as one more capped consumer, and write
its own audit file. It cannot name a model, a provider, a binary or a path --
the wire protocol refuses those by name in the helper, and this file never
tries. The only routing key on the wire is the client's `role`, forwarded
unchanged (ADR-034 §5); `priority`, `severity` and `complexity` are carried and
never read.

IDENTITY IS ATTACHED HERE, NEVER READ FROM THE BODY (ADR-034 §11)
-----------------------------------------------------------------
A request body that carries `client`, `user`, `user_id`, `origin`, `peer`,
`identity`, `request_id` or `ts` is refused BY NAME with kind
`identity_in_body`. What the runtime attaches is: the request id it minted,
its own timestamp, the client's declared label from the `X-Homelab-Client`
header (recorded as `client_declared` -- a LABEL, not an identity; nothing
authenticates it in 23.0, brief §6.10), and the peer credentials where the
transport gives them. Loopback TCP gives none, so `peer` is recorded as null,
never guessed.

THE AUDIT LINE HOLDS NO CONTENT, EVER (brief §6.5)
--------------------------------------------------
Every field in it is an id, a timestamp, a bounded label, a closed enum, a
boolean, a number or null. The question, the context, the summary and the
output appear only as LENGTHS. Refusal messages -- which can echo a client-
chosen field name -- do not appear at all; the audit line records the refusal
KIND. fixture-tests.py asserts this on the file: every string value must match
a closed grammar, and none of the content strings the fixture sent may be
found in it. The same discipline as 15.0's `summary_len`, applied everywhere.

RESULTS ARE THE CLIENT'S TO RECORD (brief §6.3)
-----------------------------------------------
The state directory holds audit.jsonl and nothing else. The endpoint returns
the result and forgets it. That is why this unit lives on root and carries no
volume-dependent contract: it is up and useful with the volume locked.
"""

from __future__ import annotations

import json
import os
import re
import socket
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from classify import DECLARABLE_KINDS, REFUSAL_FOR_CLASS, classify  # noqa: E402

VERSION = 1
CONFIG = os.environ.get("HOMELAB_HARNESS_CONFIG", "/etc/homelab-harness/config.json")

# Loopback, refused in code (ADR-038 §2). The Workbench's server.py does the
# same; this list is the whole of what the unit may be pointed at.
LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")

# Labels and routing keys share the helper's grammar (helper.py KEY_RE): short,
# lower-case, no path characters. A label under this grammar cannot carry a
# sentence, which is what lets `client_declared` and `role` appear in the audit
# line at all.
KEY_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")

# The hints. Copied from helper.py's HINTS so a bad value is refused HERE, at
# no cost, instead of spawning a helper instance to be told the same thing. If
# helper.py changes its enums this must change too -- fixture test "hints:
# enums match the helper" fails otherwise.
HINTS = {
    "priority": ("low", "normal", "high", "critical"),
    "severity": ("low", "medium", "high", "critical"),
    "complexity": ("low", "medium", "high"),
}
MAX_SUMMARY_CHARS = 200

# Every field a request body may carry. Anything else is refused by name.
REQUEST_FIELDS = frozenset({"v", "kind", "role", "question", "context",
                            "capabilities", "unattended", "summary", *HINTS})

# Fields that would claim identity or origin. Refused by name with their own
# kind so a client (and test 2) can tell "you tried to say who you are" from
# "you sent a field I do not know".
IDENTITY_FIELDS = frozenset({"client", "user", "user_id", "origin", "peer",
                             "identity", "request_id", "ts"})

CLIENT_HEADER = "X-Homelab-Client"

# Refusal kinds this process produces itself. The helper's kinds
# (unknown_role, ineligible, exhausted, error) are forwarded with
# stage="helper" and are NOT in this set -- the client can tell them apart.
ENDPOINT_KINDS = ("bad_request", "identity_in_body", "too_large",
                  "needs_decomposition", "not_a_request", "unclassifiable",
                  "helper_unavailable")
HELPER_KINDS = ("unknown_role", "ineligible", "exhausted", "error")

# HTTP status per refusal kind. Clients read `kind`, not the status; the status
# is for curl and for humans. Documented in README.md.
STATUS_FOR_KIND = {
    "bad_request": 400, "identity_in_body": 400, "too_large": 413,
    "needs_decomposition": 422, "not_a_request": 422, "unclassifiable": 422,
    "helper_unavailable": 503,
    "unknown_role": 400, "ineligible": 422, "exhausted": 429, "error": 502,
}


def log(msg: str) -> None:
    """stderr goes to the journal under the unit name. Never content."""
    print(msg, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------

def load_config(path: str = CONFIG) -> dict:
    """
    Read and validate the config. Every problem is a ValueError naming the
    key. Defaults are filled in here so the rest of the file reads cfg[...]
    without .get() and a missing key cannot silently mean "unbounded".
    """
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    cfg.pop("_format", None)

    listen = cfg.get("listen")
    if not isinstance(listen, dict):
        raise ValueError("config: 'listen' must be an object")
    if listen.get("host") not in LOOPBACK_HOSTS:
        raise ValueError(f"config: listen.host must be one of {LOOPBACK_HOSTS} (ADR-038 §2)")
    if not isinstance(listen.get("port"), int) or not 1024 <= listen["port"] <= 65535:
        raise ValueError("config: listen.port must be an integer in 1024..65535")

    if not isinstance(cfg.get("helper_socket"), str) or not os.path.isabs(cfg["helper_socket"]):
        raise ValueError("config: 'helper_socket' must be an absolute path")

    for key, default, lo in (("helper_timeout_seconds", 280, 1),
                             ("max_body_bytes", 16384, 1024),
                             ("max_question_chars", 500, 1),
                             ("max_context_items", 20, 0),
                             ("max_context_chars", 2000, 0),
                             ("max_capabilities", 16, 0)):
        value = cfg.setdefault(key, default)
        if not isinstance(value, int) or value < lo:
            raise ValueError(f"config: {key} must be an integer >= {lo}")

    audit = cfg.get("audit_file")
    if audit is None:
        state = os.environ.get("STATE_DIRECTORY")
        if not state:
            raise ValueError("config: 'audit_file' is unset and $STATE_DIRECTORY is not set")
        cfg["audit_file"] = os.path.join(state.split(":")[0], "audit.jsonl")
    elif not isinstance(audit, str) or not os.path.isabs(audit):
        raise ValueError("config: 'audit_file' must be an absolute path or null")
    return cfg


# --------------------------------------------------------------------------
# The audit line (layer 9)
# --------------------------------------------------------------------------

class Audit:
    """
    One JSON object per line, appended under a lock. The field set is fixed
    here and nowhere else; write() refuses a key outside it, so a future edit
    that tries to log a message or a text field fails at the first request in
    the fixture rather than at the first request on the node.
    """

    FIELDS = (
        "v", "request_id", "ts", "client_declared", "peer",
        "kind_declared", "class", "rule", "role", "unattended",
        "priority", "severity", "complexity",
        "outcome", "stage", "provider", "model", "cost", "duration_ms",
        "question_len", "context_items", "context_len", "summary_len",
        "capabilities_n", "output_len",
    )

    def __init__(self, path: str) -> None:
        self.path = path
        self._lock = threading.Lock()

    def write(self, line: dict) -> None:
        unknown = set(line) - set(self.FIELDS)
        if unknown:
            raise ValueError(f"audit: refusing fields outside the schema: {sorted(unknown)}")
        full = {k: line.get(k) for k in self.FIELDS}
        data = (json.dumps(full, separators=(",", ":")) + "\n").encode("utf-8")
        with self._lock:
            fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            try:
                os.write(fd, data)
            finally:
                os.close(fd)


# --------------------------------------------------------------------------
# The helper client (the 15.0 wire protocol)
# --------------------------------------------------------------------------

class HelperUnavailable(Exception):
    """The helper could not be reached or did not answer in protocol."""


def helper_call(cfg: dict, payload: dict, *, timeout: float | None = None) -> dict:
    """
    One JSON line in, one JSON line out, over AF_UNIX. Mirrors the bot's
    model_client.py. The timeout defaults to helper_timeout_seconds (280) so
    this process outlives the helper's RuntimeMaxSec (270, brief §6.9) and
    reports the helper's failure rather than its own.
    """
    timeout = cfg["helper_timeout_seconds"] if timeout is None else timeout
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect(cfg["helper_socket"])
        sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
        sock.close()
    except socket.timeout as exc:
        raise HelperUnavailable("helper did not answer in time") from exc
    except OSError as exc:
        raise HelperUnavailable(f"helper unreachable (errno {exc.errno})") from exc
    raw = b"".join(chunks).decode("utf-8", "replace").strip().splitlines()
    if not raw:
        raise HelperUnavailable("helper closed the connection without a reply")
    try:
        reply = json.loads(raw[0])
    except ValueError as exc:
        raise HelperUnavailable("helper reply was not JSON") from exc
    if not isinstance(reply, dict) or "ok" not in reply:
        raise HelperUnavailable("helper reply was not in protocol")
    return reply


# --------------------------------------------------------------------------
# Validation (layer 1) — shape first, identity by name, then bounds
# --------------------------------------------------------------------------

class Refusal(Exception):
    def __init__(self, kind: str, message: str) -> None:
        super().__init__(message)
        self.kind = kind
        self.message = message


def validate(body: dict, cfg: dict) -> dict:
    """
    Returns the validated request as a dict with every optional field filled
    in. Raises Refusal. Order: identity fields (named), unknown fields
    (named), version, then each field's type and bound. Nothing here reads the
    question's text for meaning -- that is classify()'s job and comes after.
    """
    if not isinstance(body, dict):
        raise Refusal("bad_request", "body must be a JSON object")

    for field in sorted(body):
        if field in IDENTITY_FIELDS:
            raise Refusal("identity_in_body",
                          f"field {field!r} is attached by the runtime and cannot be set by the request")
    for field in sorted(body):
        if field not in REQUEST_FIELDS:
            raise Refusal("bad_request", f"unknown field {field!r}")

    if body.get("v") != VERSION:
        raise Refusal("bad_request", f"'v' must be {VERSION}")

    kind = body.get("kind")
    if kind is not None and kind not in DECLARABLE_KINDS:
        raise Refusal("bad_request", f"'kind' must be one of {list(DECLARABLE_KINDS)} or absent")

    # Required: the endpoint does not default an agent's request onto the
    # owner's route. The helper would (absent role -> default_route); we do
    # not let that happen from here.
    role = body.get("role")
    if not isinstance(role, str) or not KEY_RE.match(role):
        raise Refusal("bad_request", "'role' is required and must match ^[a-z0-9][a-z0-9-]{0,31}$")

    question = body.get("question")
    if not isinstance(question, str) or not question.strip():
        raise Refusal("bad_request", "'question' is required and must be a non-empty string")
    question = question.strip()
    if len(question) > cfg["max_question_chars"]:
        raise Refusal("too_large",
                      f"'question' is {len(question)} chars; the limit is {cfg['max_question_chars']}")

    # Context: a list of items, each {"text": str, "source": str|null}. The
    # source is the client's provenance (ADR-039 §3), carried as received.
    # Today the Workbench sends none; that is recorded for 23.2.
    context = body.get("context", [])
    if not isinstance(context, list):
        raise Refusal("bad_request", "'context' must be a list of items")
    if len(context) > cfg["max_context_items"]:
        raise Refusal("too_large",
                      f"'context' has {len(context)} items; the limit is {cfg['max_context_items']}")
    items: list[dict] = []
    total = 0
    for i, item in enumerate(context):
        if not isinstance(item, dict) or set(item) - {"text", "source"}:
            raise Refusal("bad_request", f"context[{i}] must be an object with 'text' and optional 'source'")
        text = item.get("text")
        source = item.get("source")
        if not isinstance(text, str):
            raise Refusal("bad_request", f"context[{i}].text must be a string")
        if source is not None and not isinstance(source, str):
            raise Refusal("bad_request", f"context[{i}].source must be a string or null")
        total += len(text) + (len(source) if source else 0)
        items.append({"text": text, "source": source})
    if total > cfg["max_context_chars"]:
        raise Refusal("too_large",
                      f"'context' totals {total} chars; the limit is {cfg['max_context_chars']}")

    capabilities = body.get("capabilities", [])
    if not isinstance(capabilities, list) or not all(isinstance(c, str) and KEY_RE.match(c)
                                                     for c in capabilities):
        raise Refusal("bad_request", "'capabilities' must be a list of short lower-case names")
    if len(capabilities) > cfg["max_capabilities"]:
        raise Refusal("too_large", f"'capabilities' has {len(capabilities)} entries; "
                                   f"the limit is {cfg['max_capabilities']}")

    unattended = body.get("unattended", False)
    if not isinstance(unattended, bool):
        raise Refusal("bad_request", "'unattended' must be true or false")

    summary = body.get("summary", "")
    if not isinstance(summary, str) or len(summary) > MAX_SUMMARY_CHARS:
        raise Refusal("bad_request", f"'summary' must be a string of at most {MAX_SUMMARY_CHARS} chars")

    hints: dict[str, str | None] = {}
    for hint, allowed in HINTS.items():
        value = body.get(hint)
        if value is not None and value not in allowed:
            raise Refusal("bad_request", f"'{hint}' must be one of {list(allowed)}")
        hints[hint] = value

    return {"kind": kind, "role": role, "question": question, "context": items,
            "capabilities": capabilities, "unattended": unattended,
            "summary": summary, **hints}


def render_context(items: list[dict]) -> str:
    """
    The helper's `context` is one string (helper.py: `context[:2000]`); the
    endpoint's is a list of items with provenance. This is the ONLY transform
    between the two protocols, and it adds nothing the client did not send:
    each item's text, preceded by its source when one was given.
    """
    parts = []
    for item in items:
        if item["source"]:
            parts.append(f"[source: {item['source']}]\n{item['text']}")
        else:
            parts.append(item["text"])
    return "\n\n".join(parts)


def helper_payload(req: dict, client_declared: str) -> dict:
    """
    The 15.0 wire request. Note what is here and what is not: `role`, the
    hints and `summary` pass through unchanged; `capabilities` and `kind` do
    NOT (the helper refuses unknown fields, and neither means anything to
    it); `user_id` is the runtime's label for the consumer, so the helper's
    journal reads `ask user=harness:<client>` -- a string, which the helper
    logs and never validates (OBSERVED in helper.py handle_ask).
    """
    payload = {"v": 1, "op": "ask", "user_id": f"harness:{client_declared}",
               "question": req["question"], "context": render_context(req["context"]),
               "role": req["role"], "unattended": req["unattended"]}
    if req["summary"]:
        payload["summary"] = req["summary"]
    for hint in HINTS:
        if req[hint] is not None:
            payload[hint] = req[hint]
    return payload


# --------------------------------------------------------------------------
# The HTTP surface
# --------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "homelab-harness/1"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    # BaseHTTPRequestHandler logs every request line to stderr, with the path
    # and query -- neither carries content here, but the journal is not the
    # audit record; audit.jsonl is. Silence it.
    def log_message(self, fmt, *args) -> None:  # noqa: D401
        return

    @property
    def cfg(self) -> dict:
        return self.server.cfg  # type: ignore[attr-defined]

    def _send(self, status: int, obj: dict) -> None:
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # --- GET: health, no request accepted ---------------------------------
    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/", "/health"):
            self._send(200, {"ok": True, "service": "homelab-harness", "v": VERSION})
            return
        if self.path == "/health/helper":
            # The helper's `ping` makes no model call, so this costs nothing
            # and proves the socket is reachable AS THIS ACCOUNT -- the
            # ADR-048 group membership, checked live by `verify`.
            try:
                reply = helper_call(self.cfg, {"v": 1, "op": "ping"}, timeout=10)
                self._send(200, {"ok": True, "helper": "reachable",
                                 "providers": reply.get("providers", [])})
            except HelperUnavailable as exc:
                self._send(503, {"ok": False, "helper": "unreachable", "message": str(exc)})
            return
        self._send(404, {"ok": False, "kind": "bad_request", "message": "no such path"})

    # --- POST /v1/request: the endpoint -------------------------------------
    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/request":
            self._send(404, {"ok": False, "kind": "bad_request", "message": "no such path"})
            return
        self.server.handle_request_body(self)  # type: ignore[attr-defined]

    def read_body(self) -> bytes:
        length = self.headers.get("Content-Length")
        if length is None or not length.isdigit():
            raise Refusal("bad_request", "Content-Length is required")
        n = int(length)
        if n > self.cfg["max_body_bytes"]:
            raise Refusal("too_large", f"body is {n} bytes; the limit is {self.cfg['max_body_bytes']}")
        return self.rfile.read(n)


class Harness(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, cfg: dict) -> None:
        host, port = cfg["listen"]["host"], cfg["listen"]["port"]
        if host not in LOOPBACK_HOSTS:
            raise SystemExit(f"refusing to bind {host!r}: the harness is loopback-only (ADR-038 §2)")
        self.cfg = cfg
        self.audit = Audit(cfg["audit_file"])
        super().__init__((host, port), Handler)

    def handle_request_body(self, h: Handler) -> None:
        """
        The whole of one request, in the order the layers run: attach origin
        (1), validate (1), classify (2), forward, record and return (9).
        Every exit writes exactly one audit line.
        """
        started = time.monotonic()
        request_id = uuid.uuid4().hex
        ts = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        line: dict = {"v": VERSION, "request_id": request_id, "ts": ts,
                      "peer": None, "cost": None}
        reply: dict = {"v": VERSION, "request_id": request_id}
        status = 200

        def refuse(kind: str, message: str, stage: str = "endpoint", **extra) -> None:
            nonlocal status
            status = STATUS_FOR_KIND.get(kind, 400)
            reply.update({"ok": False, "kind": kind, "message": message, "stage": stage, **extra})
            line.update({"outcome": kind, "stage": stage})

        try:
            client = h.headers.get(CLIENT_HEADER)
            if not client or not KEY_RE.match(client):
                raise Refusal("bad_request", f"header {CLIENT_HEADER} is required and must match "
                                             "^[a-z0-9][a-z0-9-]{0,31}$")
            line["client_declared"] = client
            reply["client_declared"] = client

            raw = h.read_body()
            try:
                body = json.loads(raw.decode("utf-8"))
            except ValueError as exc:
                raise Refusal("bad_request", "body is not valid JSON") from exc

            req = validate(body, self.cfg)
            line.update({
                "kind_declared": req["kind"], "role": req["role"],
                "unattended": req["unattended"],
                "priority": req["priority"], "severity": req["severity"],
                "complexity": req["complexity"],
                "question_len": len(req["question"]),
                "context_items": len(req["context"]),
                "context_len": len(render_context(req["context"])),
                "summary_len": len(req["summary"]),
                "capabilities_n": len(req["capabilities"]),
            })

            cls, rule = classify(req["question"], kind_declared=req["kind"],
                                 capabilities=req["capabilities"])
            line.update({"class": cls, "rule": rule})
            reply["class"] = cls

            if cls != "question":
                kind = REFUSAL_FOR_CLASS[cls]
                raise Refusal(kind, {
                    "needs_decomposition": "this request is a task; decomposition is not built "
                                           "in 23.0 (addressed to Phase 23.1)",
                    "not_a_request": "this is a command; use the bot, which owns operational verbs",
                    "unclassifiable": "could not classify; declare kind=question if it is one",
                }[kind])

            # --- forward (the only place a model is reached) -------------
            try:
                answer = helper_call(self.cfg, helper_payload(req, client))
            except HelperUnavailable as exc:
                raise Refusal("helper_unavailable", str(exc)) from exc

            line.update({"provider": answer.get("provider"), "model": answer.get("model")})
            if answer.get("ok"):
                text = answer.get("text", "")
                if not isinstance(text, str):
                    raise Refusal("helper_unavailable", "helper reply had no text")
                reply.update({"ok": True, "text": text, "provider": answer.get("provider"),
                              "model": answer.get("model")})
                line.update({"outcome": "ok", "stage": None, "output_len": len(text)})
            else:
                kind = answer.get("kind") if answer.get("kind") in HELPER_KINDS else "error"
                extra = {}
                if isinstance(answer.get("detail"), list):
                    extra["detail"] = answer["detail"]
                refuse(kind, str(answer.get("message", "")), stage="helper", **extra)

        except Refusal as exc:
            refuse(exc.kind, exc.message)
        except Exception as exc:  # noqa: BLE001
            # A bug is reported as the endpoint's own error, never as the
            # helper's, and never with the request in the journal.
            log(f"request={request_id} internal error: {type(exc).__name__}: {exc}")
            refuse("bad_request", "internal error; see the endpoint's journal")

        line["duration_ms"] = int((time.monotonic() - started) * 1000)
        try:
            self.audit.write(line)
        except Exception as exc:  # noqa: BLE001
            # The request already happened; losing the audit line is a fault
            # worth paging on (the journal is what OnFailure= quotes), but
            # not a reason to hide the answer from the client.
            log(f"request={request_id} AUDIT WRITE FAILED: {exc}")
        log(f"request={request_id} client={line.get('client_declared')} "
            f"class={line.get('class')} rule={line.get('rule')} role={line.get('role')} "
            f"outcome={line.get('outcome')} stage={line.get('stage')} "
            f"provider={line.get('provider')} model={line.get('model')} "
            f"qlen={line.get('question_len')} took={line['duration_ms']}ms")
        h._send(status, reply)


def main() -> int:
    try:
        cfg = load_config()
    except Exception as exc:  # noqa: BLE001
        log(f"config error: {exc}")
        return 1
    server = Harness(cfg)
    log(f"homelab-harness v{VERSION} listening on {cfg['listen']['host']}:{cfg['listen']['port']} "
        f"(loopback only); helper={cfg['helper_socket']}; audit={cfg['audit_file']}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
