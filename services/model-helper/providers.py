"""
Model providers — Phase 09, ADR-025.

This file runs inside the HELPER, as `aleix`. It never runs inside the bot.
That split is the whole design: `homelab-bot` cannot read either OAuth
credential and must not gain the ability, so the process that shells out to a
CLI is the one that already holds the credential.

WHY BOTH PROVIDERS EXIST
------------------------
Not for show. Claude Pro and ChatGPT are two subscriptions with INDEPENDENT
usage limits. Codex was exhausted when the Phase 09 brief was written; Phase 06
lost an evening to an exhausted Claude window. One provider means the bot is
unavailable for hours at a stretch. Two means a temporary limit is a fallback,
not an outage.

They also fail DIFFERENTLY, which is the second reason the abstraction exists:
each CLI reports exhaustion in its own words, and `Answer` turns both into one
concept the caller can act on.

THE MODEL GETS NO TOOLS. THIS IS TESTED, NOT ASSUMED
----------------------------------------------------
Both CLIs are agents. Left alone they read files and run commands -- as `aleix`,
who owns the credentials and the home directory. `/ask` must not become a way to
read the host, so tool use is disabled at the CLI and the process is given an
empty working directory to stand in.

Verified on 2026-09-09 with a canary file placed in the working directory:

    default tools : returned  CANARY-7f3a-INSIDE-CWD
    --tools ""    : "The file canary.txt does not exist ... directory is empty"

Same file, same directory, same model. The restriction is real, and the second
answer is also a reminder that a model with no tools will confabulate rather
than refuse -- which is why nothing here treats model output as fact.
"""

from __future__ import annotations

import dataclasses
import json
import os
import re
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

MAX_GATEWAY_RESPONSE_BYTES = 256 * 1024
CHAT_ENVELOPE_TOKEN_ALLOWANCE = 256


def log(msg: str) -> None:
    """
    stderr, which systemd routes to the journal.

    This exists because of a Phase 09 mistake worth keeping. The Telegram reply
    deliberately does NOT carry raw CLI output -- provider diagnostics contain
    absolute paths and the reply leaves the machine. That part was right. What
    was wrong was concluding the output should go nowhere: the first real /ask
    failed with "the provider failed in a way this helper does not recognise"
    and there was nothing anywhere to say what had actually happened.

    Suppressing something from a user-facing message is not the same decision as
    not recording it. The journal is the right place, and it is the place that
    was left empty.
    """
    print(msg, file=sys.stderr, flush=True)

# The prompt. Everything sent to a provider is built from this and nothing else.
#
# The host status block is the literal output of /status -- five figures the
# owner can already read on their phone. No logs, no file contents, no journal,
# no configuration. Widening this is a separate decision with its own risk
# assessment (ADR-025), not an implementation detail.
PROMPT = """\
You are answering a question from the owner of a small home server, sent from a \
phone over Telegram.

Answer briefly and plainly. Prefer a few sentences over a structured document.

You have NO tools. You cannot read files, run commands, or inspect the host. \
The only information you have about this machine is the status block below. If \
the answer depends on something not shown there, say so plainly instead of \
guessing.

Host status:
{context}

Question:
{question}
"""


@dataclasses.dataclass(frozen=True)
class Answer:
    """
    One shape for every outcome, so the caller never parses CLI output.

    kind is "" on success, otherwise:
      "exhausted" -- the subscription's usage limit is spent. A NORMAL state,
                     not an error: the caller should try the other provider.
      "error"     -- anything else, including a timeout or an unparseable run.

    `detail` is safe to show the owner. Raw CLI output is NOT put here; it goes
    to the journal. Provider output can contain paths, and the reply goes to
    Telegram.
    """
    ok: bool
    text: str = ""
    kind: str = ""
    detail: str = ""
    retry_hint: str = ""
    provider: str = ""
    model: str = ""
    usage: dict | None = None
    gateway_cost: str | None = None
    charge_uncertain: bool = False


