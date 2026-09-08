# Documentation Standard

## Guide vs project docs

### `guide/`
For someone learning/reproducing Home Lab.

Explain:

- purpose;
- concepts needed for the decision;
- reference-build choice;
- realistic alternatives;
- commands/configuration;
- validation;
- security implications;
- actual reference-build experience.

### `docs/`
For maintaining the actual system and preserving project memory.

Record:

- current architecture/state;
- decisions;
- tested versions;
- costs;
- build history;
- handovers.

Keep it concise and avoid copying the whole tutorial into operational documentation.

## Truthfulness

Do not document planned software as installed. Mark planned, tested, active, deprecated, or removed state clearly.

## Versions

Use `Tested with X` by default. Use `Requires X` only when compatibility demands it.

## Failures

Meaningful reversals should preserve the sequence: assumption -> event -> learning -> change.
