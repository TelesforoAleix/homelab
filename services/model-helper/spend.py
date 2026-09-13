"""Persistent, fail-closed spend governor for metered model calls.

One helper process serves one socket connection, so reservations must survive
process exit and concurrent requests.  ``spend.json`` is a JSON document whose
``calls`` array is the ledger.  Each call is one content-free record, updated
from ``reserved`` to ``settled`` or ``released`` under one exclusive flock.

Money is represented as decimal strings.  Binary floats are deliberately not
used for an enforcement boundary: rounding a value down can admit a call that
the configured ceiling should refuse.
"""

from __future__ import annotations

import fcntl
import json
import os
import time
import uuid
from decimal import Decimal, InvalidOperation, ROUND_UP

WINDOWS = {
    "hour": 60 * 60,
    "day": 24 * 60 * 60,
    "week": 7 * 24 * 60 * 60,
    "month": 30 * 24 * 60 * 60,
}
KINDS = ("attended", "unattended")
ZERO = Decimal("0")
MILLION = Decimal("1000000")
MONEY_QUANTUM = Decimal("0.000000001")
TOKEN_KINDS = ("input", "output", "cache_read", "cache_write")


class GovernorUnavailable(Exception):
    """The ledger cannot safely support an enforcement decision."""


def money(value) -> Decimal:
    """Parse a non-negative finite decimal, refusing booleans and bad values."""
    if isinstance(value, bool):
        raise ValueError("money must be a non-negative decimal")
    try:
        out = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ValueError("money must be a non-negative decimal") from exc
    if not out.is_finite() or out < ZERO:
        raise ValueError("money must be a non-negative decimal")
    return out


def money_text(value: Decimal) -> str:
    return format(value.quantize(MONEY_QUANTUM), "f")


def cost_for_usage(usage: dict, price: dict) -> Decimal:
    """Calculate charge without counting cached input as ordinary input too."""
    values = {}
    for kind in TOKEN_KINDS:
        value = usage.get(kind, 0)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ValueError(f"usage.{kind} must be a non-negative integer")
        values[kind] = value
    if values["cache_read"] + values["cache_write"] > values["input"]:
        raise ValueError("usage cache tokens exceed input tokens")
    uncached = values["input"] - values["cache_read"] - values["cache_write"]
    total = Decimal(uncached) * money(price["input"])
    total += Decimal(values["output"]) * money(price["output"])
    total += Decimal(values["cache_read"]) * money(price["cache_read"])
    total += Decimal(values["cache_write"]) * money(price["cache_write"])
    return (total / MILLION).quantize(MONEY_QUANTUM, rounding=ROUND_UP)


def maximum_cost(input_token_bound: int, max_output_tokens: int, price: dict) -> Decimal:
    """Reserve a safe upper bound: dearer input class + maximum output."""
    if input_token_bound < 0 or max_output_tokens < 0:
        raise ValueError("token bounds must be non-negative")
    input_rate = max(money(price[k]) for k in ("input", "cache_read", "cache_write"))
    total = Decimal(input_token_bound) * input_rate
    total += Decimal(max_output_tokens) * money(price["output"])
    return (total / MILLION).quantize(MONEY_QUANTUM, rounding=ROUND_UP)