# Phrases that mean "your allowance is spent" rather than "something broke".
#
# BOTH of these are real, captured from genuinely exhausted subscriptions rather
# than imagined:
#
#   Codex,  while the Phase 09 brief was written:
#     ERROR: You've hit your usage limit ... try again at 8:55 PM
#   Claude, on the very first real /ask of this phase:
#     You've hit your session limit · resets 11pm (UTC)
#
# The first version of this pattern was written from the Codex text plus
# guesses, and it did not match Claude's wording -- "session limit", which none
# of the guesses covered. So the first real /ask reported "the provider failed
# in a way this helper does not recognise" about an entirely normal condition,
# and never fell back to the other provider.
#
# The lesson is the one this project keeps relearning in new clothing: a branch
# that has only ever been exercised against invented input is untested. The
# guessed half was wrong and the observed half was right.
#
# Anything still unrecognised falls through to "error", which remains the honest
# answer for output we cannot read -- and it is now logged, so the next
# unrecognised phrasing arrives with its evidence attached.
_EXHAUSTED = re.compile(
    r"(?:usage|session|weekly|daily|hourly|rate)\s+limit"
    r"|limit\s+(?:reached|exceeded)"
    r"|quota\s+exceeded"
    r"|too\s+many\s+requests"
    r"|\b429\b",
    re.IGNORECASE,
)

# Both observed shapes, and note that only one of them uses the word "at":
#   "try again at 8:55 PM"      -> 8:55 PM
#   "resets 11pm (UTC)"         -> 11pm (UTC)
# The capture stops at a comma, newline or the middle dot Claude uses as a
# separator, so it cannot run on and swallow the rest of a message.
_RETRY_AT = re.compile(
    r"(?:try\s+again\s+at|resets?(?:\s+at)?)\s+([0-9][^,\n\u00b7]{0,39})",
    re.IGNORECASE,
)


def _classify(blob: str, provider: str, model: str, code: int = -1) -> Answer:
    """Turn a failed run's output into an Answer. Shared by both providers."""
    # Logged before classification, so an unrecognised failure is still
    # recoverable from the journal. Truncated: a CLI can produce a great deal
    # of output and journald is not free on this node.
    log(f"{provider}/{model} failed exit={code} output[:1200]={blob[:1200]!r}")

    if _EXHAUSTED.search(blob):
        m = _RETRY_AT.search(blob)
        return Answer(ok=False, kind="exhausted", provider=provider, model=model,
                      retry_hint=m.group(1).strip() if m else "",
                      detail="usage limit reached")
    # Deliberately does NOT echo the CLI output. Unrecognised failure is
    # reported as unrecognised -- a plausible-looking guess would be worse.
    return Answer(ok=False, kind="error", provider=provider, model=model,
                  detail="the provider failed in a way this helper does not recognise")


class Provider:
    """
    Base class. Subclasses build argv and read the answer back.

    `model` is the registry model's `id` -- the vendor string the CLI receives
    (Phase 15.0). It arrives from helper.build_provider(), which read it from
    root-owned config; nothing on the wire can reach this argument.
    """

    name = ""

    @classmethod
    def validate_entry(cls, name: str, entry: dict) -> None:
        if not entry.get("bin") or not os.path.isabs(str(entry["bin"])):
            raise ValueError(f"config: providers.{name}.bin must be an absolute path")

    def __init__(self, entry: dict, model: dict, timeout: int) -> None:
        self.binary = entry["bin"]
        self.model = model["id"]
        self.timeout = timeout

    def ask(self, question: str, context: str) -> Answer:
        raise NotImplementedError

    def input_token_bound(self, question: str, context: str) -> int:
        return 0

    def _run(self, argv: list[str], cwd: str) -> tuple[int, str]:
        """
        Run the CLI with stdin closed and a bounded lifetime.

        stdin=DEVNULL is not tidiness. `codex exec` reads stdin and APPENDS it to
        the prompt -- with a pipe attached it prints "Reading additional input
        from stdin..." and waits. A service with an open stdin would hang.
        """
        proc = subprocess.run(
            argv,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=self.timeout,
            text=True,
        )
        return proc.returncode, proc.stdout


class ClaudeProvider(Provider):
    """
    Claude Code in print mode.

    --tools ""          disables every built-in tool (verified, see header).
    --strict-mcp-config ignores any MCP server configured for the user, so the
                        service's behaviour does not change because the owner
                        installed something in their own account.
    """

    name = "claude"

    def ask(self, question: str, context: str) -> Answer:
        prompt = PROMPT.format(context=context, question=question)
        with tempfile.TemporaryDirectory(prefix="homelab-ask-") as workdir:
            argv = [
                self.binary,
                "-p",
                "--model", self.model,
                "--tools", "",
                "--strict-mcp-config",
                prompt,
            ]
            try:
                code, out = self._run(argv, workdir)
            except subprocess.TimeoutExpired:
                log(f"{self.name}/{self.model} timed out after {self.timeout}s")
                return Answer(ok=False, kind="error", provider=self.name,
                              model=self.model,
                              detail=f"no reply within {self.timeout}s")

        text = out.strip()
        if code == 0 and text and not _EXHAUSTED.search(text):
            return Answer(ok=True, text=text, provider=self.name, model=self.model)
        return _classify(text, self.name, self.model, code)


