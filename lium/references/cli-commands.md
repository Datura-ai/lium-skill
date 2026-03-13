# Lium CLI Command Reference

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
- [lium fund](#lium-fund)
- [lium config](#lium-config)
- [lium logs](#lium-logs)
- [lium port-forward](#lium-port-forward)
- [lium reboot](#lium-reboot)
- [lium volumes](#lium-volumes)
- [lium bk (backups)](#lium-bk-backups)
- [lium schedules](#lium-schedules)
- [lium theme](#lium-theme)
- [Batch Operations](#batch-operations)
- [Pod Targeting](#pod-targeting)
- [Environment Variables](#environment-variables)
- [Exit Codes](#exit-codes)

## Global Options

```
--help        Show help message
--version     Display CLI version
--config PATH Use alternate config file
--debug       Enable debug output
```

## lium init

Interactive setup wizard. **NOT suitable for agent/scripted use** — has no non-interactive flags.

For agent setup, write config directly:
```bash
mkdir -p ~/.lium
lium config set api.api_key YOUR_KEY
lium config set ssh.key_path ~/.ssh/id_ed25519
```

## lium ls

List available GPU nodes.

```bash
lium ls [GPU_TYPE] [OPTIONS]
  GPU_TYPE          Filter by GPU type (H100, A100, RTX4090, H200, etc.)
  --region REGION   Filter by region
  --min-memory GB   Minimum GPU memory
  --max-price USD   Maximum price per hour
  --format FORMAT   Output format (table, json, csv)
```

Examples:
```bash
lium ls                    # all nodes
lium ls H100              # only H100 GPUs
lium ls --max-price 2.5   # under $2.50/hour
lium ls --format json     # JSON output for parsing
```

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
  -e, --env KEY=VALUE         Environment variables (repeatable)
  --cmd TEXT                  Command to run in container
  --entrypoint TEXT           Container entrypoint
  --internal-ports TEXT       Internal ports to expose (comma-separated)
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
lium ps [OPTIONS]
  -a, --all         Show all pods including stopped
  --format FORMAT   Output format (table, json, csv)
  --sort FIELD      Sort by field (name, status, cost, uptime)
```

## lium ssh

SSH into a pod.

```bash
lium ssh POD [OPTIONS]
  POD               Pod name or index from lium ps
  --command CMD     Execute command and exit
  --port PORT       SSH port (default: 22)
  --key PATH        Use specific SSH key
```

## lium exec

Execute command on pod(s).

```bash
lium exec POD COMMAND [OPTIONS]
  POD               Pod name, index, comma-separated list, or "all"
  COMMAND           Command to execute (quote multi-word commands)
  --timeout SECONDS Command timeout
  --output FILE     Save output to file
```

Examples:
```bash
lium exec my-pod "python train.py"
lium exec 1 "nvidia-smi" --output gpu.txt
lium exec all "pip install numpy"
```

## lium scp

Copy files to/from pods.

```bash
lium scp POD LOCAL_FILE [REMOTE_PATH] [OPTIONS]
  POD               Pod name, index, comma-separated list, or "all"
  LOCAL_FILE        Local file to copy
  REMOTE_PATH       Destination path (default: /root/)
  -r, --recursive   Copy directories recursively
  -p, --preserve    Preserve file attributes
  -d                Download mode (pod → local)
```

Examples:
```bash
lium scp my-pod ./script.py                 # upload to /root/
lium scp 1 ./data.csv /root/datasets/       # specific destination
lium scp all ./config.json                  # upload to all pods
lium scp my-pod ./folder -r                 # directory upload
```

## lium rsync

Synchronize directories to pods.

```bash
lium rsync POD LOCAL_DIR [REMOTE_PATH] [OPTIONS]
  POD               Pod name, index, list, or "all"
  LOCAL_DIR         Local directory to sync
  REMOTE_PATH       Destination path
  --delete          Delete files not in source
  --exclude PATTERN Exclude files matching pattern
  --dry-run         Show what would be synced
```

## lium rm

Remove/stop pods. **No `-y` flag** — use `echo "y" |` for non-interactive usage.

```bash
lium rm POD [POD...] [OPTIONS]
  POD               Pod name(s), indices, or "all"
  -a, --all         Remove all pods
  --in TEXT          Remove pods matching name pattern
  --at TEXT          Remove pods on specific executor
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

## lium fund

Fund account with TAO from Bittensor wallet. **Always use `-y` for agent use.**

```bash
lium fund [OPTIONS]
  -w, --wallet NAME   Wallet name (REQUIRED for non-interactive)
  -a, --amount AMOUNT Amount of TAO (REQUIRED for non-interactive)
  -y, --yes           Skip confirmation (REQUIRED for agent use)
```

## lium config

Manage configuration.

```bash
lium config show                         # display all config
lium config get api.api_key             # get specific value
lium config set ssh.key_path ~/.ssh/key  # set value
lium config edit                         # open in editor
```

## lium logs

Stream pod logs.

```bash
lium logs POD [OPTIONS]
  -f              Follow log output
  -n NUM          Number of lines to show
```

## lium port-forward

Forward local port to pod. Useful for accessing Jupyter, TensorBoard, or other web services.

```bash
lium port-forward POD PORT [OPTIONS]
  POD   Pod name or index
  PORT  Remote port to forward
```

Examples:
```bash
lium port-forward my-pod 8888    # forward Jupyter (localhost:8888)
lium port-forward 1 6006         # forward TensorBoard
```

## lium reboot

Reboot a pod.

```bash
lium reboot POD [OPTIONS]
  -v, --volume SPEC  Attach volume on reboot
```

## lium volumes

Manage persistent volumes.

```bash
lium volumes list                        # list all volumes
lium volumes new NAME [OPTIONS]          # create volume
  --desc DESCRIPTION
lium volumes rm VOLUME                   # delete volume
```

## lium bk (backups)

Manage pod backups.

```bash
lium bk show POD              # show backup config
lium bk set POD PATH          # configure auto-backups
lium bk now POD               # trigger immediate backup
lium bk logs POD              # view backup logs
lium bk restore POD BACKUP_ID # restore from backup
lium bk rm POD                # remove backup config
```

## lium schedules

Manage scheduled terminations.

```bash
lium schedules list            # list scheduled terminations
lium schedules rm POD          # cancel scheduled termination
```

## lium theme

Change CLI color theme.

```bash
lium theme [THEME]   # interactive if no theme specified
```

Available: default, monokai, solarized, dracula, nord.

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
- **Index**: `lium ssh 1` (from `lium ps` output)
- **Comma list**: `lium exec 1,2,3 "cmd"`
- **All**: `lium exec all "cmd"`

## Environment Variables

```bash
LIUM_API_KEY=xyz lium ls       # override API key
LIUM_SSH_KEY=/tmp/key lium ssh my-pod
LIUM_DEBUG=1 lium up           # debug output
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | API error |
| 4 | SSH error |
| 5 | Pod not found |
| 6 | Permission denied |
