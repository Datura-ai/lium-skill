# lium-skill

The `lium` agent skill — teaches an AI coding agent to rent GPUs and manage pods
on [Lium](https://lium.io), a decentralized GPU rental platform on Bittensor.

## Install

```bash
npx skills add Datura-ai/lium-skill --skill lium
```

Works in any agent that supports the [Agent Skills](https://agentskills.io)
standard — Claude Code, Cursor, Codex and others.

Without node, install into the agent skill directories directly:

```bash
curl -fsSL https://lium.io/agents/install.sh | bash
```

The installer writes `SKILL.md` and `references/` into `~/.claude/skills/lium/`,
`~/.cursor/skills/lium/` and `~/.codex/skills/lium/`; it takes `--claude-only`,
`--cursor-only`, `--codex-only`, `--force` (overwrite without a backup) and
`-h`. `LIUM_SKILL_VERSION` is the git ref the files are fetched from (default
`main`); the repository has no tags yet, so pin a commit sha until one exists.

The skill drives the `lium` CLI, so install that too:

```bash
curl -fsSL https://lium.io/install.sh | bash
lium init
```

## What is in here

| Path | Purpose |
|------|---------|
| `lium/SKILL.md` | The skill itself — frontmatter plus agent instructions |
| `lium/references/` | CLI and SDK references, loaded on demand |
| `agents/install.sh` | Source of `lium.io/agents/install.sh` (lium.io redirects to the raw file on `main`) |
| `llms.txt` | Short discovery index for agents |
| `llms-full.txt` | Self-contained reference, generated from the files above |
| `scripts/build-llms-full.sh` | Generates `llms-full.txt` (SKILL.md without frontmatter + both references) |
| `.github/CODEOWNERS`, `.github/REVIEWING.md` | Who reviews each path and how |

`lium.io/llms.txt` and `lium.io/llms-full.txt` are served from this repo's `main`.

## Editing

`llms-full.txt` is generated. After changing `lium/SKILL.md` or anything under
`lium/references/`, regenerate and commit it in the same change — the
`check-drift` job (`.github/workflows/check-llms-full.yml`, the only CI here)
regenerates the file on every PR, push to `main` and merge-queue run and fails
on any difference:

```bash
./scripts/build-llms-full.sh
```

## Links

- Docs: https://docs.lium.io
- CLI: https://github.com/Datura-ai/lium
- PyPI: https://pypi.org/project/lium.io/