class SpendGovernor:
    VERSION = 1

    def __init__(self, path: str, budgets: dict, stale_after_seconds: int) -> None:
        self.path = path
        self.stale_after_seconds = stale_after_seconds
        self.budgets = self._validate_budgets(budgets)

    @classmethod
    def initialize(cls, path: str) -> None:
        """Create a new ledger only when an explicit install/fixture step asks."""
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"version": cls.VERSION, "calls": []}, fh,
                      separators=(",", ":"))
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())

    @staticmethod
    def _validate_budgets(budgets: dict) -> dict:
        if not isinstance(budgets, dict):
            raise ValueError("spend.budgets must be an object")
        out = {}
        for kind in KINDS:
            entry = budgets.get(kind)
            if not isinstance(entry, dict):
                raise ValueError(f"spend.budgets.{kind} must be an object")
            out[kind] = {}
            for window in WINDOWS:
                if window not in entry:
                    raise ValueError(f"spend.budgets.{kind}.{window} is required")
                out[kind][window] = money(entry[window])
        return out

    def _open(self):
        try:
            fd = os.open(self.path, os.O_RDWR)
        except OSError as exc:
            raise GovernorUnavailable(f"cannot open spend ledger: {exc.strerror}") from exc
        return os.fdopen(fd, "r+", encoding="utf-8")

    def _load(self, fh) -> dict:
        try:
            fh.seek(0)
            data = json.load(fh)
        except (OSError, ValueError) as exc:
            raise GovernorUnavailable("spend ledger is unreadable or malformed") from exc
        if not isinstance(data, dict) or data.get("version") != self.VERSION \
                or not isinstance(data.get("calls"), list):
            raise GovernorUnavailable("spend ledger has an unsupported schema")
        required = {"ts", "reservation_id", "route", "provider", "model",
                    "budget", "reserved_usd", "status"}
        for i, call in enumerate(data["calls"]):
            if not isinstance(call, dict) or not required.issubset(call):
                raise GovernorUnavailable(f"spend ledger call {i} is malformed")
            if call["budget"] not in KINDS or call["status"] not in \
                    ("reserved", "settled", "released"):
                raise GovernorUnavailable(f"spend ledger call {i} has an invalid state")
            try:
                float(call["ts"])
                money(call["reserved_usd"])
                if call["status"] == "settled":
                    money(call.get("settled_usd"))
            except (TypeError, ValueError) as exc:
                raise GovernorUnavailable(f"spend ledger call {i} has invalid values") from exc
        return data

    @staticmethod
    def _write(fh, data: dict) -> None:
        fh.seek(0)
        fh.truncate()
        json.dump(data, fh, separators=(",", ":"))
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())

    @staticmethod
    def _amount(call: dict) -> Decimal:
        if call["status"] == "reserved":
            return money(call["reserved_usd"])
        if call["status"] == "settled":
            return money(call["settled_usd"])
        return ZERO

    def _totals(self, data: dict, now: float) -> dict:
        totals = {kind: {window: ZERO for window in WINDOWS} for kind in KINDS}
        for call in data["calls"]:
            amount = self._amount(call)
            age = now - float(call["ts"])
            for window, seconds in WINDOWS.items():
                if age < seconds:
                    totals[call["budget"]][window] += amount
        return totals

    def _release_stale(self, data: dict, now: float) -> list[str]:
        released = []
        for call in data["calls"]:
            if call["status"] == "reserved" \
                    and now - float(call["ts"]) > self.stale_after_seconds:
                call["status"] = "released"
                call["settled_usd"] = money_text(ZERO)
                call["release_reason"] = "stale reservation"
                call["completed_ts"] = now
                released.append(call["reservation_id"])
        return released

    def reserve(self, *, route: str, provider: str, model: str,
                unattended: bool, amount: Decimal, request_id: str = "") \
            -> tuple[bool, str, str, list[str]]:
        """Check all four windows and persist before returning permission."""
        now = time.time()
        kind = "unattended" if unattended else "attended"
        amount = money(amount)
        try:
            with self._open() as fh:
                fcntl.flock(fh, fcntl.LOCK_EX)
                try:
                    data = self._load(fh)
                    stale = self._release_stale(data, now)
                    totals = self._totals(data, now)
                    for window in WINDOWS:
                        used = totals[kind][window]
                        ceiling = self.budgets[kind][window]
                        if used + amount > ceiling:
                            if stale:
                                self._write(fh, data)
                            return False, (
                                f"{kind} {window} spend ceiling reached "
                                f"(${money_text(used)} + ${money_text(amount)} > "
                                f"${money_text(ceiling)})"
                            ), "", stale
                    reservation_id = uuid.uuid4().hex
                    call = {
                        "ts": now,
                        "reservation_id": reservation_id,
                        "request_id": request_id,
                        "route": route,
                        "provider": provider,
                        "model": model,
                        "budget": kind,
                        "usage": None,
                        "reserved_usd": money_text(amount),
                        "settled_usd": None,
                        "status": "reserved",
                        "window_totals_after": {
                            w: money_text(totals[kind][w] + amount) for w in WINDOWS
                        },
                    }
                    data["calls"].append(call)
                    self._write(fh, data)
                    return True, (
                        f"{kind} reserved ${money_text(amount)}; "
                        f"hour ${call['window_totals_after']['hour']}/"
                        f"${money_text(self.budgets[kind]['hour'])}"
                    ), reservation_id, stale
                finally:
                    fcntl.flock(fh, fcntl.LOCK_UN)
        except GovernorUnavailable:
            raise
        except OSError as exc:
            raise GovernorUnavailable(f"cannot update spend ledger: {exc.strerror}") from exc

    def _finish(self, reservation_id: str, *, status: str, usage: dict | None,
                amount: Decimal, reason: str = "", gateway_cost=None) -> dict:
        now = time.time()
        try:
            with self._open() as fh:
                fcntl.flock(fh, fcntl.LOCK_EX)
                try:
                    data = self._load(fh)
                    match = next((c for c in data["calls"]
                                  if c["reservation_id"] == reservation_id), None)
                    if match is None or match["status"] != "reserved":
                        raise GovernorUnavailable("spend reservation is missing or already finished")
                    reserved = money(match["reserved_usd"])
                    actual = money(amount)
                    # The reservation should be the hard boundary. If the
                    # estimate was wrong, the money is already spent: settle
                    # at actual (never falsify the ledger) and make the
                    # overshoot visible for the next call.
                    if actual > reserved:
                        reason = (reason + "; " if reason else "") + \
                                 "actual exceeded reservation"
                    match["status"] = status
                    match["usage"] = usage
                    match["settled_usd"] = money_text(actual)
                    match["completed_ts"] = now
                    if reason:
                        match["release_reason" if status == "released" else "settle_note"] = reason
                    if gateway_cost is not None:
                        match["gateway_cost_usd"] = money_text(money(gateway_cost))
                    totals = self._totals(data, now)
                    match["window_totals_after"] = {
                        w: money_text(totals[match["budget"]][w]) for w in WINDOWS
                    }
                    self._write(fh, data)
                    return dict(match)
                finally:
                    fcntl.flock(fh, fcntl.LOCK_UN)
        except GovernorUnavailable:
            raise
        except OSError as exc:
            raise GovernorUnavailable(f"cannot update spend ledger: {exc.strerror}") from exc

    def settle(self, reservation_id: str, usage: dict, price: dict,
               gateway_cost=None, *, reason: str = "") -> dict:
        return self._finish(reservation_id, status="settled", usage=usage,
                            amount=cost_for_usage(usage, price), reason=reason,
                            gateway_cost=gateway_cost)

    def settle_reserved_maximum(self, reservation_id: str, reason: str) -> dict:
        with self._open() as fh:
            fcntl.flock(fh, fcntl.LOCK_SH)
            try:
                data = self._load(fh)
                match = next((c for c in data["calls"]
                              if c["reservation_id"] == reservation_id), None)
                if match is None:
                    raise GovernorUnavailable("spend reservation is missing")
                amount = money(match["reserved_usd"])
            finally:
                fcntl.flock(fh, fcntl.LOCK_UN)
        return self._finish(reservation_id, status="settled", usage=None,
                            amount=amount, reason=reason)

    def release(self, reservation_id: str, reason: str) -> dict:
        return self._finish(reservation_id, status="released", usage=None,
                            amount=ZERO, reason=reason)

    def snapshot(self) -> tuple[dict, list[str]]:
        now = time.time()
        try:
            with self._open() as fh:
                fcntl.flock(fh, fcntl.LOCK_EX)
                try:
                    data = self._load(fh)
                    stale = self._release_stale(data, now)
                    if stale:
                        self._write(fh, data)
                    totals = self._totals(data, now)
                    out = {
                        kind: {
                            window: {
                                "spent_usd": money_text(totals[kind][window]),
                                "ceiling_usd": money_text(self.budgets[kind][window]),
                            } for window in WINDOWS
                        } for kind in KINDS
                    }
                    out["week_ledger_count"] = sum(
                        1 for c in data["calls"]
                        if now - float(c["ts"]) < WINDOWS["week"]
                        and (c["status"] == "settled"
                             or (c["status"] == "released"
                                 and str(c.get("release_reason", ""))
                                 .startswith("provider refusal:")))
                    )
                    return out, stale
                finally:
                    fcntl.flock(fh, fcntl.LOCK_UN)
        except GovernorUnavailable:
            raise
        except OSError as exc:
            raise GovernorUnavailable(f"cannot read spend ledger: {exc.strerror}") from exc
