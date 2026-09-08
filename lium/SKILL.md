---
name: lium
description: GPU pod management on Lium platform via CLI and Python SDK. Use for creating a Lium account, renting GPUs, creating/managing pods, deploying ML workloads (LLM serving, diffusion, RL, batch jobs), transferring files to and from remote GPUs, running long jobs in the background, checking GPU utilisation and cost, verifying the GPU count of a rented pod, and programmatic compute management. Triggers on "lium", "lium.io", "lium-sdk", "create a lium account", "sign up for lium", "sign up without an email", "fingerprint", "fingerprint signup", "lium api key", "GPU rental", "rent a GPU", "GPU pod", "cloud GPU", "remote GPU", "deploy to GPU", "run on 8 GPUs", "vllm on lium", "nvidia-smi on the pod", "pull results from the pod", any lium CLI command (lium up/ls/ps/describe/ssh/exec/scp/rsync/rm/fund), lium SDK, @machine decorator.
allowed-tools: Bash(lium:*), Bash(curl:*)
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
curl -fsSL https://raw.githubusercontent.com/Datura-ai/lium/main/scripts/install.sh | bash
```

This auto-detects OS (Linux/macOS) and architecture, downloads the binary to `~/.lium/bin/lium`, and adds it to PATH.

After install, authentication depends on whether the user has a Lium account:

- **No account, and no mailbox you can read** → **fingerprint signup**: one call to `POST /auth/signup`, no email, no password, no confirmation link. This is the fully autonomous path — see "No Account Yet — Sign Up".
- **No account, but a human is there to click a confirmation link** → `lium signup --email <their email>` — same section. Do not send the user to the web signup form.
- **Has an account** → `lium init` (opens a browser) or `lium init --no-browser` for headless/agent use — see "Authentication Setup for Agents".

```bash
curl -fsS -X POST https://lium.io/api/auth/signup \
  -H 'Content-Type: application/json' -d '{}'    # no account, no mailbox
lium signup --email ada@example.com              # no account, human can confirm
lium init                                        # existing account, browser
lium init --no-browser                           # existing account, headless
```

Verify setup:

```bash
lium balance   # prints a balance -> auth works; prints an error -> it does not
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

### No Account Yet — Sign Up

`lium init` authenticates a user who **already has an account**. To create one, ask a single
question — **can anyone read the mailbox?** No: fingerprint signup, one call, fully autonomous.
Yes: `lium signup --email <their real email>`.

Only create an account when the user asks for one. Never invent an email address and never use a
disposable inbox to fake the email path — when there is no mailbox, sign up with a fingerprint.

#### Fingerprint Signup — No Email, Fully Autonomous

A **fingerprint** here is a 32-character random string Lium mints as the account credential — not
a passkey, not WebAuthn, not biometrics, not a device fingerprint. Nothing is scanned. One HTTP
call completes the signup, so "I cannot sign up without a human" is wrong.

```bash
# empty body — Lium names the account itself (lium_a1b2c3)
curl -fsS -X POST https://lium.io/api/auth/signup \
  -H 'Content-Type: application/json' -d '{}'
# {"user_id":"...","username":"lium_a1b2c3","fingerprint":"<32 chars>",
#  "api_key":"sk_...","signup_credit_granted":true|false}

# when api_key is a string, store it and continue — no confirmation step in between
lium config set api.api_key sk_...
lium ls
```

- `api_key` can be `null` — minting it is allowed to fail without failing the signup. When it is
  `null`, stop before configuring the CLI: sign in with the fingerprint and mint a key on the
  dashboard.
- `fingerprint` is the **dashboard login** at https://lium.io/login and the **only** recovery path
  — Lium stores just a hash. It is returned **exactly once** and nobody, support included, can
  look it up. Hand it to the user for their password manager, and treat it like a password:
  never paste it into a pod, a log, a commit or a ticket. Workloads use the API key instead.
- `signup_credit_granted` says whether the credit landed — do not promise $5 before reading it.
  It is `false` when the platform has the credit off, and when this IP already signed up once.

Send `{}`. The optional `username` is a display name only — it is not part of the login, the
web form never asks for one, and requesting a taken name fails with `409`. Rate limit per IP:
5/min, 20/day. There is no CLI flag yet — `lium signup` is the email path only. Full walkthrough:
https://docs.lium.io/pod-users/fingerprint-signup

#### Email Signup — `lium signup`

When a human can confirm the address, `lium signup` does the whole cold start — no browser, no
dashboard, no web form:

```bash
lium signup --email ada@example.com   # creates the account, stores the API key
lium ls                               # browse machines
lium up <node-id> -y                  # rent
lium ssh <pod>                        # connect
```

Ask for their **real email** first — the account, its balance and password recovery are tied to
it, and the confirmation link is sent there.

`lium signup` prints the generated password — hand it to the user, it is their dashboard login
(to choose one instead, pass `--password` or set `LIUM_SIGNUP_PASSWORD`, which keeps it off argv).
Even when the command fails after the account was created — a timeout, or the API key could not
be read back — the error still reports the email and password, so the account is never stranded.
Add `--json` for a machine-readable
`{email, password, api_key, signup_credit_granted, ssh_key_configured, next_steps}`.
The key is written to `~/.lium/config.ini`, so the account is then indistinguishable from one
set up with `lium init`.

Older binaries do not have the command. Probe for it, and update when it is missing:

```bash
lium --version                        # diagnostics only — probe the command itself below
lium signup --help >/dev/null 2>&1 || echo "CLI too old — update it"

# Binary install (installed via install.sh): auto-updates on launch, or force it
curl -fsSL https://lium.io/install.sh | bash

# pip / uv install
uv tool upgrade lium.io    # or: pip install -U lium.io
```

On an older CLI that cannot be updated, the same signup is three HTTP calls:

