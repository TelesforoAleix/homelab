# Repository Bootstrap Instructions

This package is intentionally shipped without a `.git/` directory. Initialize Git locally so your repository history begins on your machine.

## 1. Open in VS Code

Open the `homelab-bootstrap` directory as a folder/workspace and review:

1. `README.md`
2. `PROJECT.md`
3. `ROADMAP.md`
4. `AGENTS.md`
5. `docs/reference/project-state.md`

## 2. Rename the folder if desired

Recommended repository name:

```text
homelab
```

## 3. Initialize Git

```bash
git init
git branch -M main
git add .
git commit -m "chore: bootstrap Home Lab repository"
```

## 4. Create the public GitHub repository

The repository name, owner, visibility details, and license have not been fixed by the owner. Do not invent these decisions.

Once the GitHub repository exists, add it as the remote and push `main` using the instructions GitHub provides for the repository you created.

## 5. Status

**Phase 00 and Phase 01 are complete** (2026-09-08). This file describes the original bootstrap and
is retained as history; it is not a current task list.

Governance has since changed: phases are self-contained and sequential, and each phase writes its own
brief before implementation. See [ADR-017](docs/decisions/ADR-017-self-contained-sequential-phases.md)
and `PROJECT.md` §13. For current state, read `docs/reference/project-state.md`.
