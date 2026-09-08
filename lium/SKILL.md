---
name: lium
description: GPU pod management on Lium platform via CLI and Python SDK. Use for creating a Lium account, renting GPUs, creating/managing pods, deploying ML workloads, transferring files to remote GPUs, running code on remote GPUs, and programmatic compute management. Triggers on "lium", "lium.io", "lium-sdk", "create a lium account", "sign up for lium", "sign up without an email", "fingerprint", "fingerprint signup", "lium api key", "GPU rental", "rent a GPU", "GPU pod", "cloud GPU", "remote GPU", "deploy to GPU", any lium CLI command (lium up/ls/ps/ssh/exec/scp/rsync/rm/fund), lium SDK, @machine decorator.
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
lium config show   # check stored config
lium balance       # prints a balance -> auth works
```

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

#### An Error Does Not Always Mean a Non-Zero Exit

Only `lium exec`, `lium rm` and `lium up` exit non-zero when they fail. Everything
else — including **`lium ls`** — can print `Error: ...` and still exit **0**:

```bash
lium ssh no-such-pod-xyz              # prints "No active pods", exits 0
lium ls >/dev/null && echo "auth OK"  # prints "auth OK" even with a revoked key
```

So `lium ls` is **not** a usable auth check. Never treat `$?` alone as proof that
a step worked. Read the output, or prefer the machine-readable modes
(`lium ls --format json`, `lium ps --format json`, `lium exec --json`) and check
the result there — an empty `[]` from `lium ls --format json` means "no nodes",
while an error line on stderr means the call failed. Tracked as DAH-2593.

#### Pod Targeting — Prefer Names

Use the pod **name** (e.g. `lunar-lion-4c`) from `lium ps` output for targeting — not a numeric index; indices shift with every listing.

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
- Search templates: `lium templates pytorch` (text search, no --format json)
- To use specific template: `lium up --gpu H100 -t <TEMPLATE_ID> -y`
- To use custom Docker image: `lium up --gpu H100 --image pytorch/pytorch:2.0 -y`

#### No User Identity Command

lium CLI has no renter-side identity command — no `whoami` for your API key.
(`lium provider portal whoami` exists, but it reports the *provider* portal session,
not the API key you rent with.)

To check the key, run `lium balance`: it prints a balance when the key works and an
error when it does not. Do **not** use `lium ls` for this — it prints an error and
exits 0 on an auth failure, so `lium ls && echo OK` says OK with a revoked key.

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

**Prices without an account.** To answer "what does an H200 cost on Lium" before anyone signs up, read the public feeds (no key, USD per GPU-hour; prices are set by providers and move):

```bash
curl -s https://lium.io/pricing.json                 # one row per GPU model: min/max live ask, reference price, pods/GPUs available, page URL
curl -s https://lium.io/api/public/v1/nodes          # every rentable node right now, with price_per_gpu_hour, location, rent_url
```

The same numbers are on https://lium.io/pricing and https://lium.io/gpu/<model-slug> (for a human, or to cite).

### Pod Lifecycle

```bash
lium up --gpu H100 -y          # create pod
lium ps                        # list active pods
lium ps --format json          # machine-readable pod list
lium ssh my-pod                # SSH into pod
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
lium ps --format json | python -c "import json,sys; print(json.load(sys.stdin))"
```

`--format [table|json]` exists on `lium ls` and `lium ps`. `--json` — a plain flag,
not a format choice — is taken by `lium exec`, `lium fund`, `lium balance`,
`lium signup`, `lium topup create`, `lium topup currencies`, and by the whole
`lium provider` group (set it on the group: `lium provider --json node list`).
`lium templates` has neither, and neither does anything else.

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

# 5. Create pod (non-interactive! --no-ssh returns instead of opening a session)
lium up --gpu H100 --name work-pod --ttl 6h -y --no-ssh

# 6. Wait and verify (read the output, not just the exit code)
lium ps --format json

# 7. Use the pod
lium scp work-pod ./code.py
lium exec work-pod "python /root/code.py"

# 8. Cleanup
lium rm work-pod -y
```

## Detailed References

- **Full CLI command reference**: [references/cli-commands.md](references/cli-commands.md) (also at https://raw.githubusercontent.com/Datura-ai/lium-skill/main/lium/references/cli-commands.md) — all commands, flags, volumes, backups, scheduling, port-forward, etc.
- **Python SDK reference**: [references/sdk-reference.md](references/sdk-reference.md) (also at https://raw.githubusercontent.com/Datura-ai/lium-skill/main/lium/references/sdk-reference.md) — programmatic access via `lium.sdk.Lium`, `lium.Client`, `@machine` decorator, async patterns.