```bash
BASE=https://lium.io/api

# No mailbox to confirm? Use the fingerprint signup above instead of steps 1-3.

# 1. Create the account. An API key named "Default" is minted server-side here; current
#    backends return it in the response — {"msg": "success", "api_key": "sk_...",
#    "signup_credit_granted": true|false} — older ones mint it without returning it.
curl -sX POST $BASE/users -H 'Content-Type: application/json' \
  -d '{"name":"Ada","email":"ada@example.com","password":"..."}'

# 2-3. Only when the response had no api_key: log in for a JWT, read the key back (format sk_...).
TOKEN=$(curl -sX POST $BASE/users/login -H 'Content-Type: application/json' \
  -d '{"email":"ada@example.com","password":"..."}' | jq -r .token)
KEY=$(curl -s $BASE/keys -H "Authorization: Bearer $TOKEN" \
  | jq -r '.[] | select(.name=="Default") | .key')

lium config set api.api_key "$KEY"
# leave ssh.key_path unset — the CLI generates and configures the key on first use,
# and setting the path to a key that does not exist yet makes it skip that
```

### Before the First Rental — Balance

`lium up` calls `POST /executors/{executor_id}/rent`, and the balance is the only gate: a fresh
account can rent as soon as it is funded, email confirmed or not. Map the error to the action:

| 403 on rent | Meaning | Action |
|---|---|---|
| `"Insufficient balance"` | The account balance is zero. | Fund the account — see "Funding options" below. |

#### Email confirmation

Confirming the address does not gate renting. It confirms the address itself, so that password
resets and account emails reach the user. Registration sends **two** mails: `"Welcome to Celium!"`
(no link in it) and `"Please confirm your email"` — only the second one carries the link. Point
the user at that subject, and ask them to click the link. That is the normal path.

Two endpoints on `https://lium.io/api` cover the cases where it does not work. Neither needs
auth; both take JSON:

```bash
# Mail never arrived / link expired (tokens are valid 24h) — send a fresh one
curl -sX POST https://lium.io/api/auth/resend-verify-email \
  -H 'Content-Type: application/json' -d '{"email":"ada@example.com"}'
# 400 "User doesn't exist." or "Email is already verified." when it does not apply

# User pastes the link instead of clicking it — finish verification from its ?token=
curl -sX POST https://lium.io/api/auth/verify-email \
  -H 'Content-Type: application/json' -d '{"token":"<token from the link>"}'
```

#### The $5 signup credit

The signup credit is $5 when the platform has it enabled **and** no other account has signed up
from this IP address — nothing about the email domain matters. Do not explain a `403 "Insufficient
balance"` with the credit: that error only says the balance is zero, and the answer to it is to
fund the account.

Whether it landed is answered by `signup_credit_granted` in the signup response (also in
`lium signup --json`): `true` → granted, `false` → not granted. When it is `null` or absent —
the backend does not report it — read the balance:

```bash
lium balance --json   # {"balance_usd": 5.0}
```

#### Funding options

- Dashboard: https://lium.io/billing
- Headless invoice: `POST /tmc-pay/create-invoice` with header `X-API-Key: sk_...` and a body of
  `{"amount": <USD>, "crypto_currency": "...", "crypto_network": "..."}` (all three required).
  Valid currency/network pairs come from `GET /tmc-pay/currencies` (same API key header). The
  response carries `deposit_address`, `crypto_amount`, `hosted_invoice_url` and `expires_at` —
  give these to the user to pay from their wallet, do not move funds on their behalf.

  ```bash
  # {"currencies": [{"code": "USDT", "network": "tron", ...}, ...]} — pick a pair from here
  curl -s https://lium.io/api/tmc-pay/currencies -H "X-API-Key: sk_..."

  curl -sX POST https://lium.io/api/tmc-pay/create-invoice -H "X-API-Key: sk_..." \
    -H 'Content-Type: application/json' \
    -d '{"amount": 20, "crypto_currency": "USDT", "crypto_network": "tron"}'
  ```

- `lium fund -w default -a 10.0 -y` for users with a Bittensor wallet — here `-a` is an amount of
  **TAO**, not dollars. `-a` means USD only on the `--alpha` path, which moves Subnet-51 alpha the
  user already has staked: `lium fund --alpha -k <hotkey-ss58> -a 10 -y`.

SSH keys need no extra registration — the public key at `ssh.key_path` is registered
server-side right before renting.

### Authentication Setup for Agents

For a user who already has an account (skip if you just ran the signup flow above and stored the key).

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
lium balance       # prints a balance -> auth works; an error -> it does not
```

Do not run `lium config show` (or `lium config get api.api_key`) to check the setup: both
print the API key in full, and anything an agent prints ends up in its transcript and logs.
`lium balance` proves the key works without ever showing it. If you must confirm where the key
is stored, check that `~/.lium/config.ini` exists.

### Non-Interactive Pod Creation

Always use `-y` flag and pass all parameters. Add `--no-ssh` too: without it a
successful `lium up` ends by opening an interactive SSH session, which stalls an
agent (`--image` mode streams container logs instead).

```bash
# WRONG (interactive):
lium up              # one confirmation prompt before renting
lium up 1            # same — the prompt is the acquire confirmation

# RIGHT (non-interactive):
lium up --gpu H100 -y --no-ssh                        # auto-selects node + default template
lium up --gpu A100 -c 2 --country US -y --no-ssh      # with filters
lium up --gpu H100 --name my-pod --ttl 6h -y --no-ssh # with name and auto-termination
lium up --gpu A6000 --image pytorch/pytorch:2.0 -y    # custom docker image (streams logs)
lium up --gpu H100 --jupyter -y --no-ssh              # with Jupyter
lium up --gpu H100 -c 8 --name train --ttl 6h --verify-gpus --strict-gpus -y --no-ssh
                                                      # checks billed + nvidia-smi GPU counts; removes the pod on a mismatch
