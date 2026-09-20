# lium-skill

[![skills.sh installs](https://skills.sh/b/Datura-ai/lium-skill)](https://skills.sh/Datura-ai/lium-skill)
[![Agent Skills standard](https://img.shields.io/badge/Agent%20Skills-SKILL.md-blue)](https://agentskills.io)
[![Docs MCP](https://img.shields.io/badge/MCP-docs.lium.io%2Fmcp-2ea44f)](https://docs.lium.io/developers/mcp)
[![CLI on PyPI](https://img.shields.io/pypi/v/lium.io?label=lium%20CLI%20on%20PyPI)](https://pypi.org/project/lium.io/)

The `lium` agent skill — teaches an AI coding agent to rent GPUs and manage pods
on [Lium (lium.io)](https://lium.io), agent-first compute: a decentralized GPU rental marketplace on Bittensor Subnet 51.

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

## Where the skill is listed

- [skills.sh](https://skills.sh/Datura-ai/lium-skill) — the Agent Skills directory; the badge above is its install count
- The docs MCP endpoint `llms.txt` names, `https://docs.lium.io/mcp` (tools `search`, `read_page`), is described at https://docs.lium.io/developers/mcp

## Links

- Docs: https://docs.lium.io
- CLI: https://github.com/Datura-ai/lium
- PyPI: https://pypi.org/project/lium.io/
- Live GPU prices (no account): https://lium.io/pricing · https://lium.io/pricing.json
