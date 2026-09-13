"""
Home Lab model helper — Phase 09, ADR-025.

THIS PROCESS EXISTS TO HOLD A CREDENTIAL THE BOT MUST NOT HAVE
--------------------------------------------------------------
Phase 07 proved, by attempting it, that `homelab-bot` cannot read
/home/aleix/.claude/.credentials.json or /home/aleix/.codex/auth.json. Phase 09
had to make model calls anyway. There were three ways to do that and two of them
were wrong:

  copy the credential to homelab-bot ......... rejected outright
  add homelab-bot to a group that can read it  rejected outright
  let the bot run something as another user .. rejected: the bot would need an
                                               escalation mechanism, and the
                                               thing it escalates to is a shell
  ---
  put the CALL where the credential already is, and let the bot ASK  <-- this

So this runs as `aleix`, who already has both credentials, and the bot talks to
it over a UNIX socket. The bot gains no group, no sudoers entry, and no read
access to /home/aleix. `id homelab-bot` is unchanged by this phase.

The socket is the entire attack surface, so it is deliberately tiny:

  IT IS NOT A SHELL. Two operations, `ping` and `ask`. `ask` takes a string and
  returns a string. There is no operation that names a file, a command, a model,
  a provider or a path -- the caller cannot choose ANY of those. Everything the
  CLI is invoked with comes from a root-owned config file, never from the wire.

PHASE 15.0: THE CALLER ASKS BY WHO IT IS, NOT BY WHAT MODEL IT WANTS
--------------------------------------------------------------------
The config file is now a REGISTRY (ADR-026 §2): providers, models beneath them,
and a `routes` table keyed by a routing key -- in the agent world the agent's
role (ADR-034 §5), today only the bot's, and the bot sends none, so it gets
`default_route`. The key is a lookup into root-owned config, never a value that
reaches argv. An unknown key is refused, never defaulted. `priority`,
`severity`, `complexity` and `summary` are accepted so the protocol is stable
for Phase 23.0, validated, logged, and IGNORED for routing: resolve_route() is
the one place a route is chosen and it receives the key alone.

Every provider carries `unattended` (ADR-026 §3). A call that declares itself
unattended is refused before the cap reservation if no provider on its route
may serve it -- so the refusal costs nothing, the Phase 09 rule for caps. And
unattended calls stop short of an owner reserve (ADR-026 §6, limits.py).

WHO MAY CONNECT IS NOT DECIDED HERE
-----------------------------------
It is decided by systemd, in the .socket unit, before this process exists:
SocketMode=0660 with SocketGroup=homelab-bot. Filesystem permissions on the
socket inode are the access control. That is deliberate -- an access rule in a
committed unit file is reviewable; an access check in a Python process is a
thing that can be bypassed by a bug in the same Python process.

WHAT LEAVES THE MACHINE
-----------------------
The owner's question, and the literal output of /status: hostname, uptime, load,
memory, disk. Five figures the owner can already read on their phone. Nothing
else -- no logs, no journal, no file contents, no unit files, no allowlists.

That is a security boundary, not a scoping accident. Journal lines are written
by other software, some of it reachable from the network. Feeding them to a
model would mean an unbounded amount of host data leaving the machine, chosen by
whatever could write a log line rather than by the owner. Five numeric fields
cannot carry an instruction.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from limits import Limiter          # noqa: E402
from providers import BY_NAME       # noqa: E402

CONFIG = os.environ.get("HOMELAB_MODEL_HELPER_CONFIG",
                        "/etc/homelab-model-helper/config.json")

# A hard ceiling that does not depend on the config being sane. The bot caps the
# question too; this is the backstop for anything that reaches the socket.
MAX_REQUEST_BYTES = 16 * 1024


def log(msg: str) -> None:
    """stderr goes to the journal under the unit name."""
    print(msg, file=sys.stderr, flush=True)


# Routing keys and route names share one grammar: short, lower-case, no path
# characters. Anything else is refused before it is looked up.
KEY_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")

# The hints. Closed sets: a value outside them is a bad request, not a value to
# coerce. None of these is ever read by resolve_route().
HINTS = {
    "priority": ("low", "normal", "high", "critical"),
    "severity": ("low", "medium", "high", "critical"),
    "complexity": ("low", "medium", "high"),
}
MAX_SUMMARY_CHARS = 200

# Every field `ask` may carry. Anything else is refused BY NAME (test 8): the
# wire protocol is exactly where "the caller cannot name a program" would be
# lost by accident, and a rejected field is louder than an ignored one.
ASK_FIELDS = frozenset({"v", "op", "user_id", "question", "context",
                        "role", "unattended", "summary", *HINTS})


def load_config() -> dict:
    """
    Read and validate the registry. Every problem is a ValueError with the
    path that caused it; the caller turns that into "helper misconfigured" on
    the wire and the full text in the journal.

    The Phase 09 shape ("providers" as a list) is REFUSED, not migrated:
    guessing at a config is how a service runs with a cap it does not have.
    """
    with open(CONFIG, encoding="utf-8") as fh:
        cfg = json.load(fh)

    providers = cfg.get("providers")
    if isinstance(providers, list):
        raise ValueError("config: Phase 09 shape ('providers' is a list); "
                         "migrate to the Phase 15.0 registry (see config.example.json)")
    if not isinstance(providers, dict) or not providers:
        raise ValueError("config: 'providers' must be a non-empty object")

    for name, entry in providers.items():
        if name not in BY_NAME:
            raise ValueError(f"config: unknown provider {name!r} (adding a provider is code)")
        if not isinstance(entry, dict):
            raise ValueError(f"config: providers.{name} must be an object")
        if not entry.get("bin") or not os.path.isabs(str(entry["bin"])):
            raise ValueError(f"config: providers.{name}.bin must be an absolute path")
        if not isinstance(entry.get("unattended"), bool):
            raise ValueError(f"config: providers.{name}.unattended must be true or false")
        # Reserved for Phase 15.1. Their PRESENCE is refused: the governor that
        # makes a metered provider safe (ADR-033 §5) does not exist here, and a
        # field that appears to work and does nothing is how a paid call
        # happens without one. 15.1 removes this in the commit that ships the
        # governor, not before.
        for reserved in ("metered", "credential"):
            if reserved in entry:
                raise ValueError(f"config: providers.{name}.{reserved} is not supported "
                                 "before Phase 15.1 (no spend governor exists)")
        models = entry.get("models")
        if not isinstance(models, dict) or not models:
            raise ValueError(f"config: providers.{name}.models must be a non-empty object")
        for key, model in models.items():
            if not KEY_RE.match(key):
                raise ValueError(f"config: providers.{name}.models.{key!r}: bad model key")
            if not isinstance(model, dict) or not isinstance(model.get("id"), str) \
                    or not model["id"].strip():
                raise ValueError(f"config: providers.{name}.models.{key}.id must be a string")

    routes = cfg.get("routes")
    if not isinstance(routes, dict) or not routes:
        raise ValueError("config: 'routes' must be a non-empty object")
    for route, entries in routes.items():
        if not KEY_RE.match(route):
            raise ValueError(f"config: routes.{route!r}: bad route name")
        if not isinstance(entries, list) or not entries:
            raise ValueError(f"config: routes.{route} must be a non-empty list")
        for ref in entries:
            pname, _, mkey = str(ref).partition("/")
            if pname not in providers or mkey not in providers[pname]["models"]:
                raise ValueError(f"config: routes.{route}: {ref!r} is not a registered provider/model")

    default = cfg.get("default_route")
    if default not in routes:
        raise ValueError("config: 'default_route' must name a route")

    caps = cfg.get("caps")
    if not isinstance(caps, dict):
        raise ValueError("config: 'caps' must be an object")
    for k in ("per_hour", "per_day"):
        if not isinstance(caps.get(k), int) or caps[k] < 0:
            raise ValueError(f"config: caps.{k} must be a non-negative integer")
    reserve = caps.get("owner_reserve")
    if not isinstance(reserve, dict):
        raise ValueError("config: caps.owner_reserve must be an object (ADR-026 §6)")
    for k in ("per_hour", "per_day"):
        if not isinstance(reserve.get(k), int) or not 0 <= reserve[k] <= caps[k]:
            raise ValueError(f"config: caps.owner_reserve.{k} must be an integer in 0..caps.{k}")

    if not isinstance(cfg.get("state_file"), str) or not os.path.isabs(cfg["state_file"]):
        raise ValueError("config: 'state_file' must be an absolute path")
    return cfg


def resolve_route(cfg: dict, key: str | None) -> tuple[str, list[tuple[str, str]]]:
    """
    THE ONE PLACE A ROUTE IS CHOSEN.

    Receives the routing key and nothing else -- not the hints, not the
    summary, not the unattended flag. Returns (route name, ordered list of
    (provider name, model key)). Raises KeyError for an unknown key; the caller
    refuses, it never defaults (brief §9).
    """
    name = cfg["default_route"] if key is None else key
    if name not in cfg["routes"]:
        raise KeyError(name)
    return name, [tuple(ref.split("/", 1)) for ref in cfg["routes"][name]]


def build_provider(cfg: dict, pname: str, mkey: str):
    entry = cfg["providers"][pname]
    timeout = int(cfg.get("timeout_seconds", 120))
    return BY_NAME[pname](entry["bin"], entry["models"][mkey]["id"], timeout)


def read_request() -> dict:
    """
    One JSON object, one line. Bounded before parsing.

    Reading from stdin works because the unit is Accept=yes: systemd hands the
    accepted connection to this process as stdin and stdout. There is no socket
    code here at all, which is the point -- the smallest thing that can be wrong.
    """
    raw = sys.stdin.buffer.readline(MAX_REQUEST_BYTES + 1)
    if len(raw) > MAX_REQUEST_BYTES:
        raise ValueError("request too large")
    return json.loads(raw.decode("utf-8"))


def reply(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _bad(message: str) -> dict:
    return {"ok": False, "kind": "error", "message": message}


def handle_ask(req: dict, cfg: dict) -> dict:
    """
    Order matters and is the design: shape, route, eligibility, THEN the cap
    reservation. Every refusal above the reservation costs nothing.
    """
    user = req.get("user_id", "unknown")

    # --- 1. shape ----------------------------------------------------------
    for field in req:
        if field not in ASK_FIELDS:
            log(f"ask user={user} outcome=bad_request field={field!r}")
            return _bad(f"unknown field {field!r}")

    question = req.get("question")
    context = req.get("context", "")
    if not isinstance(question, str) or not question.strip():
        return _bad("empty question")
    if not isinstance(context, str):
        return _bad("bad context")

    role = req.get("role")
    if role is not None and (not isinstance(role, str) or not KEY_RE.match(role)):
        return _bad("bad role")
    unattended = req.get("unattended", False)
    if not isinstance(unattended, bool):
        return _bad("bad unattended flag")
    summary = req.get("summary", "")
    if not isinstance(summary, str) or len(summary) > MAX_SUMMARY_CHARS:
        return _bad("bad summary")
    hints = []
    for hint, allowed in HINTS.items():
        value = req.get(hint)
        if value is None:
            continue
        if value not in allowed:
            return _bad(f"bad {hint}")
        hints.append(f"{hint}={value}")
    # Logged, and that is the whole of what the hints do. The summary is the
    # caller's prose and is logged as a length, like the question.
    tags = " ".join(hints + [f"summary_len={len(summary)}"])

    max_q = int(cfg.get("max_question_chars", 500))
    question = question.strip()[:max_q]
    context = context[:2000]

    # --- 2. route ------------------------------------------------------------
    try:
        route, entries = resolve_route(cfg, role)
    except KeyError:
        log(f"ask user={user} key={role} outcome=unknown_role")
        return {"ok": False, "kind": "unknown_role",
                "message": f"no route for role {role!r}"}

    # --- 3. eligibility (ADR-026 §3) -----------------------------------------
    if unattended:
        skipped = [p for p, _ in entries if not cfg["providers"][p]["unattended"]]
        entries = [(p, m) for p, m in entries if cfg["providers"][p]["unattended"]]
        if not entries:
            log(f"ask user={user} route={route} unattended=true outcome=ineligible "
                f"providers={','.join(skipped)}")
            return {"ok": False, "kind": "ineligible",
                    "message": f"no provider on route {route!r} may serve unattended calls"}
        if skipped:
            log(f"ask user={user} route={route} unattended=true "
                f"skipped_ineligible={','.join(skipped)}")

    # --- 4. cap reservation, then the call, then fallback along the route ----
    caps = cfg["caps"]
    limiter = Limiter(cfg["state_file"],
                      int(caps["per_hour"]), int(caps["per_day"]),
                      int(caps["owner_reserve"]["per_hour"]),
                      int(caps["owner_reserve"]["per_day"]))

    spent: list[str] = []
    for pname, mkey in entries:
        provider = build_provider(cfg, pname, mkey)
        allowed, note = limiter.check_and_reserve(provider.name, unattended=unattended)
        if not allowed:
            log(f"ask user={user} route={route} provider={provider.name} outcome=capped")
            spent.append(note)
            continue

        started = time.monotonic()
        answer = provider.ask(question, context)
        took = time.monotonic() - started

        # The question itself is NOT logged. It is the owner's own text and the
        # journal is not the place for it; the length is enough to debug with.
        log(f"ask user={user} route={route} unattended={str(unattended).lower()} {tags} "
            f"provider={answer.provider} model={answer.model} "
            f"qlen={len(question)} took={took:.1f}s "
            f"outcome={'ok' if answer.ok else answer.kind} {note}")

        if answer.ok:
            max_a = int(cfg.get("max_answer_chars", 3000))
            return {"ok": True, "provider": answer.provider,
                    "model": answer.model, "text": answer.text[:max_a]}

        if answer.kind == "exhausted":
            hint = f" (retry at {answer.retry_hint})" if answer.retry_hint else ""
            spent.append(f"{answer.provider}: usage limit reached{hint}")
            continue

        # A real error is not a reason to spend the other subscription too.
        return {"ok": False, "kind": "error", "provider": answer.provider,
                "message": answer.detail}

    return {"ok": False, "kind": "exhausted",
            "message": "no provider could answer",
            "detail": spent}


def main() -> int:
    try:
        cfg = load_config()
    except Exception as exc:                      # noqa: BLE001
        log(f"config error: {exc}")
        reply({"ok": False, "kind": "error", "message": "helper misconfigured"})
        return 1

    try:
        req = read_request()
    except Exception as exc:                      # noqa: BLE001
        log(f"bad request: {exc}")
        reply({"ok": False, "kind": "error", "message": "bad request"})
        return 1

    op = req.get("op")
    if op == "ping":
        # Deliberately makes NO model call. The install-time connectivity proof
        # must not cost the owner a slice of their allowance.
        # Still a list of names: the Phase 09 probe and the bot read it as one.
        reply({"ok": True, "op": "ping", "providers": list(cfg["providers"])})
        return 0
    if op == "ask":
        reply(handle_ask(req, cfg))
        return 0

    reply({"ok": False, "kind": "error", "message": f"unknown op {op!r}"})
    return 1


if __name__ == "__main__":
    sys.exit(main())
