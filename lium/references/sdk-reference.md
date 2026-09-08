# Lium Python SDK Reference

## Table of Contents

- [Installation & Auth](#installation--auth)
- [High-Level SDK (lium.sdk.Lium)](#high-level-sdk-liumsdklium)
- [@machine Decorator](#machine-decorator)
- [Low-Level SDK (lium.Client)](#low-level-sdk-liumclient)
- [Models](#models)
- [Exceptions](#exceptions)

## Installation & Auth

```bash
pip install lium.io      # CLI + high-level SDK
pip install lium-sdk     # low-level SDK only
```

Authentication (auto-loaded in priority order):
1. Direct: `Lium(api_key="...")` or `Client(api_key="...")`
2. Environment: `LIUM_API_KEY`
3. Config file: `~/.lium/config.ini` (set via `lium init`)

SSH keys auto-discovered from `~/.ssh/id_ed25519`, `~/.ssh/id_rsa`, `~/.ssh/id_ecdsa`.

---

## High-Level SDK (lium.sdk.Lium)

Full-featured SDK included with `pip install lium.io`. Mirrors CLI capabilities.

```python
from lium.sdk import Lium
lium = Lium()
```

Signatures below follow Python notation: everything after `*` is keyword-only and
raises `TypeError` when passed positionally. `lium.exec(pod, "nvidia-smi")` fails —
it has to be `lium.exec(pod, command="nvidia-smi")`.

### Discovery

| Method | Description |
|--------|-------------|
| `ls(*, gpu_type=, gpu_count=, lat=, lon=, max_distance_miles=)` | List available executors |
| `ps()` | List active pods |
| `pod(pod_id)` | Get pod details |
| `get_executor(executor_id)` | Get executor details |
| `templates(filter=, only_my=)` | List templates |
| `gpu_types()` | List available GPU types |

### Pod Lifecycle

| Method | Description |
|--------|-------------|
| `rent(*, gpu_type, gpu_count=1, name=, template_id=, min_vram_gb=, min_cpus=, min_ram_gb=, min_disk_gb=, min_download_mbps=, max_price_per_gpu_hour=, country=, dry_run=)` | **Coming with lium#209 — not in 0.0.37, the latest release** (`pip show lium.io`; until it ships use `ls()` + `up(executor_id=)` below). Rent the cheapest node matching a spec in one call (the backend picks when `GET /version` lists `rent_by_spec` — production does today; against an older backend the client picks the cheapest exact match; `dry_run=True` prices without renting). Returns `RentResult` with `.pod`, `.executor`, `.price_per_hour` |
| `up(*, executor_id, name=, template_id=, volume_id=, ports=, ssh_keys=)` | Create pod on a named node |
| `down(pod)` | Stop/delete pod |
| `rm(pod)` | Alias for `down()` |
| `reboot(pod, volume_id=)` | Reboot pod |
| `wait_ready(pod, *, timeout=)` | Poll until pod is RUNNING |
| `logs(pod_id, *, tail=, follow=)` | Stream pod logs |
| `edit(pod_id, **kwargs)` | Edit pod template |

### Remote Execution

| Method | Description |
|--------|-------------|
| `exec(pod, *, command, env=)` | Execute command, returns `{"stdout", "stderr", "exit_code", "success"}` |
| `stream_exec(pod, *, command, env=)` | Stream execution output |
| `exec_all(pods, *, command, env=, max_workers=)` | Execute on multiple pods |
| `ssh(pod)` | Get SSH command string |

### File Transfer

| Method | Description |
|--------|-------------|
| `scp(pod, *, local, remote)` | Copy file to pod |
| `upload(pod, *, local, remote)` | Upload (alias for scp) |
| `download(pod, *, remote, local)` | Download file from pod |
| `rsync(pod, *, local, remote)` | Sync directory |

### Template Management

| Method | Description |
|--------|-------------|
| `default_docker_template(executor_id)` | Get executor's default template |
| `create_template(...)` | Create custom template |
| `update_template(template_id, name=, docker_image=, ...)` | Update template |
| `switch_template(pod, *, template_id)` | Change pod's template |
| `wait_template_ready(template_id, timeout=)` | Wait for template build |

### Volume Management

| Method | Description |
|--------|-------------|
| `volumes()` | List all volumes |
| `volume(volume_id)` | Get volume info |
| `volume_create(name, *, description=)` | Create volume |
| `volume_update(volume_id, *, name=, description=)` | Update volume |
| `volume_delete(volume_id)` | Delete volume |

### Backup Management

| Method | Description |
|--------|-------------|
| `backup_create(pod, *, path=, frequency_hours=, retention_days=)` | Set up auto-backups |
| `backup_now(pod, *, name, description=)` | Trigger immediate backup |
| `backup_config(pod)` | Get backup config |
| `backup_list()` | List all backups |
| `backup_logs(pod)` | Get backup execution logs |
| `backup_delete(config_id)` | Delete backup config |
| `restore(pod, *, backup_id, restore_path=)` | Restore from backup |

### Pod Scheduling

| Method | Description |
|--------|-------------|
| `schedule_termination(pod, *, termination_time)` | Auto-terminate at specific time |
| `cancel_scheduled_termination(pod)` | Cancel auto-termination |

### Jupyter

| Method | Description |
|--------|-------------|
| `install_jupyter(pod, *, jupyter_internal_port)` | Install Jupyter on pod |

### Account

| Method | Description |
|--------|-------------|
| `balance()` | Get account balance |
| `wallets()` | List connected wallets |
| `add_wallet(bt_wallet)` | Add Bittensor wallet |
| `get_my_user_id()` | Get current user ID |

### Complete Example

```python
from lium.sdk import Lium

lium = Lium()

# lium.io 0.0.37 (the latest release): list, pick the cheapest 8xA100 yourself, rent it by id
executors = lium.ls(gpu_type="A100", gpu_count=8)
cheapest = min(executors, key=lambda e: e.price_per_hour)
pod = lium.wait_ready(lium.up(executor_id=cheapest.id, name="my-pod"), timeout=600)
# Coming with lium#209 (not in 0.0.37): the same in one call, no listing
#   rented = lium.rent(gpu_type="A100", gpu_count=8, min_cpus=32, name="my-pod")
#   pod = lium.wait_ready(rented.pod, timeout=600)

# Execute
result = lium.exec(pod, command="nvidia-smi")
print(result["stdout"])

# Files
lium.upload(pod, local="train.py", remote="/root/train.py")
lium.exec(pod, command="python /root/train.py")
lium.download(pod, remote="/root/model.pt", local="./model.pt")

# Backups
lium.backup_create(pod, path="/root/data", frequency_hours=24, retention_days=7)

# Cleanup
lium.down(pod)
```

---

## @machine Decorator

Run one Python function on a GPU pod: rents the cheapest node matching `machine`, ships the function's `def`, installs `requirements` once per pod (on top of the image's own packages — torch is already there on the PyTorch template), streams the function's stdout/stderr live, returns the pickled result or re-raises the remote exception, removes the pod or keeps it warm.

```python
import lium

@lium.machine(machine="1xH200", requirements=["transformers", "accelerate"], timeout=900, keep_warm=300)
def run(model_name: str, prompt: str) -> str:
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForCausalLM.from_pretrained(model_name, dtype=torch.bfloat16, device_map="cuda")
    ids = tok(prompt, return_tensors="pt").to("cuda")
    return tok.decode(model.generate(**ids, max_new_tokens=64)[0], skip_special_tokens=True)

answer = run("Qwen/Qwen2.5-0.5B-Instruct", "What is the capital of France?")
run.close()          # remove the warm pod now
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `machine` | str | `"<count>x<gpu>"` or `"<gpu>"`: `"1xH200"`, `"RTX4090"`, `"2xA100"`. Count defaults to 1. Cheapest matching node is rented. |
| `requirements` | list, optional | pip packages, installed once per pod into a venv that also sees the image's packages |
| `template_id` | str, optional | Docker template to rent with (default: the node's default template) |
| `timeout` | float, default 3600 | seconds the function may run; `None` = unlimited. Pod removal is scheduled at `timeout + 15 min` |
| `keep_warm` | float, default 0 | seconds the pod stays after a call for the next one (also from the next run of the script); removal re-armed to `keep_warm + 2 min` after each call |
| `cleanup` | bool, default True | `False` keeps the pod indefinitely |
| `local` | bool, default False | run in-process (`LIUM_MACHINE_LOCAL=1` does it for every function; release after 0.0.33) |
| `quiet` | bool, default False | suppress the `[lium]` progress lines on stderr |

**On the decorated function:** `f.remote(*a)` (= `f(*a)`), `f.local(*a)`, `f.map(iterable)` (one item per call, all on one pod), `f.close()`.

**What travels:** only the function's own `def` (decorators/annotations stripped) plus pickled arguments; the result comes back pickled. Import inside the body; a closure variable or a module-level name used inside is refused when the function is decorated (`LiumError` naming it). Methods, nested functions and `async def` work; lambdas do not. Return plain Python types — a tensor or `torch.__version__` would need torch installed on the caller to unpickle.

**Errors:** the remote exception is re-raised with its own type; `e.__cause__` is `lium.RemoteExecutionError` with `exception_type`, `remote_traceback`, `exit_code`, `stdout`, `stderr`. Timeout → `RemoteExecutionError: <fn> exceeded timeout=Ns and was killed`. Prints from the pod appear on the caller's terminal while the function runs.

**Progress lines (stderr):**
```
[lium] run: renting 1xH200 $2.75/h (swift-fox-c8, United States), removal in 1.5h
[lium] run: pod ready in 45s
[lium] run: preparing environment (2 package(s): transformers, accelerate)
[lium] run: environment ready in 31s
[lium] run: running
[lium] run: done in 118s (~$0.0901)
[lium] run: pod stays warm 300s
```

Measured (6 Sep 2026, 1×RTX 4090 at $0.30/h): cold call ~70 s (~$0.006), warm call ~19 s, `transformers`+`accelerate` install 32 s once per pod. Requires the `lium` release after 0.0.33.

---

## Low-Level SDK (lium.Client)

Resource-based client from `pip install lium-sdk`. Context-manager pattern.

### Sync Client

```python
import lium

with lium.Client(api_key="optional") as client:
    pods = client.pods.list()
```

### Async Client

```python
import asyncio, lium

async def main():
    async with lium.AsyncClient() as client:
        pods = await client.pods.list()

asyncio.run(main())
```

### Resources

**client.pods:**
| Method | Description |
|--------|-------------|
| `list()` → `list[PodList]` | List user's pods |
| `retrieve(id, wait_until_running=False, timeout=300)` → `Pod` | Get pod, optionally wait |
| `create(id_in_site, pod_name, template_id, user_public_key)` → `Pod` | Low-level create |
| `delete(id_in_site)` → `None` | Delete pod |
| `list_executors(filter_query=None)` → `list[Executor]` | List available machines |
| `easy_deploy(machine_query, docker_image=, dockerfile=, template_id=, pod_name=)` → `Pod` | High-level deploy |

**machine_query format for easy_deploy:**
- `"H100"` — any H100
- `"1xA6000"` — exactly 1x A6000
- `"2xA100"` — exactly 2x A100
- `"H200,A100"` — H200 or A100

**client.templates:**
| Method | Description |
|--------|-------------|
| `list()` → `list[Template]` | List templates |
| `retrieve(template_id)` → `Template` | Get template |
| `create(...)` → `Template` | Create template |
| `delete(template_id)` → `None` | Delete template |

**client.ssh_keys:**
| Method | Description |
|--------|-------------|
| `list()` → `list[SSHKey]` | List uploaded SSH keys |
| `create(name: str, public_key: str)` → `SSHKey` | Upload public key |
| `delete(key_id: UUID)` → `None` | Remove SSH key |

**client.docker_credentials:**
| Method | Description |
|--------|-------------|
| `list()` → `list[DockerCredentials]` | List stored registry credentials |
| `create(registry: str, username: str, password: str)` → `DockerCredentials` | Add registry credentials (for private images) |
| `delete(cred_id: UUID)` → `None` | Remove credentials |

---

## Models

### ExecutorInfo (high-level SDK)

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Executor identifier |
| `huid` | `str` | Human-readable ID (e.g. "cosmic-hawk-f2") |
| `gpu_type` | `str` | GPU model ("H100", "A100", etc.) |
| `gpu_count` | `int` | Number of GPUs |
| `price_per_hour` | `float` | USD per hour |
| `location` | `str` | Country/region |
| `specs` | `dict` | Hardware specs (RAM, storage, etc.) |
| `status` | `str` | Availability status |
| `docker_in_docker` | `bool` | DinD support |
| `ip` | `str` | Machine IP |

### Executor (low-level SDK)

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Executor identifier |
| `gpu_type` | `str` | GPU model |
| `gpu_count` | `int` | Number of GPUs |
| `price` | `float` | USD per hour |
| `location` | `str` | Country/region |
| `driver_version` | `str` | NVIDIA driver version |
| `docker_in_docker` | `bool` | DinD support |

### PodInfo / Pod

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Pod identifier |
| `name` | `str` | Pod name |
| `status` | `str` | "RUNNING", "STOPPED", "PENDING", etc. |
| `huid` | `str` | Human-readable ID |
| `ssh_cmd` | `str` | Ready-to-use SSH command |
| `ssh_ip` | `str` | SSH host |
| `ssh_port` | `int` | SSH port |
| `ports` | `list[dict]` | Allocated port mappings |
| `executor` | `Executor` | Associated executor info |
| `template` | `Template` | Docker template used |
| `created_at` | `datetime` | Creation timestamp |
| `removal_scheduled_at` | `datetime | None` | Scheduled termination time |
| `jupyter_url` | `str | None` | Jupyter URL if enabled |

### Template

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Template identifier |
| `name` | `str` | Template name |
| `huid` | `str` | Human-readable ID |
| `docker_image` | `str` | Docker image name |
| `docker_image_tag` | `str` | Image tag |
| `category` | `str` | Template category (ml, web, etc.) |
| `status` | `str` | Build status |

### VolumeInfo

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Volume identifier |
| `huid` | `str` | Human-readable ID |
| `name` | `str` | Volume name |
| `description` | `str` | Volume description |
| `current_size_bytes` | `int` | Current storage used |
| `current_file_count` | `int` | Number of files |

### BackupConfig

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Config identifier |
| `pod_executor_id` | `UUID` | Associated pod |
| `backup_frequency_hours` | `int` | Backup interval in hours |
| `retention_days` | `int` | Days to keep backups |
| `backup_path` | `str` | Path being backed up |
| `is_active` | `bool` | Whether backups are enabled |

---

## Exceptions

High-level SDK (`lium.sdk`):
| Exception | Trigger |
|-----------|---------|
| `LiumError` | Base exception |
| `LiumAuthError` | Invalid API key (401) |
| `LiumNotFoundError` | Resource not found (404) |
| `LiumRateLimitError` | Rate limit exceeded (429) |
| `LiumServerError` | Server errors (5xx) |

Enable debug logging:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

Or set `LIUM_DEBUG=1` environment variable.