class CodexProvider(Provider):
    """
    Codex in non-interactive exec mode.

    Every flag here was forced by something observed on 2026-09-09:

      --skip-git-repo-check  codex refuses to run outside a trusted git
                             directory: "Not inside a trusted directory and
                             --skip-git-repo-check was not specified."
      --sandbox read-only    the model's shell tool cannot write. Combined with
                             an empty working directory there is nothing to read
                             either.
      --ephemeral            no session files written to ~/.codex. A service
                             should not accumulate transcripts of the owner's
                             questions on a node with no backup and no
                             encryption.
      -o FILE                the final message, alone, in a file. The alternative
                             is scraping a banner that prints the model name,
                             session id and token count -- parsing that would be
                             a bug waiting to happen.
    """

    name = "codex"

    def ask(self, question: str, context: str) -> Answer:
        prompt = PROMPT.format(context=context, question=question)
        with tempfile.TemporaryDirectory(prefix="homelab-ask-") as workdir:
            last = f"{workdir}/last-message.txt"
            argv = [
                self.binary, "exec",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--ephemeral",
                "-C", workdir,
                "-m", self.model,
                "-o", last,
                prompt,
            ]
            try:
                code, out = self._run(argv, workdir)
            except subprocess.TimeoutExpired:
                log(f"{self.name}/{self.model} timed out after {self.timeout}s")
                return Answer(ok=False, kind="error", provider=self.name,
                              model=self.model,
                              detail=f"no reply within {self.timeout}s")

            text = ""
            try:
                with open(last, encoding="utf-8") as fh:
                    text = fh.read().strip()
            except FileNotFoundError:
                # codex writes this file only on success. Its absence IS the
                # failure signal, and a more reliable one than the exit status.
                pass

        if code == 0 and text:
            return Answer(ok=True, text=text, provider=self.name, model=self.model)
        return _classify(out, self.name, self.model, code)


