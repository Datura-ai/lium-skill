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

The installer takes `--claude-only`, `--cursor-only`, `--codex-only` and
`--force`; pin a version with `LIUM_SKILL_VERSION=v0.1.0`.

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
| `agents/install.sh` | Source of `lium.io/agents/install.sh` |
| `llms.txt` | Short discovery index for agents |
| `llms-full.txt` | Self-contained reference, generated from the files above |

## Editing

`llms-full.txt` is generated. After changing `lium/SKILL.md` or anything under
`lium/references/`, regenerate and commit it in the same change — CI fails the
PR on drift:

```bash
./scripts/build-llms-full.sh
```

## Links

- Docs: https://docs.lium.io
- CLI: https://github.com/Datura-ai/lium
- PyPI: https://pypi.org/project/lium.io/