```

Rent by spec, not by id: `lium up --gpu <type> [-c N] [--country CC]` (and, since 0.0.39 (lium#209), `Lium.rent(gpu_type=, gpu_count=, min_cpus=, min_vram_gb=, max_price_per_gpu_hour=, …)` in the SDK) **picks a matching node and rents it in one call**. The backend route that picks the cheapest is live (`GET /version` lists `rent_by_spec`); since 0.0.39 (lium#209) `lium up --gpu` and `Lium.rent` use it; 0.0.37/0.0.38 do not call it and pick locally (the first Pareto-optimal row of `ls()`, not the cheapest). Do not `lium ls` first and rent the first row yourself: it is neither the cheapest nor guaranteed still free. On a 0.0.37/0.0.38 SDK, which has no `rent()`, `ls()` + `up(executor_id=)` is the only path — pick by `price_per_hour`, not the first row (example in `references/sdk-reference.md`).

`lium up` exits 0 only when the pod is running (and, with `--verify-gpus`, when
the GPU counts agree). It exits 1 **with the pod still running and billing** when
its `--timeout` (default 900 s) runs out while the pod is starting
(`pod_not_ready`) or when the GPU count is wrong and `--strict-gpus` was not
given (`gpu_count_mismatch`). After any non-zero exit: `lium ps <name> --format
json`, and `lium rm <name> -y` if a pod is listed.

### Before You Rent 8 GPUs — Check Interconnect and Ingress First

A multi-GPU listing does not tell you how the GPUs are wired together or how fast the
node pulls from the internet. Both decide whether a tensor-parallel / FSDP job runs at
all and how long the weights take to arrive. Check them in the first minute of the
rental, before any download or launch, and delete the pod if they are wrong.

```bash
lium exec <pod> "nvidia-smi topo -m; nvidia-smi topo -p2p r"
```

Read `topo -m`: every off-diagonal GPU cell must be `NV#` (e.g. `NV18` on H100/H200,
`NV12` on A100) for a proper HGX board. `PIX`/`PXB`/`PHB`/`NODE`/`SYS` means PCIe — several
times slower for NCCL collectives. Read `topo -p2p r`: every off-diagonal cell must be
`OK`; `NS` everywhere means peer-to-peer is disabled (seen on virtualised 8× H200 hosts),
and NCCL fails on its first all-reduce with `unhandled cuda error` / `operation not
supported`.

Decision rule for TP/FSDP jobs: all `NV#` and all `OK` → proceed. Anything else →
`lium rm <pod> -y` and pick another node. If the job must run there anyway, NCCL only works
over loopback sockets, and TP=8 serving of a large model is impractical. Each `lium exec` is
a fresh SSH session, so a bare `export` in one call is gone in the next; pass the variables
with `-e` on the call that runs the job:

```bash
lium exec <pod> -e NCCL_P2P_DISABLE=1 -e NCCL_SHM_DISABLE=1 -e NCCL_IB_DISABLE=1 -e NCCL_SOCKET_IFNAME=lo "python train.py"   # virtualised host without RDMA NICs
```

One independent process per GPU (batch inference, best-of-N generation, sweeps) does not
need the interconnect and runs at full speed on any eight cards.

Ingress: the **Download (Mbps)** column in `lium ls` is a smoothed average of the validator's
VerifyX check, which fetches a real object of known size and hash (the speed-test average is
the fallback when VerifyX has no figure; **Upload** follows the same order). It flags nodes under
100 Mbps as slow; it does not predict Hugging Face or PyPI throughput. The same
756 GB checkpoint pulled at 2.6–4 GB/s, 1.04 GB/s and 45–200 MB/s on three nodes listed in
the same few-hundred-Mbps band. Measure before committing:

```bash
lium exec <pod> "curl -o /dev/null -sS -w '%{http_code} %{speed_download}\n' 'https://speed.cloudflare.com/__down?bytes=50000000'"   # HTTP code, bytes/s (>= 100 MB is refused with 403)
lium exec <pod> "curl -L -o /dev/null -sS --max-time 20 -w '%{http_code} %{speed_download}\n' https://huggingface.co/openai-community/gpt2/resolve/main/model.safetensors"   # same for the Hugging Face CDN; -L follows the redirect, 20 s cap, nothing written to disk
```

Do the arithmetic: bytes to download ÷ measured bytes/s. At 45 MB/s a 750 GB checkpoint is
4.6 h of idle GPU billing; at 1 GB/s it is 12.5 min. Uplink varies as much (30 KB/s vs
0.5 MB/s seen) — push results from the pod to Hugging Face / S3 directly rather than through
the controlling machine. An `interconnect` field and a CDN-measured ingress/egress figure
are coming with lium-platform#61, and `lium ls` filters for NVLink and minimum ingress with
lium#149; neither is released. Until your CLI shows a **Link** column, these commands are
the check.

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

#### After `lium init --session` — Verify with `lium balance`

After completing the two-step auth, run `lium balance`. A balance means auth is done; `lium ls`
is not a check — it lists nodes with a wrong key too (see below).

#### Exit Codes Are Reliable — But `lium ls` Is Not an Auth Check

Since 0.0.31 every renter command exits non-zero on a handled error (1 general,
2 bad arguments/config, 3 API error, 4 SSH, 5 pod not found, 6 permission
denied), so `lium <cmd> && next-step` is safe. `lium exec` exits with the remote
command's own code.

`lium ls` and `lium templates` read **public endpoints**: they return real data and
exit 0 with a revoked or invalid API key (no key configured at all → exit 2).

```bash
lium ls >/dev/null && echo "auth OK"       # prints "auth OK" even with a bad key
lium balance --json >/dev/null && echo OK  # exit 3 on a bad key — use this instead
```

With `--json`, a failure is one JSON object on **stderr**
(`{"ok": false, "error": {"code": ..., "message": ...}}`) and stdout stays empty.
`ls` / `ps --format json` have no envelope: a failure prints a plain error line on
stdout — check the exit code before parsing.

