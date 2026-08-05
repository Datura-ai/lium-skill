# Lium CLI Command Reference

Verified against the published CLI **v0.0.27**. Every flag below exists; nothing is
listed that the binary does not accept. When in doubt, `lium <command> --help` is
the source of truth.

## Table of Contents

- [Global Options](#global-options)
- [lium init](#lium-init)
- [lium ls](#lium-ls)
- [lium up](#lium-up)
- [lium ps](#lium-ps)
- [lium ssh](#lium-ssh)
- [lium exec](#lium-exec)
- [lium scp](#lium-scp)
- [lium rsync](#lium-rsync)
- [lium rm](#lium-rm)
- [lium templates](#lium-templates)
- [lium balance](#lium-balance)
- [lium fund](#lium-fund)
- [lium topup](#lium-topup)
- [lium config](#lium-config)
- [lium logs](#lium-logs)
- [lium port-forward](#lium-port-forward)
- [lium reboot](#lium-reboot)
- [lium update](#lium-update)
- [lium volumes](#lium-volumes)
- [lium bk (backups)](#lium-bk-backups)
- [lium schedules](#lium-schedules)
- [lium ssh-keys](#lium-ssh-keys)
- [lium theme](#lium-theme)
- [Batch Operations](#batch-operations)
- [Pod Targeting](#pod-targeting)
- [Environment Variables](#environment-variables)
- [Exit Codes](#exit-codes)

## Global Options

```
--help        Show help message
--version     Display CLI version
```

There is no global `--config` or `--debug`. Per-command flags are listed below.

## lium init

Set up the API key and SSH key. Has two non-interactive flags, so an agent can drive it:

```bash
lium init [OPTIONS]
  --no-browser        Print the approval URL and session id, then exit immediately
  --session SESSION   Complete auth with the session id from --no-browser
```

Alternatively, write the config directly when the key is already known:
```bash
lium config set api.api_key YOUR_KEY
lium config set ssh.key_path ~/.ssh/id_ed25519
```

## lium ls

List available GPU nodes.

```bash
lium ls [OPTIONS]
  --gpu TYPE            Filter by GPU type (H100, A100, RTX4090, H200, etc.)
  --count N             Exact GPU count to match
  --min-cuda VERSION    Minimum CUDA version, e.g. 12.4
  --lat / --lon / --max-distance   Filter by distance from a point
  --sort FIELD          download, upload, price_gpu, price_total, loc, id, gpu
  --limit N             Limit rows shown
  --format table|json   Output format (there is no csv)
```

Examples:
```bash
lium ls                       # all nodes
lium ls --gpu H100            # only H100 GPUs
lium ls --gpu H100 --count 8  # 8×H100 machines
lium ls --format json         # JSON output for parsing
```

There is no positional GPU argument — `lium ls H100` is not valid, use `--gpu H100`.

## lium up

Create a new pod. **Always use `-y` flag for non-interactive (agent) usage.**

```bash
lium up [EXECUTOR_ID] [OPTIONS]
  EXECUTOR_ID                 Executor UUID, HUID, or index from last lium ls
  -n, --name NAME             Custom pod name
  -t, --template_id ID        Template ID
  -v, --volume SPEC           Volume: id:<HUID> or new:name=<NAME>[,desc=<DESC>]
  -y, --yes                   Skip confirmation (REQUIRED for agent use)
  --gpu TYPE                  Filter by GPU type (H200, A6000, etc.)
  -c, --count NUM             Filter by GPU count per pod
  --country CODE              Filter by ISO country code (US, FR, etc.)
  -p, --ports NUM             Require ≥NUM ports AND allocate NUM ports
  --ttl DURATION              Auto-terminate after duration (6h, 45m, 2d)
  --until TIME                Auto-terminate at time ("today 23:00", "tomorrow 01:00")
  --jupyter                   Install Jupyter Notebook (auto-selects port)
  --image IMAGE               Docker image (e.g., pytorch/pytorch:2.0)
  --dockerfile PATH           Build from a Dockerfile instead of a prebuilt image
  -e, --env KEY=VALUE         Environment variables (repeatable)
  --cmd TEXT                  Command to run in container
  --entrypoint TEXT           Container entrypoint
  --internal-ports TEXT       Internal ports to expose (comma-separated)
  --ssh-name NAME             SSH key to register for this pod
  --volume-encryption / --no-volume-encryption   Encrypt the attached volume
```

Examples:
```bash
# Non-interactive (for agents):
lium up --gpu H100 -y                            # auto-select + default template
lium up --gpu H200 --country US --name train -y  # with filters
lium up --gpu H100 --ttl 6h --jupyter -y         # with TTL + Jupyter

# Docker-run style (streams logs instead of SSH):
lium up --gpu A4000 --image pytorch/pytorch:2.0 -y
lium up --gpu H100 --image vllm/vllm-openai:latest -e HF_TOKEN=xxx -y

# With volumes:
lium up --gpu H100 -v id:brave-fox-3a -y         # attach existing volume
lium up --gpu H100 -v new:name=data -y           # create + attach volume

# Specific executor:
lium up 1 --name dev-pod -y                      # executor #1 from last ls
```

## lium ps

List active pods.

```bash
lium ps [POD_ID] [OPTIONS]
  POD_ID                Show a single pod (id, huid or name)
  --format table|json   Output format (there is no csv)
```

## lium ssh

SSH into a pod. Takes a target and nothing else — there is no `--command`, `--port`
or `--key` flag. To run a command remotely use `lium exec`.

```bash
lium ssh TARGET
  TARGET            Pod name, huid or index from lium ps
```

## lium exec

Execute a command on one or more pods.

```bash
lium exec TARGETS [COMMAND] [OPTIONS]
  TARGETS           Pod name, index, comma-separated list, or "all"
  COMMAND           Command to execute (quote multi-word commands)
  -s, --script PATH Run a local script file on the pod instead of COMMAND
  -e, --env KEY=VAL Environment variables for the command (repeatable)
```

Examples:
```bash
lium exec my-pod "python train.py"
lium exec my-pod -s ./setup.sh
lium exec all "pip install numpy"
```

There is no `--timeout` and no `--output` — redirect on the shell side instead:
`lium exec my-pod "nvidia-smi" > gpu.txt`.

## lium scp

Copy files to and from pods.

```bash
lium scp TARGETS SOURCE_PATH [DESTINATION_PATH] [OPTIONS]
  TARGETS           Pod name, index, comma-separated list, or "all"
  SOURCE_PATH       File or directory to copy
  DESTINATION_PATH  Destination path (default: /root/)
  -d, --download    Download mode (pod → local)
```

Examples:
```bash
lium scp my-pod ./script.py                 # upload to /root/
lium scp 1 ./data.csv /root/datasets/       # specific destination
lium scp all ./config.json                  # upload to all pods
lium scp my-pod /root/out.txt ./ -d         # download from pod
```

There are no `-r` / `-p` flags — directories are handled without a recursive flag.

## lium rsync

Synchronize a local directory to pods. Takes no options.

```bash
lium rsync TARGETS LOCAL_PATH [REMOTE_PATH]
  TARGETS           Pod name, index, list, or "all"
  LOCAL_PATH        Local directory to sync
  REMOTE_PATH       Destination path
```

## lium rm

Remove/stop pods. **No `-y` flag** — use `echo "y" |` for non-interactive usage.

```bash
lium rm [TARGETS] [OPTIONS]
  TARGETS           Pod name(s), indices, or "all"
  -a, --all         Remove all active pods
  --in TEXT         Schedule the removal after a duration (e.g. 2h)
  --at TEXT         Schedule the removal at a time
```

**Agent usage** (non-interactive):
```bash
echo "y" | lium rm my-pod       # single pod
echo "y" | lium rm -a           # all pods
echo "y" | lium rm 1,2,3        # multiple by index
```

## lium templates

List available Docker templates. No `--format json` support.

```bash
lium templates [SEARCH]
  SEARCH            Text search to filter templates (e.g. "pytorch", "tensorflow")
```

**Notes**:
- Without `--template_id` in `lium up`, the default **PyTorch (CUDA)** template is used — fastest to start
- Default Docker-in-Docker (dind) image: `daturaai/dind`

## lium balance

Show the account balance.

```bash
lium balance [OPTIONS]
  --json            Print machine-readable JSON
```

## lium fund

Fund the account with TAO from a Bittensor wallet. **Always use `-y` for agent use.**

```bash
lium fund [OPTIONS]
  -w, --wallet NAME   Wallet name (REQUIRED for non-interactive)
  -a, --amount AMOUNT Amount of TAO (REQUIRED for non-interactive)
  -k, --hotkey NAME   Hotkey on the coldkey
  --alpha             Fund with alpha instead of TAO
  --json              Print machine-readable JSON
  -y, --yes           Skip confirmation (REQUIRED for agent use)
```

## lium topup

Fund the account with crypto — no Bittensor wallet needed.

```bash
lium topup currencies [OPTIONS]
  --refresh           Bypass the cached currency list
  --json              Print machine-readable JSON

lium topup create [OPTIONS]
  -a, --amount AMOUNT   Amount in USD
  -c, --currency CODE   Currency to pay in
  -n, --network NAME    Network for that currency
  --json                Print machine-readable JSON
```

## lium config

Manage configuration.

```bash
lium config show                          # display all config
lium config get api.api_key               # get specific value
lium config set ssh.key_path ~/.ssh/key   # set value
lium config unset KEY                     # remove a key
lium config path                          # path to the config file
lium config edit                          # open in editor
lium config reset --confirm               # wipe all configuration
```

## lium logs

Stream pod logs.

```bash
lium logs POD_ID [OPTIONS]
  -f, --follow      Follow log output
  -n, --tail NUM    Number of lines to show
```

## lium port-forward

Forward a local port to a pod. Useful for Jupyter, TensorBoard or any web service.

```bash
lium port-forward TARGET PORT [OPTIONS]
  TARGET              Pod name, huid or index
  PORT                Port inside the pod to forward
  -l, --local-port N  Local port to bind (default: same as PORT)
```

Examples:
```bash
lium port-forward my-pod 8888    # forward Jupyter (localhost:8888)
lium port-forward my-pod 6006 -l 16006
```

## lium reboot

Reboot pods. A reboot **recreates** the pod: the ephemeral filesystem is lost, only
attached volumes survive.

```bash
lium reboot [TARGETS] [OPTIONS]
  TARGETS             Pod name(s), indices, or "all"
  -a, --all           Reboot all active pods
  --volume-id ID      Attach this volume on reboot
```

## lium update

Update a running pod — currently installs Jupyter.

```bash
lium update TARGET [OPTIONS]
  --jupyter           Install Jupyter Notebook on the pod
```

## lium volumes

Manage persistent volumes.

```bash
lium volumes list                        # list all volumes
lium volumes new NAME [OPTIONS]          # create volume
  -d, --desc DESCRIPTION
lium volumes rm INDICES [OPTIONS]        # delete volumes by index from `volumes list`
  -y, --yes
```

## lium bk (backups)

Manage pod backups. The pod is a positional argument; everything else is a flag.

```bash
lium bk show POD_ID                        # show backup config
lium bk set POD_ID [OPTIONS]               # configure auto-backups
  --path PATH                              # directory to back up
  --every HOURS                            # backup frequency
  --keep DAYS                              # retention
  -y, --yes
lium bk now POD_ID [OPTIONS]               # trigger immediate backup
  -n, --name NAME
  -d, --description TEXT
lium bk logs [POD_ID] [--id ID]            # backup logs
lium bk restore POD_ID [OPTIONS]           # restore from a backup
  --id ID                                  # backup id to restore
  --to PATH                                # restore destination
  -y, --yes
lium bk restore-logs [POD_ID] [--id ID]    # restore logs
lium bk rm POD_ID [-y]                     # remove backup config
```

## lium schedules

Manage scheduled terminations.

```bash
lium schedules list            # list scheduled terminations
lium schedules rm INDICES      # cancel by index from `schedules list`
```

## lium ssh-keys

Manage the SSH keys registered with Lium.

```bash
lium ssh-keys list             # keys registered on the account
lium ssh-keys sync             # register the local public key
```

## lium theme

Set the CLI color theme. The theme name is required.

```bash
lium theme THEME_NAME
```

Available: `dark`, `light`.

## Batch Operations

Many commands support batch operations via comma-separated targets or `all`:

```bash
lium exec 1,2,3 "apt update"
lium exec all "nvidia-smi"
lium scp all ./requirements.txt
lium rsync all ./project
```

## Pod Targeting

Pods accept these identifiers:
- **Name**: `lium ssh my-pod`
- **HUID**: `lium ssh eager-wolf-aa`
- **Index**: `lium ssh 1` (from `lium ps` output — indices shift as pods change, prefer names)
- **Comma list**: `lium exec 1,2,3 "cmd"`
- **All**: `lium exec all "cmd"`

## Environment Variables

```bash
LIUM_API_KEY=xyz lium ls          # override the API key
LIUM_BASE_URL=... lium ls         # point the CLI at another backend (e.g. staging)
LIUM_DEBUG=1 lium up              # debug output
```

There is no `LIUM_SSH_KEY` — set `ssh.key_path` with `lium config set` instead.

## Exit Codes

**v0.0.27 does not have a documented exit-code contract.** Several commands report an
error and still exit `0` — for example `lium ps` on a pod id that matches nothing.
Do not use the exit code alone to decide whether a command succeeded; check the
output as well.

The contract below has landed on `main` and will apply from the next release:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | API error |
| 4 | SSH error |
| 5 | Pod not found |
| 6 | Permission denied |
