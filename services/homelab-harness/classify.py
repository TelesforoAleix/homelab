"""
Layer 2 — Understanding. Phase 23.0.

WHAT THIS IS
------------
A deterministic classifier with a closed taxonomy of four classes:

    question        one bounded ask, one answer   -> the only class served in 23.0
    task            needs decomposition or tools  -> refused: needs_decomposition
    command         an operational verb the bot already owns -> refused: not_a_request
    unclassifiable  none of the above matched     -> refused: unclassifiable

Every request gets exactly one class. There is no model call here: the target
architecture allows one but says it must be the smallest spend, and there is no
governor yet to bound it (brief §6.4). So the rules below are the whole of
layer 2, and a reader must be able to predict the class of a request by hand
from the table in README.md -- that table and this file are the same rules.

WHAT THIS IS NOT
----------------
Not a security control. It refuses classes this sub-phase cannot serve; it does
not sanitise. A `question` containing a tool-shaped string reaches the model as
text and comes back as text (brief §9). The rules are a short list a determined
client can steer around; that is recorded as an open risk, not hidden.

THE ORDER IS THE DESIGN
-----------------------
Structural signals for `command` and `task` are checked BEFORE the client's
declared kind is honoured. The declaration is data the client asserts about its
own request (ADR-034 §11: an agent's statement about its work is data, not an
instruction), so it can resolve the ambiguous residue -- turn `unclassifiable`
into `question` -- but it cannot turn a request that names tools or reads as a
list of steps into a `question`. A client that wants its work done cannot get it
by relabelling it.
"""

from __future__ import annotations

import re

CLASSES = ("question", "task", "command", "unclassifiable")

# What a client may DECLARE. `unclassifiable` is a verdict, never a declaration.
DECLARABLE_KINDS = ("question", "task", "command")

# Rule C2: the bot's command shape -- a slash, a word, optional arguments.
COMMAND_RE = re.compile(r"^/[a-z][a-z0-9_-]*(\s|$)")

# Rule T3: a leading imperative that names work rather than an answer. Short by
# design; every entry is a verb whose object is normally a thing to change.
# "explain", "describe", "summarise" are deliberately absent -- they ask for an
# answer, not for work.
IMPERATIVE_VERBS = frozenset({
    "implement", "refactor", "fix", "deploy", "install", "migrate", "commit",
    "push", "merge", "delete", "remove", "rename", "create", "build", "edit",
    "modify", "configure", "run", "execute", "write", "add", "update", "rewrite",
})

# Rule T4: two or more lines that look like enumerated or bulleted steps.
STEP_LINE_RE = re.compile(r"^\s*(?:\d+[.)]|[-*•])\s+\S")

# Rule Q1: a leading word that asks. Lower-cased first token, punctuation stripped.
QUESTION_WORDS = frozenset({
    "what", "why", "how", "when", "where", "who", "whom", "whose", "which",
    "is", "are", "was", "were", "does", "do", "did", "can", "could", "should",
    "would", "will", "explain", "describe", "summarise", "summarize", "compare",
    "define", "tell", "list", "translate",
})

_WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")


def _first_word(text: str) -> str:
    m = _WORD_RE.search(text)
    return m.group(0).lower() if m else ""


def classify(question: str, *, kind_declared: str | None,
             capabilities: tuple[str, ...] | list[str] = ()) -> tuple[str, str]:
    """
    Returns (class, rule) where `rule` is the identifier of the first rule that
    matched, so the audit line and the fixture can say WHY a class was chosen
    without quoting the request. `question` is the request text after strip();
    the caller has already refused an empty one.

    Rules, in order (README.md carries the same table with worked examples):

      C1  kind_declared == "command"                          -> command
      C2  text matches /<word> at the start                   -> command
      T1  kind_declared == "task"                             -> task
      T2  capabilities is non-empty                           -> task
      T3  first word is an imperative from IMPERATIVE_VERBS   -> task
      T4  two or more step-shaped lines (1. / 2. / - / *)     -> task
      Q0  kind_declared == "question"                         -> question
      Q1  first word is in QUESTION_WORDS                     -> question
      Q2  text ends with "?"                                  -> question
      U   nothing matched                                     -> unclassifiable
    """
    text = question.strip()
    first = _first_word(text)

    if kind_declared == "command":
        return "command", "C1"
    if COMMAND_RE.match(text):
        return "command", "C2"

    if kind_declared == "task":
        return "task", "T1"
    if capabilities:
        return "task", "T2"
    if first in IMPERATIVE_VERBS:
        return "task", "T3"
    if sum(1 for line in text.splitlines() if STEP_LINE_RE.match(line)) >= 2:
        return "task", "T4"

    if kind_declared == "question":
        return "question", "Q0"
    if first in QUESTION_WORDS:
        return "question", "Q1"
    if text.endswith("?"):
        return "question", "Q2"

    return "unclassifiable", "U"


# The refusal each unserved class produces. `question` is served; it has none.
REFUSAL_FOR_CLASS = {
    "task": "needs_decomposition",
    "command": "not_a_request",
    "unclassifiable": "unclassifiable",
}
