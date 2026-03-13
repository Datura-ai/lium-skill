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

## Agent-Specific: Non-Interactive Usage

**CRITICAL**: Many lium commands are interactive by default. As an agent, always pass all parameters explicitly to avoid interactive prompts.

### Check Installation & Version

```bash
# Check if installed (check PATH + common locations)
command -v lium >/dev/null 2>&1 \
  || [ -x "$HOME/.local/bin/lium" ] \
  || [ -x "/usr/local/bin/lium" ] \
  && echo "installed" || echo "not installed"

# Ensure ~/.local/bin is in PATH (where uv installs tools)
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Check installed vs latest version
pip index versions lium.io 2>/dev/null | head -3
# Example output:
#   lium.io (0.0.5)                    ← latest
#   Available versions: 0.0.5, 0.0.4, 0.0.3
#     INSTALLED: 0.0.1                 ← needs upgrade if different from latest
```

### Install or Upgrade

Preferred method — `uv tool install` (isolated env, no conflicts):

```bash
# Install uv if not present
command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Install lium (first time)
uv tool install lium.io

# Upgrade to latest
uv tool upgrade lium.io
```

Alternative — pip:

```bash
pip install --upgrade lium.io
```

### Non-Interactive Setup (instead of `lium init`)

`lium init` is fully interactive — do NOT use it from an agent. Instead, configure directly:

```bash
# Option 1: Write config file directly
mkdir -p ~/.lium
cat > ~/.lium/config.ini << 'EOF'
[api]
api_key = YOUR_API_KEY

[ssh]
key_path = /path/to/ssh/private/key
EOF

# Option 2: Use lium config set
lium config set api.api_key YOUR_API_KEY
lium config set ssh.key_path ~/.ssh/id_ed25519

# Option 3: Environment variable (session only)
export LIUM_API_KEY=YOUR_API_KEY
```

The user must register at https://lium.io and get an API key from Account Settings. Ask the user for their API key if not configured.

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
lium ls              # all available GPUs (shows table with ★ for best price/perf)
lium ls H100         # filter by type
lium ls --format json          # machine-parseable output
lium templates                 # list Docker templates
lium templates pytorch         # search templates
```

### Pod Lifecycle

```bash
lium up --gpu H100 -y          # create pod
lium ps                        # list active pods
lium ps --format json          # machine-parseable
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
lium ps --format json
```

## End-to-End Agent Workflow

Complete flow for setting up and renting a GPU pod:

```bash
# 1. Check/install/upgrade lium
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v lium >/dev/null 2>&1; then
  command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
  uv tool install lium.io
else
  uv tool upgrade lium.io 2>/dev/null || pip install --upgrade lium.io
fi

# 2. Configure (ask user for API key if needed)
lium config set api.api_key "$API_KEY"
lium config set ssh.key_path ~/.ssh/id_ed25519

# 3. Verify
lium ls >/dev/null 2>&1 && echo "OK" || echo "Auth failed"

# 4. Find suitable GPU
lium ls H100 --format json

# 5. Create pod (non-interactive!)
lium up --gpu H100 --name work-pod --ttl 6h -y

# 6. Wait and verify
lium ps --format json

# 7. Use the pod
lium scp work-pod ./code.py
lium exec work-pod "python /root/code.py"

# 8. Cleanup
echo "y" | lium rm work-pod
```

## Detailed References

- **Full CLI command reference**: See [references/cli-commands.md](references/cli-commands.md) for all commands, flags, volumes, backups, scheduling, port-forward, etc.
- **Python SDK reference**: See [references/sdk-reference.md](references/sdk-reference.md) for programmatic access — `lium.sdk.Lium`, `lium.Client`, `@machine` decorator, async patterns.