#### Pod Targeting — Prefer Names

Use the pod **name** (e.g. `lunar-lion-4c`) from `lium ps` output for targeting — not a numeric index. An index is resolved against the last `lium ps` **in this shell** and refused with `stale_pod_index` when that listing is missing, older than 10 minutes, or no longer shows that pod.

#### `-y` Exists on the Destructive Commands

`lium rm`, `lium up`, `lium fund`, `lium volumes rm`, `lium bk set/rm/restore` all
take `-y, --yes`. No piped `yes` is needed:

```bash
lium rm my-pod         # will prompt for confirmation
lium rm my-pod -y      # non-interactive
lium rm -a -y          # remove all pods non-interactively
```

#### Templates

- Without `--template_id` or `--image`, `lium up` uses default **PyTorch (CUDA)** template — fastest to start
- Default Docker-in-Docker (dind) template image: `daturaai/dind`
- Search templates: `lium templates pytorch` (text search; the table has **no id
  column**; since 0.0.39 (lium#217) `lium templates --format json` / `--json` prints the ids)
- To get a template id: `curl -s https://lium.io/api/templates -H "X-API-Key: $LIUM_API_KEY" | jq -r '.[] | "\(.id) \(.docker_image):\(.docker_image_tag)"'`
  or `python -c "from lium.sdk import Lium; [print(t.id, t.docker_image, t.docker_image_tag) for t in Lium().templates('pytorch')]"`
- To use specific template: `lium up --gpu H100 -t <TEMPLATE_ID> -y`
- To use custom Docker image: `lium up --gpu H100 --image pytorch/pytorch:2.0 -y`

#### No User Identity Command

lium CLI has no renter-side identity command — no `whoami` for your API key.
(`lium provider portal whoami` exists, but it reports the *provider* portal session,
not the API key you rent with.)

To check the key, run `lium balance`: it prints a balance when the key works and
exits 3 when it does not. Do **not** use `lium ls` for this — the executor list is
public, so `lium ls && echo OK` says OK with a revoked key.

#### Long-Running Commands Over SSH

`lium exec` runs the command in the foreground and returns only when **every
process still holding its stdout/stderr** has exited — a job started with a bare
`&` keeps `exec` blocked, and a long-running `exec` can also stall when the SSH
session drops. Detach anything that runs longer than a minute (installs, model
downloads, training, servers), then poll a log file:

```bash
# Start detached: new session (setsid), immune to hangup (nohup), stdin closed, output to a file.
# (\$! is escaped for the local shell; the remote prints the background PID.)
lium exec my-pod "mkdir -p /workspace/logs && nohup setsid bash -lc 'pip install vllm' > /workspace/logs/install.log 2>&1 < /dev/null & echo PID=\$!"

# Poll — do not `tail -f` through exec, it never returns
lium exec my-pod "tail -n 20 /workspace/logs/install.log"
lium exec my-pod "kill -0 <PID> && echo running || echo finished"
```

`lium logs my-pod --follow` streams the container's PID 1 output only — it does
not show processes you started via `exec` unless they write to `/proc/1/fd/1`.
An `exec --detach` flag that does this for you is proposed (lium#211, not released).

#### PEP 668 on Default PyTorch Template

The default `daturaai/pytorch` image is based on Ubuntu 24.04 where system `pip` is PEP 668 protected (`externally-managed-environment`). Use one of:

```bash
# Option 1: venv on the fast volume (recommended — keeps torch from the image via --system-site-packages)
python3 -m venv --system-site-packages /workspace/venv && . /workspace/venv/bin/activate && pip install <pkg>

# Option 2: uv (fast; a venv under /workspace, or --system)
curl -LsSf https://astral.sh/uv/install.sh | sh && export PATH="$HOME/.local/bin:$PATH"
uv venv /workspace/venv --system-site-packages && uv pip install --python /workspace/venv/bin/python <pkg>

# Option 3: allow system-wide install (one-off)
pip install --break-system-packages <pkg>      # or: export PIP_BREAK_SYSTEM_PACKAGES=1
```

#### Missing System Tools in Base Image

The default GPU base image does not include `ffmpeg`, `rsync`, `nvcc` (the CUDA
compiler), `tesseract`, `jq`, `htop`, `tmux`, `screen`, `libnuma1`, `git-lfs`.
`apt-get` works as root; install what the job needs first:

```bash
lium exec my-pod "apt-get update -qq && apt-get install -y -qq ffmpeg rsync jq tmux git-lfs libnuma1"
```

`rsync` must be present **on the pod** for a plain `rsync` or the SDK's `Lium.rsync()`
to work; the CLI's `lium rsync` installs it first (`apt-get install -y rsync` when
`which rsync` fails on the pod). Compiling CUDA extensions (FlashAttention, custom kernels) needs
`nvcc`: check `which nvcc`, and prefer prebuilt wheels or a `-devel` image tag.

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

#### Verify HuggingFace Model Exists Before Deploy

Before spinning up a pod for a specific model (e.g. `vllm serve <repo>`), confirm the `repo_id` exists on HuggingFace — typos like `qwen3.5-4b` (doesn't exist) vs `Qwen/Qwen3-4B` waste a full cold-start cycle.

```bash
curl -s "https://huggingface.co/api/models?search=qwen+2.5+7b&limit=10" | jq -r '.[].id'
```

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

If an executor is visible on the lium.io dashboard but `lium up <node-id>` or `lium ls` doesn't show it, the platform's availability filter rejected it. Reasons include: low free disk space, high disk utilization, unresponsive health checks, or missing verification. **`lium ls` is the source of truth for rentable machines** — prefer filtering/selecting from `lium ls` output rather than matching IDs from the website.

## Agent Playbook

The loop that works unattended, from a shell with `LIUM_API_KEY` set. Every pod
gets a **name** (so it can be found again), a **TTL** (so a crashed agent does
not bill for days) and a **GPU-count check** (so you do not pay for GPUs that are
not there). Work runs **detached** and is polled; results are pulled with
`rsync`; the run ends with `rm` and a `ps` that shows nothing left.

```bash
export LIUM_API_KEY=sk_...           # non-interactive auth; beats ~/.lium/config.ini
NAME=job-$(date +%s)

# 1. Pick hardware from JSON, not from the table
lium ls --gpu H200 --count 8 --format json \
  | jq -r 'map(select(.tier=="secure")) | sort_by(.price_per_gpu_hour) | .[0] | "\(.huid) \(.config) $\(.price_per_hour)/h \(.country)"'

# 2. Rent, non-interactively, with a TTL; --no-ssh returns as soon as the pod is RUNNING
lium up --gpu H200 -c 8 --name "$NAME" --ttl 6h -y --no-ssh || exit 1

# 3. Read the pod record (up prints no JSON) and verify what you pay for
lium ps "$NAME" --format json > pod.json
BILLED=$(jq -r '.[0].gpu_count' pod.json)
SEEN=$(lium exec "$NAME" --json "nvidia-smi -L | wc -l" | jq -r '.results[0].stdout | tonumber')
[ "$SEEN" = "8" ] && [ "$BILLED" = "8" ] || { echo "GPU count mismatch: asked 8, billed $BILLED, visible $SEEN"; lium rm "$NAME" -y; exit 1; }

# 4. Prepare the pod (fast path, tools, venv) — one --script exec; stdin is NOT forwarded
cat > setup.sh <<'EOF'
set -e
mkdir -p /workspace/{logs,out,hf}
apt-get update -qq && apt-get install -y -qq rsync ffmpeg jq >/dev/null
python3 -m venv --system-site-packages /workspace/venv
. /workspace/venv/bin/activate && pip install -q "huggingface_hub[hf_transfer]"
EOF
lium exec "$NAME" --script setup.sh

# 5. Start the job detached (capture the PID from --json), then poll
lium scp "$NAME" ./train.py /workspace/train.py
PID=$(lium exec "$NAME" --json "cd /workspace && HF_HOME=/workspace/hf HF_HUB_ENABLE_HF_TRANSFER=1 nohup setsid /workspace/venv/bin/python train.py > /workspace/logs/train.log 2>&1 < /dev/null & echo \$!" | jq -r '.results[0].stdout | tonumber')
while lium exec "$NAME" "kill -0 $PID" >/dev/null 2>&1; do
  lium exec "$NAME" "tail -n 2 /workspace/logs/train.log"; sleep 60
done

# 6. Pull results (no -z for binary output; resumable), then tear down and confirm
read -r HOST PORT < <(jq -r '.[0].ssh_cmd | capture("@(?<h>\\S+).*-p (?<p>\\d+)") | "\(.h) \(.p)"' pod.json)
rsync -a --partial --inplace --info=progress2 -e "ssh -p $PORT -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
  "root@$HOST:/workspace/out/" ./out/
lium rm "$NAME" -y
lium ps --format json | jq 'length'   # 0 → nothing left billing
```

`lium exec <pod> --script setup.sh` is the safe way to run a multi-line setup: no
quoting games, and the script's exit code comes back. (`lium exec <pod> "bash -s"
< setup.sh` does **not** work — local stdin is never forwarded.) Capture remote
output with `--json | jq -r '.results[0].stdout'`; the human format prints an
`Executing on …` line on stdout first.

### Verify What You Paid For

Two failure modes were seen repeatedly on 4- and 8-GPU rentals: the platform
provisions a **1-GPU pod** when the requested count is unavailable (silent
downgrade), and a pod is **billed for N GPUs but the container exposes fewer**
(phantom GPUs). Neither shows up as an error. Check, every time, right after `up`:

```bash
lium ps "$NAME" --format json | jq '.[0] | {gpu_count, price_per_hour, config}'   # what you are billed for
lium exec "$NAME" "nvidia-smi -L"                                                # what the container sees
lium exec "$NAME" "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader"
```

If either number is below what you asked for, `lium rm` the pod immediately and
rent again (another executor: pass its HUID from `lium ls` as `NODE_ID`). Keep
the `nvidia-smi -L` output; it is the evidence for a refund. The CLI will do this
check for you with `lium up --verify-gpus` / `--strict-gpus` (upcoming, CLI > 0.0.33).

### Pod Gotchas — The First Hour

Observed on the default `daturaai/pytorch` templates (Ubuntu 24.04). Check with
`mount | grep -E ' /root | /workspace '`, `nvidia-smi`, `python -c "import torch; print(torch.__version__, torch.cuda.get_arch_list())"`.

- **Use `/workspace`, not `/root`.** The home directory is an encrypted FUSE mount
  (`gocryptfs`): model loads from it are several times slower, it pegs a CPU core
  during heavy I/O, and multi-process caches (Triton, torch.compile) misbehave on
  it. Put venvs, `HF_HOME`, datasets, checkpoints and outputs under `/workspace`.
  In the container restarts we saw, `/workspace` survived and everything else
  (running processes, `/root`, `/tmp`) did not — treat the rest as disposable.
- **Weights: `HF_HOME=/workspace/hf` + `hf_transfer`.**
  `pip install "huggingface_hub[hf_transfer]"`, then
  `export HF_HOME=/workspace/hf HF_HUB_ENABLE_HF_TRANSFER=1` before any download
  — multi-GB/s on most nodes instead of a few hundred MB/s. Gated models need
  `HF_TOKEN`. Download once, detached, before starting the GPU job.
- **PEP 668**: system `pip` refuses to install. Use a venv under `/workspace`
  (`--system-site-packages` keeps the image's torch) or `uv`; see the pitfall
  above.
- **Blackwell needs a matching torch.** B200 / B300 / RTX PRO 6000 / RTX 5090 are
  `sm_100` / `sm_103` / `sm_120`. A torch built for CUDA 12.6 has no kernels for
  them and fails on the first CUDA call (`no kernel image is available`). Pick a
  `cuda12.8` or `cuda13.0` template tag (`-t <id>`), or reinstall:
  `pip install --upgrade torch torchvision --index-url https://download.pytorch.org/whl/cu130`
  (`cu128` also works). Verify with `torch.cuda.get_arch_list()`.
- **FlashAttention-3 is Hopper-only** (H100/H200). On Blackwell use
  FlashAttention-4 (beta) or PyTorch SDPA's cuDNN/flash backends; building FA3
  there wastes 20+ minutes and then fails at runtime. Most serving stacks
  (vLLM, SGLang) pick a working backend on their own — prefer their wheels over
  building kernels. Building anything CUDA needs `nvcc`, which the base image
  does not ship (`-devel` tags do).
- **Missing tools**: `ffmpeg`, `rsync`, `nvcc`, `tesseract`, `jq`, `tmux` are not
  installed. `apt-get update && apt-get install -y ...` first — as root, no sudo.
- **`exec` blocks on background children**: start long jobs with
  `nohup setsid ... > log 2>&1 < /dev/null &` (pitfall above) and poll the log.
- **Container restarts happen.** A pod can restart without any action from you;
  GPU jobs die, `/workspace` stays. Write checkpoints to `/workspace`, make jobs
  resumable, and note `uptime` / `ps -p 1 -o etimes=` when a job vanished.
- **Ports**: only the ports in `lium ps --format json | jq '.[0].ports'` are
  reachable from outside (internal → external map). Bind servers to `0.0.0.0`
  on an internal port from that map, or use `lium port-forward`.

### Moving Data

```bash
# Upload: lium handles it (single file, or a directory with lium rsync)
lium scp "$NAME" ./config.yaml /workspace/config.yaml
lium rsync "$NAME" ./src /workspace/src

# Download a directory: plain rsync to the pod's SSH endpoint (from lium ps --format json)
rsync -a --partial --inplace --info=progress2 --bwlimit=20000 \
  -e "ssh -p $PORT -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
  "root@$HOST:/workspace/out/" ./out/
```

- `--partial --inplace` makes a dropped transfer resumable; `--bwlimit` (KB/s)
  keeps one pull from starving the rest of the job.
- No `-z` for media, checkpoints, parquet or anything already compressed.
- Throughput out of a pod varies a lot (from ~100 KB/s to multi-MB/s); when a
  big pull is slow, sync **pod to pod** to a cheap 1-GPU pod and tear the
  expensive one down, then pull from the cheap pod at leisure.

Pod-to-pod copy (source pod pushes to destination pod over SSH; both need
`rsync` installed):

```bash
SRC=render-pod; DST=edit-pod
read -r DHOST DPORT < <(lium ps "$DST" --format json | jq -r '.[0].ssh_cmd | capture("@(?<h>\\S+).*-p (?<p>\\d+)") | "\(.h) \(.p)"')
# one-time trust: a key on SRC, authorised on DST
PUB=$(lium exec "$SRC" --json "test -f ~/.ssh/id_p2p || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_p2p; cat ~/.ssh/id_p2p.pub" | jq -r '.results[0].stdout' | tr -d '\n')
lium exec "$DST" "mkdir -p ~/.ssh && grep -qxF '$PUB' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUB' >> ~/.ssh/authorized_keys"
# the copy itself (detach it like any long job when it is large)
lium exec "$SRC" "rsync -a --partial --inplace -e 'ssh -p $DPORT -i ~/.ssh/id_p2p -o StrictHostKeyChecking=no' /workspace/out/ root@$DHOST:/workspace/in/"
```

### Watch the GPUs

A pod that is quietly idle costs the same as one that is busy. Sample utilisation
into a CSV on the pod as soon as the job starts; it is also your evidence when a
job stalls or a GPU is missing.

```bash
lium exec "$NAME" "mkdir -p /workspace/logs && nohup setsid nvidia-smi --query-gpu=timestamp,index,utilization.gpu,memory.used,memory.total,power.draw --format=csv -l 60 > /workspace/logs/gpu.csv 2>&1 < /dev/null & echo \$!"
lium exec "$NAME" "tail -n 8 /workspace/logs/gpu.csv"      # one line per GPU per minute
lium exec "$NAME" "nvidia-smi --query-gpu=index,utilization.gpu,memory.used --format=csv,noheader"   # one-shot
```

Zero utilisation across all GPUs for more than a few minutes means the job is
stuck on CPU work, on I/O from `/root`, or has crashed — check the log before the
bill grows. (`lium top` for this is upcoming, CLI > 0.0.33.)

### Cost Hygiene

- **Always `--ttl`** (or `--until`). It is scheduled once the pod is RUNNING; a
  pod that never got there has no TTL — `lium ps` and `lium rm` it yourself.
  Extend a TTL with `lium rm <pod> --in 4h` (schedules a new removal) and see
  what is scheduled with `lium schedules list`.
- **Check the meter**: `lium ps --format json | jq '.[] | {name, price_per_hour, spent_usd, uptime}'`
  — `spent_usd` is uptime × price, computed client-side. Multi-GPU nodes are
  billed for the whole node from the moment `up` returns, including setup time.
- **Never keep an 8-GPU node for CPU work.** Downloads, preprocessing, video
  encoding, editing and uploads belong on the cheapest node in `lium ls`
  (`--sort price_per_hour --limit 5`) or on your own machine. Copy pod-to-pod,
  `rm` the big node, continue on the cheap one.
- **One `up` per pod name.** If `up` times out or errors after "Renting
  machine", run `lium ps` before retrying — the pod may exist (and bill) already.
  Retrying blindly has produced two pods for one request.
- **Tear down and prove it**: `lium rm "$NAME" -y && lium ps --format json | jq length`
  — expect `0` (or the count you intend to keep). `lium rm -a -y` ends everything.
- Keep the `nvidia-smi -L` and `lium ps --format json` snapshots from step 3 of
  the playbook; billing disputes need them.

### Recipes

Copy-paste jobs, each ending in a teardown, in
[references/recipes.md](references/recipes.md): vLLM / SGLang serving on 8 GPUs,
best-of-N image/video diffusion with one process per GPU, RL / simulation,
a batch data job, and the "verify what you paid for" check as a script.

### Upcoming (CLI > 0.0.33) — Do Not Use Yet

These are on review branches, not in any release. Probe with `lium <cmd> --help`
before relying on one; until then use the workarounds in this file.

| Upcoming | Today |
|----------|-------|
| `lium up --verify-gpus` / `--strict-gpus` | `nvidia-smi -L \| wc -l` vs `ps --format json` `gpu_count` |
| `lium exec --detach` / `--log` | `nohup setsid ... < /dev/null &` |
| `lium templates --format json`, id column | `curl .../api/templates` or `Lium().templates()` |
| `--json` alias on `ps`, `ls`, `templates`, `balance`; `balance --format json` | `--format json` on `ps`/`ls`, `--json` on `balance` |
| Key fingerprint + source in 401/403 messages | check `LIUM_API_KEY` vs `~/.lium/config.ini` yourself |
| `LIUM_NONINTERACTIVE=1` refusing to prompt | pass `-y`, `--no-ssh`, all arguments |
| `Lium.up(..., wait=True)`, `exec(detach=True)`, `rsync(bwlimit=...)`, `cp()` | see the SDK reference's agent recipe |

## CLI Quick Reference

### Discovery

```bash
lium ls                        # all available GPUs (shows table with ★ for best price/perf)
lium ls --gpu H100             # filter by GPU type (there is no positional argument)
lium ls --sort download        # sort by download speed (fastest first) — preferred default
lium ls --sort upload          # sort by upload speed
lium ls --sort price_gpu       # sort by price per GPU/hour
lium ls --format json          # machine-parseable output
lium templates                 # list Docker templates
lium templates pytorch         # search templates
```

**Recommendation**: When selecting machines for the user, prefer `--sort download` to get the fastest network unless the user specifically asks to sort by price or other criteria.

### Pod Lifecycle

```bash
lium up --gpu H100 --name my-pod --ttl 4h -y --no-ssh   # create pod, return when ready
lium ps                        # list active pods
lium ps --format json          # machine-readable pod list (ssh_cmd, ports, price, spent)
lium ps my-pod --format json   # one pod
lium describe my-pod --json    # full manifest of one pod
lium audit --since 24h --json  # who did what to your pods — exits 3 auth_error on lium.io today: the backend does not yet serve /users/me/events to API keys (lium-platform#208)
lium ssh my-pod                # SSH into pod (interactive — not for agents)
lium exec my-pod "nvidia-smi"  # run command
lium exec all "pip install torch"  # batch exec on all pods
lium rm my-pod -y              # stop pod
lium rm -a -y                  # stop all pods
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
lium scp my-pod ./train.py                    # upload to ~ (/root) on the pod
lium scp my-pod ./data.csv /workspace/data/   # upload to a specific path
lium scp my-pod /workspace/out/final.mp4 ./ -d  # download one file
lium scp all ./config.json                    # upload to all pods
lium rsync my-pod ./project /workspace/project  # sync a local directory TO the pod (upload only)
```

`lium rsync` is upload-only and takes no flags. Pull directories back with plain
`rsync` over the pod's SSH endpoint (`ssh_cmd` from `lium ps --format json` gives
host and port; see `lium rsync` in the CLI reference).

### Pod Targeting

Pods accept: name, index from `lium ps`, comma-separated (`1,2,3`), or `all`.

### Output Formats

Always use `--format json` when parsing output programmatically:

```bash
lium ls --format json | python -c "import json,sys; print(json.load(sys.stdin))"
lium ps --format json | python -c "import json,sys; print(json.load(sys.stdin))"
```

Never read node ids or prices off the `lium ls` table. When stdout is not a terminal the table
is rendered 80 columns wide, and at that width it has no **Id** column, no row index, and the
price cell is truncated to `0…`; the Id and Location columns only appear from about 130
columns. The JSON has every field: `id` (UUID — what `lium up` accepts), `huid` (the short
name the table shows; not accepted by `lium up` in the current release, 0.0.37 and
earlier — lium#153 fixes it, not released), `price_per_hour`,
`price_per_gpu_hour`, `gpu_count`, `download_mbps`, `upload_mbps`, `country`.

`--format [table|json]` exists on `lium ls` and `lium ps` (on 0.0.37/0.0.38
`lium ps --json` is rejected). `--json` — a plain flag, not a format choice — is taken by
`lium describe`, `lium exec`, `lium audit`, `lium fund`, `lium balance`,
`lium signup`, `lium topup create`, `lium topup currencies`, and by the whole
`lium provider` group (set it on the group: `lium provider --json node list`).
On 0.0.37/0.0.38 `lium templates` and `lium up` have neither, and neither does
anything else. Since 0.0.39 (lium#217) `--json` is an alias of `--format json` on
`ls`, `ps` and `templates` (so `lium ps --json` works), `templates --format json`
prints the ids, and `LIUM_OUTPUT=json` makes every failure a JSON envelope on
stderr; `lium up` still has no JSON output.

## End-to-End Agent Workflow

Complete flow for setting up and renting a GPU pod:

```bash
# 1. Install lium (if not present)
if ! command -v lium >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/Datura-ai/lium/main/scripts/install.sh | bash
  export PATH="$HOME/.lium/bin:$PATH"
fi

# 2a. No account, no mailbox → fingerprint signup, no human needed. Save `fingerprint` for the
#     user (dashboard login, shown once). If api_key is null, mint one after signing in with it.
curl -fsS -X POST https://lium.io/api/auth/signup -H 'Content-Type: application/json' -d '{}'
lium config set api.api_key <API_KEY_FROM_RESPONSE>

# 2b. No account, but a human can click the confirmation link → ask for their real email
lium signup --email <USER_EMAIL>

# 2c. Existing account → two-step headless auth instead
lium init --no-browser
# → parse URL and session ID from output, show URL to user
# → wait for user to confirm they approved
lium init --session <SESSION_ID>

# 3. Verify (lium ls exits 0 even on an auth failure — check balance instead)
lium balance --json
# A zero balance means signup credit did not land; fund the account before renting.

# 4. Find suitable GPU (sort by speed by default)
lium ls --gpu H100 --sort download

# 5. Create pod (non-interactive! --no-ssh returns instead of opening a session).
#    --verify-gpus compares the billed count with nvidia-smi over SSH; --strict-gpus removes a wrong pod.
lium up --gpu H100 --name work-pod --ttl 6h --verify-gpus --strict-gpus -y --no-ssh \
  || { lium ps work-pod --format json | grep -q '"id"' && lium rm work-pod -y; exit 1; }   # exit 1 can leave a billing pod (pod_not_ready)

# 6. Read the pod record (up has no JSON output)
lium ps work-pod --format json

# 7. Use the pod
lium scp work-pod ./code.py /workspace/code.py
lium exec work-pod "cd /workspace && python code.py"

# 8. Cleanup
lium rm work-pod -y
lium ps                                        # confirm nothing is left billing
```

## Run One Python Function on a GPU (no pod scripting)

When the task is "run this function on a GPU and give me the result" — a benchmark, an inference, an embedding batch — use `@lium.machine` from the SDK instead of `up` / `scp` / `exec` / `rm` by hand. It rents the cheapest matching node, ships the function, installs the requirements once, streams the function's output, returns the result (or re-raises its exception) and removes the pod. Cost is bounded: the pod is scheduled for removal at `timeout + 15 min` (plus `keep_warm`) from the moment it is rented. Everything in this section beyond `machine`, `template_id`, `cleanup` and `requirements` **needs 0.0.40 (lium#208, DAH-3014)**: on 0.0.37–0.0.39 the decorator takes only those four, picks the first node whose name contains the string, installs `requirements` into an isolated venv (so torch must be listed there too), matches `machine` as a substring of the node's name (`"H200"`; the `"1xH200"` form is 0.0.40 too), and results must be JSON-serialisable.

```python
import lium

@lium.machine(machine="RTX4090", requirements=["transformers", "accelerate"], timeout=600, keep_warm=300)
def generate(prompt: str) -> str:
    import torch                                  # import INSIDE the function; only its def travels
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok = AutoTokenizer.from_pretrained("HuggingFaceTB/SmolLM2-135M-Instruct")
    model = AutoModelForCausalLM.from_pretrained("HuggingFaceTB/SmolLM2-135M-Instruct", dtype=torch.bfloat16, device_map="cuda")
    ids = tok.apply_chat_template([{"role": "user", "content": prompt}], return_tensors="pt", add_generation_prompt=True).to("cuda")
    out = model.generate(ids, max_new_tokens=64, do_sample=False, pad_token_id=tok.eos_token_id)
    return tok.decode(out[0][ids.shape[-1]:], skip_special_tokens=True).strip()

try:
    print(generate("Who discovered penicillin?"))    # cold: ~1-2 min (rent, boot, install); warm: ~20 s
    print(generate("Name one antibiotic."))          # reuses the warm pod
except Exception as e:                                # a builtin raised remotely: the same type, e.__cause__ is lium.RemoteExecutionError;
    cause = e.__cause__ if isinstance(e.__cause__, lium.RemoteExecutionError) else None   # a timeout, no node, a failed rental: no cause
    print(type(e).__name__, e, cause.remote_traceback if cause else "")
finally:
    generate.close()                                  # remove the warm pod now (else: keep_warm + 2 min later)
```

Rules that save a failed call: `machine` is `"<count>x<gpu>"` / `"<gpu>"` (`"1xH200"`, `"RTX4090"`; count defaults to 1 — `"A100"` is one A100, not eight). Import inside the function; a module-level import/constant/helper used inside is refused at definition time (it would be a `NameError` on the pod). Return plain Python types (`str()`, `.tolist()`, `.cpu().numpy()`), not tensors or `torch.__version__`. Torch is already on the default template — do not put it in `requirements` (since 0.0.40 the venv sees the image's packages; before that it does not — list it there). `f.map(items)` runs a batch on one pod; `f.local(x)` or `LIUM_MACHINE_LOCAL=1` runs the function locally for tests; `quiet=True` drops the `[lium]` progress lines (the function's own prints still stream). Like the rest of this section (`timeout`, `keep_warm`, `close()`, `RemoteExecutionError`, the node pick), every one of these (map, local, LIUM_MACHINE_LOCAL, quiet) is 0.0.40 (lium#208) — not one of them exists on 0.0.37–0.0.39.

## Detailed References

- **Full CLI command reference**: [references/cli-commands.md](references/cli-commands.md) (also at https://raw.githubusercontent.com/Datura-ai/lium-skill/main/lium/references/cli-commands.md) — all commands, flags, volumes, backups, scheduling, port-forward, etc.
- **Python SDK reference**: [references/sdk-reference.md](references/sdk-reference.md) (also at https://raw.githubusercontent.com/Datura-ai/lium-skill/main/lium/references/sdk-reference.md) — programmatic access via `lium.sdk.Lium` (real signatures, models, exceptions), an end-to-end agent recipe, and the `@machine` decorator.
- **Recipes**: [references/recipes.md](references/recipes.md) (also at https://raw.githubusercontent.com/Datura-ai/lium-skill/main/lium/references/recipes.md) — copy-paste jobs with teardown: GPU-count verification script, vLLM/SGLang serving on 8 GPUs, best-of-N diffusion, RL/simulation, batch data.
