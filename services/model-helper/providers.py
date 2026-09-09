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
import re
import subprocess
import sys
import tempfile


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
    """Base class. Subclasses build argv and read the answer back."""

    name = ""

    def __init__(self, binary: str, model: str, timeout: int) -> None:
        self.binary = binary
        self.model = model
        self.timeout = timeout

    def ask(self, question: str, context: str) -> Answer:
        raise NotImplementedError

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


BY_NAME = {"claude": ClaudeProvider, "codex": CodexProvider}