class GatewayProvider(Provider):
    """Vercel AI Gateway's OpenAI-compatible Chat Completions surface.

    The credential name comes from root-owned configuration.  The value comes
    only from systemd's credential tmpfs; there is no environment-variable or
    file-path fallback.  Neither the credential nor urllib's request object is
    logged, because both carry the bearer header.
    """

    name = "gateway"

    @classmethod
    def validate_entry(cls, name: str, entry: dict) -> None:
        endpoint = entry.get("endpoint")
        if not isinstance(endpoint, str):
            raise ValueError(f"config: providers.{name}.endpoint must be a URL")
        parsed = urllib.parse.urlparse(endpoint)
        local_http = parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost", "::1")
        production_https = parsed.scheme == "https" \
            and parsed.hostname == "ai-gateway.vercel.sh" and parsed.port is None
        if not production_https and not local_http:
            raise ValueError(
                f"config: providers.{name}.endpoint must be the Vercel HTTPS endpoint "
                "(or loopback http for fixtures)")
        if parsed.username is not None or parsed.password is not None:
            raise ValueError(f"config: providers.{name}.endpoint must not contain credentials")
        if parsed.path != "/v1/chat/completions" or parsed.params or parsed.query or parsed.fragment:
            raise ValueError(f"config: providers.{name}.endpoint must end exactly /v1/chat/completions")
        credential = entry.get("credential")
        if not isinstance(credential, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,31}", credential):
            raise ValueError(f"config: providers.{name}.credential must be a credential name")

    def __init__(self, entry: dict, model: dict, timeout: int) -> None:
        self.model = model["id"]
        self.vendor = self.model.split("/", 1)[0]
        self.timeout = timeout
        self.endpoint = entry["endpoint"]
        self.max_output_tokens = model["max_output_tokens"]
        self.reasoning = model.get("reasoning")
        cred_dir = os.environ.get("CREDENTIALS_DIRECTORY")
        if not cred_dir:
            raise ValueError("gateway credential unavailable: CREDENTIALS_DIRECTORY is not set")
        path = os.path.join(cred_dir, entry["credential"])
        try:
            with open(path, encoding="utf-8") as fh:
                self._key = fh.read().strip()
        except OSError as exc:
            raise ValueError("gateway credential unavailable or unreadable") from exc
        if not self._key:
            raise ValueError("gateway credential is empty")

    @staticmethod
    def _usage(value) -> dict | None:
        if not isinstance(value, dict):
            return None
        details = value.get("prompt_tokens_details")
        details = details if isinstance(details, dict) else {}
        raw = {
            "input": value.get("prompt_tokens"),
            "output": value.get("completion_tokens"),
            "cache_read": details.get("cached_tokens", 0),
            "cache_write": value.get("cache_creation_input_tokens", 0),
        }
        if any(isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in raw.values()):
            return None
        return raw

    def input_token_bound(self, question: str, context: str) -> int:
        # One UTF-8 byte per token is deliberately conservative for text and
        # includes the exact labels sent in the sole message. The API's prompt
        # count also includes a provider-created chat envelope that is not in
        # the content string, so reserve a deliberately generous fixed margin.
        content_bytes = len(f"Context:\n{context}\n\nQuestion:\n{question}".encode("utf-8"))
        return content_bytes + CHAT_ENVELOPE_TOKEN_ALLOWANCE

    def ask(self, question: str, context: str) -> Answer:
        content = f"Context:\n{context}\n\nQuestion:\n{question}"
        body = {
            "model": self.model,
            "messages": [{"role": "user", "content": content}],
            "max_tokens": self.max_output_tokens,
            # The creator prefix in the model id is not a serving-provider
            # pin. Vercel dynamically routes by default, so enforce the
            # approved egress destination on every request (brief §6.5).
            "providerOptions": {"gateway": {"only": [self.vendor]}},
        }
        if self.reasoning not in (None, "none", "provider-default"):
            body["reasoning"] = {"effort": self.reasoning}
        request = urllib.request.Request(
            self.endpoint,
            data=json.dumps(body, separators=(",", ":")).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self._key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            context_obj = ssl.create_default_context() if self.endpoint.startswith("https://") else None
            with urllib.request.urlopen(request, timeout=self.timeout, context=context_obj) as response:
                raw = response.read(MAX_GATEWAY_RESPONSE_BYTES + 1)
                if len(raw) > MAX_GATEWAY_RESPONSE_BYTES:
                    return Answer(ok=False, kind="error", provider=self.name, model=self.model,
                                  detail="gateway response was too large", charge_uncertain=True)
                payload = json.loads(raw)
        except urllib.error.HTTPError as exc:
            # Do not read or log the body: an upstream could echo request data.
            if exc.code == 429:
                return Answer(ok=False, kind="exhausted", provider=self.name,
                              model=self.model, detail="gateway rate limit reached")
            if exc.code == 401:
                return Answer(ok=False, kind="provider_error", provider=self.name,
                              model=self.model, detail="gateway authentication refused")
            # Only the documented refusal states above are safe to release.
            # A server/proxy error happened after the request left the node;
            # the provider may have completed billable work before failing.
            return Answer(ok=False, kind="error", provider=self.name,
                          model=self.model, detail=f"gateway HTTP {exc.code}",
                          charge_uncertain=True)
        except (TimeoutError, urllib.error.URLError, OSError) as exc:
            log(f"{self.name}/{self.model} transport failure: {type(exc).__name__}")
            return Answer(ok=False, kind="error", provider=self.name, model=self.model,
                          detail="gateway transport failed", charge_uncertain=True)
        except ValueError:
            return Answer(ok=False, kind="error", provider=self.name, model=self.model,
                          detail="gateway returned unreadable JSON", charge_uncertain=True)

        if not isinstance(payload, dict):
            return Answer(ok=False, kind="error", provider=self.name, model=self.model,
                          detail="gateway returned a malformed response", charge_uncertain=True)
        usage = self._usage(payload.get("usage"))
        gateway_cost = payload.get("usage", {}).get("cost") \
            if isinstance(payload.get("usage"), dict) else None
        try:
            text = payload["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            text = None
        if not isinstance(text, str) or not text.strip():
            return Answer(ok=False, kind="error", provider=self.name, model=self.model,
                          detail="gateway response carried no answer", usage=usage,
                          gateway_cost=str(gateway_cost) if gateway_cost is not None else None,
                          charge_uncertain=True)
        return Answer(ok=True, text=text.strip(), provider=self.name, model=self.model,
                      usage=usage,
                      gateway_cost=str(gateway_cost) if gateway_cost is not None else None)


BY_NAME = {"claude": ClaudeProvider, "codex": CodexProvider,
           "gateway": GatewayProvider}
