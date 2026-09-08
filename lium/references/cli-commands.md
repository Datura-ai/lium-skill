# Lium CLI Command Reference

Written against `lium --version` **0.0.29**. Every flag below appears in that
binary's own `--help`; nothing here is extrapolated. When a newer CLI ships,
`lium <command> --help` is the authority, not this file. The one exception is
marked inline: an option or command tagged **(lium#NNN, not released)** is read
off that open lium PR's `--help` and is not in the released binary yet.

## Table of Contents

- [Global Options](#global-options)
- [lium signup](#lium-signup)
- [lium init](#lium-init)
- [lium balance](#lium-balance)
- [lium ls](#lium-ls)
- [lium up](#lium-up)
- [lium ps](#lium-ps)
- [lium audit](#lium-audit)
- [lium ssh](#lium-ssh)
- [lium exec](#lium-exec)
- [lium scp](#lium-scp)
- [lium rsync](#lium-rsync)
- [lium rm](#lium-rm)
- [lium logs](#lium-logs)
- [lium port-forward](#lium-port-forward)
- [lium reboot](#lium-reboot)
- [lium update](#lium-update)
- [lium templates](#lium-templates)
- [lium volumes](#lium-volumes)
- [lium bk (backups)](#lium-bk-backups)
- [lium schedules](#lium-schedules)
- [lium ssh-keys](#lium-ssh-keys)
- [lium config](#lium-config)
- [lium theme](#lium-theme)
- [lium fund](#lium-fund)
- [lium topup](#lium-topup)
- [lium mine](#lium-mine)
- [lium provider](#lium-provider)
- [lium gpu-splitting](#lium-gpu-splitting)
- [Batch Operations](#batch-operations)
- [Pod Targeting](#pod-targeting)
- [Environment Variables](#environment-variables)
- [Exit Codes](#exit-codes)

## Global Options

The root command takes exactly two options:

```
--version   Show the version and exit
--help      Show this message and exit
```

There is no `--config` and no `--debug` flag. Debug output is switched on with
the `LIUM_DEBUG=1` environment variable, and the config file location comes from
`lium config path`.

## lium signup

Create a Lium account and store the API key it mints. Fully non-interactive — this is
the command to use when the user has **no account yet**. Older CLI binaries do not have it —
probe with `lium signup --help` and update the CLI when it is missing.

```bash
lium signup [OPTIONS]
  --email EMAIL       The user's real email (REQUIRED) — the confirmation link goes there
  --name NAME         Display name (defaults to the email's local part)
  --password PASSWORD Account password (a strong one is generated when omitted)
  --json              Machine-readable output
```

The password can also come from the `LIUM_SIGNUP_PASSWORD` environment variable — `--password`
wins when both are set. Prefer the variable: a flag value is left behind in the shell history
and in `ps` output. Whatever its origin, the password is always reported back to the caller.

Ask the user for their **real** email — the account, its balance, password recovery and the
confirmation link are all tied to it. Never invent an address.

The command creates the account (`POST /users`), stores the minted API key in
`~/.lium/config.ini` under `api.api_key`, and sets up an SSH key. After it, `lium ls` and
`lium up` work with no further setup.

**Refuses to run when `api.api_key` is already configured** — it exits with an error instead
of creating a second, unreachable account. To sign up anyway, drop the existing key first:

```bash
lium config unset api.api_key   # then: lium signup --email ...
```

**Failures never strand the account.** When the command fails after the account was created —
the request timed out, or the API key could not be read back — the error still reports the
email and password, so the user can log in at https://lium.io and copy an API key from the
dashboard. With `--json`, that error goes to stderr as
`{"ok": false, "error": {...}, "data": {"email": "...", "password": "..."}}`.

Examples:
```bash
lium signup --email ada@example.com
lium signup --email ada@example.com --name Ada --json
LIUM_SIGNUP_PASSWORD=... lium signup --email ada@example.com
```

`--json` output:
```json
{
  "api_key": "sk_...",
  "email": "ada@example.com",
  "next_steps": ["...", "...", "..."],
  "password": "generated-or-supplied",
  "signup_credit_granted": true,
  "ssh_key_configured": true
}
```

- `password` — the dashboard login at https://lium.io. Hand it to the user; it is not stored anywhere else.
- `signup_credit_granted` — comes straight from the signup API response and is the authoritative
  answer to "did the $5 signup credit land?": `true` → granted; `false` → not granted (the
  once-per-IP gate, or the credit disabled platform-side); `null` → the backend did not report
  it (older backend) — read the balance instead: `lium balance --json`.
- Renting is not gated on email confirmation — a funded balance is the only requirement. Clicking
  the link in the **"Please confirm your email"** mail (the separate "Welcome to Celium!" mail
  carries no link) confirms the address, so that password resets and account emails reach the user.

## lium init

Initialize the CLI for a user who **already has an account** — `lium init` cannot create
one, use [`lium signup`](#lium-signup) for that. Plain `lium init` opens a browser and is
**not suitable for agent use**; the `--no-browser` / `--session` pair is the headless two-step.

```bash
lium init [OPTIONS]
  --no-browser    Print the auth URL + session ID instead of opening a browser (step 1)
  --session ID    Verify the auth session and save the API key (step 2)
```

For an agent that already holds an API key, write the config directly instead:
```bash
lium config set api.api_key YOUR_KEY
lium config set ssh.key_path ~/.ssh/id_ed25519
```

## lium balance

Show the current account balance.

```bash
lium balance [OPTIONS]
  --json   Print machine-readable JSON
```

## lium ls

List available GPU nodes. There is no positional argument — filter with `--gpu`.

```bash
lium ls [OPTIONS]
  --gpu TEXT              Filter by GPU type, e.g. A100
  --count INTEGER         Exact GPU count to match (e.g. 1, 8)
  --min-cuda FLOAT        Minimum CUDA version, e.g. 12.4
  --lat FLOAT             Latitude for distance filtering
  --lon FLOAT             Longitude for distance filtering
  --max-distance INTEGER  Maximum distance in miles from --lat/--lon
  --sort FIELD            price_gpu | price_total | loc | id | gpu | download |
                          upload | price_per_gpu_hour | price_per_hour
                          (an explicit --sort wins over the ★ optimal ordering)
  --limit INTEGER         Limit the number of rows shown
  --format [table|json]   Output format; 'json' goes to stdout, suitable for jq
```

Examples:
```bash
lium ls                         # all nodes
lium ls --gpu H100              # only H100 nodes
lium ls --gpu H100 --count 8    # only 8×H100 nodes
lium ls --format json           # JSON output for parsing
lium ls --sort price_per_gpu_hour --limit 10
```

## lium up

Create a new pod. **Always pass `-y` for non-interactive (agent) usage.**

```bash
lium up [OPTIONS] [NODE_ID]
  NODE_ID                     Node UUID, HUID, or index from the last `lium ls`.
                              Optional — omit it and the filters below auto-select
                              the best node. (`lium up --help` prints NODE_ID without
                              brackets; the argument is optional all the same.)
  -n, --name TEXT             Custom pod name
  -t, --template_id TEXT      Template ID
  -v, --volume TEXT           Volume spec: 'id:<HUID>' or 'new:name=<NAME>[,desc=<DESC>]'
  -y, --yes                   Skip the confirmation prompt (REQUIRED for agent use)
  --gpu TEXT                  Filter nodes by GPU type (e.g. H200, A6000)
  -c, --count INTEGER         Number of GPUs per pod
  --country TEXT              Filter nodes by ISO country code (e.g. US, FR)
  -p, --ports INTEGER         Minimum number of available ports required
  --ttl TEXT                  Auto-terminate after a duration (6h, 45m, 2d)
  --until TEXT                Auto-terminate at a local time ("today 23:00",
                              "tomorrow 01:00", "2025-10-20 15:30")
  --jupyter                   Install Jupyter Notebook (auto-selects a port)
  --no-ssh                    Create the pod and return instead of opening an SSH session
  --image TEXT                Docker image to run (e.g. pytorch/pytorch:2.0)
  --internal-ports TEXT       Internal ports to expose (comma-separated: 22,8000,8080)
  --dockerfile FILE           Build the pod image from this Dockerfile
                              (mutually exclusive with --image / --template_id)
  -e, --env TEXT              Environment variables (KEY=VALUE), repeatable
  --entrypoint TEXT           Container entrypoint
  --cmd TEXT                  Command to run in the container
  --ssh-name TEXT             Name to register a new SSH key under
                              (default: cli-<user>@<hostname>)
  --volume-encryption / --no-volume-encryption
                              Encrypt the local volume when supported (on by default)
```

`--no-ssh` matters for agents: without it `lium up` ends by opening an interactive
SSH session (or, with `--image`, by streaming container logs).

Examples:
```bash
# Non-interactive (for agents):
lium up --gpu H100 -y --no-ssh                    # auto-select + default template
lium up --gpu H200 --country US --name train -y --no-ssh
lium up --gpu H100 --ttl 6h --jupyter -y --no-ssh

# Docker-run style (streams logs instead of SSH):
lium up --gpu A4000 --image pytorch/pytorch:2.0 -y
lium up --gpu H100 --image vllm/vllm-openai:latest -e HF_TOKEN=xxx -y

# Custom Dockerfile, built remotely:
lium up --gpu A4000 --dockerfile ./Dockerfile -y

# With volumes:
lium up --gpu H100 -v id:brave-fox-3a -y          # attach an existing volume
lium up --gpu H100 -v new:name=data -y            # create + attach a volume

# Specific node:
lium up 1 --name dev-pod -y                       # node #1 from the last ls
```

## lium ps

List active pods. The optional positional narrows the listing to one pod.

```bash
lium ps [OPTIONS] [POD_ID]
  POD_ID                 Show a single pod — name, HUID or UUID only, NOT an index
  --format [table|json]  Output format; 'json' goes to stdout, suitable for jq
```

`lium ps --format json` **is supported** and is the way an agent should read pod
state. There is no `-a/--all` and no `--sort`.

## lium audit

**Not in lium 0.0.33 — lium#160, not released.** Who did what to the account's pods, and
when: every rent, reboot, edit and delete with the session or API key that requested it;
entries the platform wrote by itself (a validator reply, a balance stop) say `platform`.
Needs a backend that serves `GET /users/me/events` to API keys (lium-platform#208); against
today's API it exits `3` with a hint.

```bash
lium audit [OPTIONS]                 # lium#160, not released
  --pod TEXT             Only this pod: id, huid, name or index from the last ps; a deleted
                         pod's full id
  --since TEXT           Only events after this: 24h, 30m, 7d or an ISO timestamp (else exit 2)
  --key TEXT             Only actions made with this API key id
  --limit INTEGER        Newest events to fetch, 1–1000 (default 200; out of range exits 2 locally)
  --json                 Print the events as machine-readable JSON (newest first)
```

The table — When (UTC) / Pod / What / By — reads oldest first. `By` is `key <name> (<id8>)`,
`session` (browser) or `platform`. Exit `5` when `--pod` is neither a listed pod nor a full UUID
(a full id passes through so a deleted pod can be queried).

```bash
lium audit --since 24h                                              # today — lium#160, not released
lium audit --pod my-pod                                             # one pod's history — lium#160, not released
lium audit --json | jq '.[] | select(.actor.api_key_name == "ci")'  # one key's actions — lium#160, not released
```

## lium ssh

Open an interactive SSH session to a pod. It takes no options — to run a command
and exit, use [`lium exec`](#lium-exec).

```bash
lium ssh TARGET
  TARGET   Pod name/ID (eager-wolf-aa) or index from `lium ps` (1, 2, 3)
```

## lium exec

Execute commands on one or more pods. **This is the command an agent uses to run
things remotely** — it exits with the remote command's exit code, so
`lium exec <pod> "cmd" && next-step` behaves the way a caller expects.

```bash
lium exec [OPTIONS] TARGETS [COMMAND]
  TARGETS            Pod name/ID, index, comma-separated list, or "all"
  COMMAND            Command to execute (quote multi-word commands)
  -s, --script TEXT  Execute a local script file on the pod
  -e, --env TEXT     Set environment variables (KEY=VALUE)
  --json             Print machine-readable JSON (stdout, stderr, exit_code)
```

Examples:
```bash
lium exec my-pod "python train.py"
lium exec 1 "python --version"
lium exec 1 "nvidia-smi"
lium exec 1,2,3 "uptime"
lium exec all "df -h"
lium exec 1 --script setup.sh
lium exec 1 -e API_KEY=xyz "python app.py"
lium exec 1 --json "python train.py"
```

There is no `--timeout` and no `--output`; redirect the output in the shell
(`lium exec 1 "nvidia-smi" > gpu.txt`).

## lium scp

Copy files between the local machine and pods. Upload is the default; `-d` flips
the direction.

```bash
lium scp [OPTIONS] TARGETS SOURCE_PATH [DESTINATION_PATH]
  TARGETS           Pod name/ID, index, comma-separated list, or "all"
  SOURCE_PATH       Local file (upload) or remote path (download)
  DESTINATION_PATH  Optional; for multiple pods a download destination must be a directory
  -d, --download    Download from the pods to the local machine
```

Examples:
```bash
lium scp 1 ./script.py                     # upload to ~/script.py on pod #1
lium scp eager-wolf-aa ./data.csv ~/data/  # upload into a directory
lium scp all ./config.json                 # upload to every pod
lium scp 2 /root/output.log ./outputs -d   # download from pod #2 into ./outputs/
```

There is no `-r/--recursive` and no `-p/--preserve`; use
[`lium rsync`](#lium-rsync) for directories.

## lium rsync

Sync a directory to pods with rsync. It takes no options.

```bash
lium rsync TARGETS LOCAL_PATH [REMOTE_PATH]
  TARGETS      Pod name/ID, index, comma-separated list, or "all"
  LOCAL_PATH   Local directory to sync
  REMOTE_PATH  Optional destination path
```

## lium rm

Remove (terminate) pods. Removal is irreversible. The command exits non-zero when
nothing matched `TARGETS`, so a typo cannot look like a successful teardown.

```bash
lium rm [OPTIONS] [TARGETS]
  TARGETS    Pod name(s)/ID(s), index/indices, comma-separated list, or "all"
  -a, --all  Remove all active pods
  -y, --yes  Skip the confirmation prompt
  --in TEXT  Schedule the removal after a duration (e.g. 6h)
  --at TEXT  Schedule the removal at a time (e.g. "tomorrow 01:00")
```

`--in` and `--at` **schedule** a removal rather than filtering which pods to
remove; cancel a scheduled one with [`lium schedules rm`](#lium-schedules).

**Agent usage** — `-y` exists, no piped `yes` needed:
```bash
lium rm my-pod -y        # single pod
lium rm -a -y            # all pods
lium rm 1,2,3 -y         # several by index
lium rm my-pod --in 6h   # schedule removal in six hours
```

## lium logs

Stream logs from a pod.

```bash
lium logs [OPTIONS] POD_ID
  POD_ID              Pod name, HUID or UUID — NOT an index
  -n, --tail INTEGER  Number of lines to show from the end of the logs
  -f, --follow        Follow log output
```

Examples:
```bash
lium logs abc123           # last 100 lines
lium logs abc123 -n 50     # last 50 lines
lium logs abc123 -f -n 10  # follow, with 10 lines of history
```

## lium port-forward

Forward a local port to a pod's internal port. Useful for Jupyter, TensorBoard and
other web services.

```bash
lium port-forward [OPTIONS] TARGET PORT
  TARGET                    Pod name/ID or index
  PORT                      The internal port on the pod to forward to
  -l, --local-port INTEGER  Local port to bind (defaults to the same as PORT)
```

Examples:
```bash
lium port-forward my-pod 8888     # localhost:8888 -> pod's 8888
lium port-forward 1 8000 -l 3000  # localhost:3000 -> pod's 8000
```

## lium reboot

Reboot pods.

```bash
lium reboot [OPTIONS] [TARGETS]
  TARGETS           Pod name(s)/ID(s), index/indices, or "all"
  -a, --all         Reboot all active pods
  --volume-id TEXT  Volume ID to attach when rebooting
```

A reboot re-creates the pod: everything outside an attached volume is lost.

## lium update

Update the configuration of a running pod.

```bash
lium update [OPTIONS] TARGET
  TARGET             Pod name/ID or index
  --jupyter INTEGER  Install Jupyter Notebook on the given internal port
```

## lium templates

List available Docker templates and images. It takes no options.

```bash
lium templates [SEARCH]
  SEARCH   Text search to filter templates (e.g. "pytorch", "tensorflow")
```

**Notes**:
- Without `--template_id`, `lium up` uses the default **PyTorch (CUDA)** template — fastest to start
- Default Docker-in-Docker (dind) image: `daturaai/dind`

## lium volumes

Manage persistent volumes.

```bash
lium volumes list                     # list all volumes
lium volumes new NAME [-d DESC]       # create a volume (-d, --desc)
lium volumes rm INDICES [-y, --yes]   # remove by index from the last `lium volumes list`
```

`volumes rm` takes **indices from the previous listing**, not names or HUIDs — run
`lium volumes list` first.

## lium bk (backups)

Manage pod backup configurations. `POD_ID` is a pod name/ID or an index from
`lium ps`.

```bash
lium bk show POD_ID                   # show the backup config
lium bk set POD_ID [OPTIONS]          # set or update it
  --path TEXT    Backup path (default: /root)
  --every TEXT   Backup frequency (1h, 6h, 24h)
  --keep TEXT    Retention period (1d, 7d, 30d)
  -y, --yes      Skip the confirmation prompt
lium bk now POD_ID [OPTIONS]          # trigger an immediate backup
  -n, --name TEXT         Backup name (e.g. 'pre-release')
  -d, --description TEXT  Backup description
lium bk logs [POD_ID] [--id ID]       # backup logs, or details of one backup
lium bk restore POD_ID --id ID        # restore a backup (--id is required)
  --to TEXT      Restore path (default: /root)
  -y, --yes      Skip the confirmation prompt
lium bk restore-logs [POD_ID] [--id ID]
lium bk rm POD_ID [-y]                # remove the backup config
```

`--path` on `bk set` is a flag, not a positional: `lium bk set 1 --path /root --every 6h --keep 7d`.

## lium schedules

Manage scheduled pod terminations (the ones created by `lium rm --in/--at` and by
`lium up --ttl/--until`).

```bash
lium schedules list       # list all pods with scheduled terminations
lium schedules rm INDICES # cancel by index from the listing
```

## lium ssh-keys

Manage the SSH public keys registered with Lium.

```bash
lium ssh-keys list   # list the keys registered with Lium
lium ssh-keys sync   # register every local SSH pubkey that isn't on Lium yet
```

## lium config

Manage the CLI configuration (`~/.lium/config.ini`).

```bash
lium config show                          # display the entire configuration
lium config get api.api_key               # get one value
lium config set ssh.key_path ~/.ssh/key   # set one value (interactive without VALUE)
lium config unset api.api_key             # remove one value
lium config path                          # print the config file path
lium config reset [--confirm]             # reset to defaults
lium config edit                          # open in the default editor
```

## lium theme

Set the CLI color theme. The argument is required and accepts only two values.

```bash
lium theme {dark|light}
```

## lium fund

Fund the account with TAO — or with free Subnet-51 alpha stake — from a Bittensor
wallet. **Always pass `-y` for agent use.**

```bash
lium fund [OPTIONS]
  -w, --wallet TEXT  Bittensor wallet name to fund from
  -a, --amount TEXT  Amount to fund with (TAO; USD when --alpha)
  --alpha            Fund with free Subnet-51 alpha stake
  -k, --hotkey TEXT  Origin hotkey the alpha is staked under — SS58 address or
                     wallet hotkey name (required with --alpha)
  --json             Print machine-readable JSON
  -y, --yes          Skip confirmation prompts
```

Examples:
```bash
lium fund -w default -a 1.5 -y
lium fund --alpha -k <hotkey-ss58> -a 25 -y --json   # -a is USD when --alpha
```

## lium topup

Top up the balance with a stablecoin.

```bash
lium topup currencies [OPTIONS]         # list supported stablecoins and networks
  --refresh            Bypass the cache and re-fetch
  --json               Print machine-readable JSON
lium topup create [OPTIONS]             # create an invoice, print the deposit address
  -a, --amount FLOAT   Top-up amount in USD (required)
  -c, --currency TEXT  Stablecoin code, e.g. USDT (required)
  -n, --network TEXT   Network, e.g. tron (required)
  --json               Print machine-readable JSON
```

Send exactly the returned `crypto_amount` to the deposit address on that network;
the balance is credited once the transfer confirms.

```bash
lium topup create -a 20 -c USDT -n tron --json
```

## lium mine

Bootstrap a Subnet-51 **provider** machine: clone `Datura-ai/lium-io` into
`compute-subnet`, install the executor tooling, write `neurons/executor/.env` and
start the executor container. It runs on the GPU host you are contributing, not
on a renter's laptop.

`lium provider --help` calls this "renter workflows" — that blurb is wrong; the
code clones and starts a miner executor.

```bash
lium mine [OPTIONS]
  -k, --hotkey TEXT  Miner hotkey SS58 address
  -d, --dir TEXT     Target directory
  -b, --branch TEXT  Branch to install from
  -a, --auto         Run without prompting
  -v, --verbose      Show the plan banner
```

## lium provider

Provider-side commands for Subnet 51 mining — a different persona from `lium mine`.
Hotkey registration on SN51 itself is done with `btcli subnet register`, not here.

```bash
lium provider [OPTIONS] COMMAND [ARGS]...
  -w, --coldkey TEXT  Bittensor coldkey (wallet) name; falls back to
                      LIUM_PROVIDER_COLDKEY, then `provider.coldkey` in the config
  -k, --hotkey TEXT   Hotkey name on that coldkey; falls back to
                      LIUM_PROVIDER_HOTKEY, then `provider.hotkey`
  --portal-url TEXT   Override the lium-miner-portal base URL
  --json              Machine-readable JSON (one envelope per command)
  --debug             Error context on stderr; verbose logging
  -y, --yes           Auto-confirm the persona gate for spend-affecting subcommands
  --dry-run           Skip irreversible subprocess calls (e.g. ssh), report intent only
```

Sub-commands: `billing`, `config`, `machine`, `machine-request`, `node`, `portal`,
`status`, `sync`. Run `lium provider <sub> --help` for their flags.

## lium gpu-splitting

Prepare Docker storage on a host for LIUM GPU splitting.

```bash
lium gpu-splitting check [--device PATH]        # inspect the host, print the plan, change nothing
lium gpu-splitting setup [--device PATH] --yes  # end-to-end Docker storage setup
lium gpu-splitting verify                       # verify the host meets the requirements
```

`setup` is the only one that changes the host, and it stops on an interactive
confirmation of the plan — pass `--yes` from a script.

## Batch Operations

`exec`, `scp`, `rsync`, `rm` and `reboot` take several targets at once, as a
comma-separated list or `all`:

```bash
lium exec 1,2,3 "apt update"
lium exec all "nvidia-smi"
lium scp all ./requirements.txt
lium rsync all ./project
lium rm 1,2,3 -y
```

## Pod Targeting

The pod argument is called `TARGET` (single) or `TARGETS` (several) in the CLI's
own help; `logs`, `ps` and the `bk` sub-commands call it `POD_ID`. What each
form accepts is **not** uniform:

| Form | Example | Accepted by |
|------|---------|-------------|
| Name / HUID / UUID | `lium ssh eager-wolf-aa` | every command |
| Index from the last `lium ps` | `lium ssh 1` | `ssh`, `exec`, `scp`, `rsync`, `rm`, `reboot`, `update`, `port-forward`, `bk *`, `audit --pod` (lium#160, not released) — **not** `ps` and **not** `logs` |
| Comma list | `lium exec 1,2,3 "cmd"` | `TARGETS` commands only |
| All | `lium exec all "cmd"` | `TARGETS` commands only |

`lium ps 1` and `lium logs 1` match the literal string `1` against pod names and
IDs; they do not resolve indices, so they report the pod as not found unless a
pod is actually named `1`.

Indices come from the most recent listing and shift whenever anything is created
or removed. Prefer names: read them once with `lium ps --format json` and pass
those.

## Environment Variables

```bash
LIUM_API_KEY=xyz lium ls                    # override the API key
LIUM_DEBUG=1 lium up --gpu H100 -y          # debug output
LIUM_BASE_URL=https://staging.lium.io/api lium signup --email ada@example.com
LIUM_SIGNUP_PASSWORD=pw lium signup --email ada@example.com  # keeps the password off argv
LIUM_PROVIDER_COLDKEY=... LIUM_PROVIDER_HOTKEY=... lium provider status
```

`LIUM_BASE_URL` (default `https://lium.io/api`, the `/api` suffix included) points the SDK
**and** `lium signup` at another backend — use it to sign up against staging.
`LIUM_PAY_URL` overrides the payments backend the same way.

There is no `LIUM_SSH_KEY` variable — the SSH key path lives in the config
(`lium config set ssh.key_path ...`).

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error (bad arguments, unreadable script, missing config, no API key) |
| 3 | API error — the API refused or failed the call: 401 (bad or revoked key), 404, 429, 5xx |
| 4 | SSH error |
| 5 | Pod not found |
| 6 | Permission denied — the API answered 403 (an empty balance on `lium up`, for one) |

Since **0.0.31** (lium#104, DAH-2593) every command runs under one error handler
(`handle_errors` in `lium/cli/utils.py`), so the table holds for all of them:
`lium ls` with a revoked key exits `3`; `lium up` with an empty balance exits `6`.
Inside a batch the rule changes: `rm`, `reboot`, `scp`, `rsync` (and `volumes rm`,
`schedules rm`) finish the batch and exit `1` naming the items that failed, whatever
the API answered for them (`Failed to remove pods: brave-orbit-b9`); only their
target lookup before the batch exits `3`/`6`. The exceptions are `lium provider …`,
which keeps its own map (`1` arguments, `2` auth, `3` portal, `5` ssh, `6` config
missing, `7` token-cache contention), and `lium gpu-splitting …`, which runs on the
host without the API and exits `1` on any failure. `lium exec` exits with the remote
command's code (`5` when no pod matched, `2` on a bad argument or unreadable
script). Under `--json` (`exec`, `describe`, `balance`,
`fund`, `topup`, `signup`) a failure is one JSON object on stderr,
`{"ok": false, "error": {"code": ..., "message": ...}}`, and stdout stays empty;
`--format json` (`ls`, `ps`) reports a failure as text.

`lium audit` *(lium#160, not released)* adds nothing to the table: its 401 is
exit `3` like every other command's, with the hint that if the key works for
`lium ps` the backend does not yet open `/users/me/events` to API keys.
