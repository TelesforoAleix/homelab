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

The repository name, owner, visibility details, and license have not been fixed by Project Planning. Do not invent these decisions.

Once the GitHub repository exists, add it as the remote and push `main` using the instructions GitHub provides for the repository you created.

## 5. Before Phase 01

Update any known hardware inspection details and complete the Phase 00 build log. Then Project Planning should create the dedicated Phase 01 handover/brief for Ubuntu Server.
