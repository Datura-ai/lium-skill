# Lium Python SDK Reference

Written against `lium.io` **0.0.37** (`lium/sdk/client.py`, tag `v0.0.37`). Signatures below are
copied from the source; when in doubt, `python -c "import lium, inspect; help(lium.Lium)"`
is the authority.

## Table of Contents

- [Installation & Auth](#installation--auth)
- [High-Level SDK (lium.sdk.Lium)](#high-level-sdk-liumsdklium)
- [Agent Recipe](#agent-recipe)
- [@machine Decorator](#machine-decorator)
- [Models](#models)
- [Exceptions](#exceptions)

## Installation & Auth

```bash
pip install lium.io        # CLI + SDK in one package (or: uv tool install lium.io)
```

The old `lium-sdk` package on PyPI is **deprecated** — its last release only says
"renamed to lium.io". There is no separate low-level `lium.Client` /
`lium.AsyncClient` in `lium.io`; `import lium` re-exports `lium.sdk` (`lium.Lium`
is `lium.sdk.Lium`).

Authentication is loaded by `Config.load()` in this order:

1. `LIUM_API_KEY` environment variable
2. `~/.lium/config.ini` → `[api] api_key` (written by `lium init` / `lium signup`)

`Lium()` takes **no `api_key` keyword**. To pass a key explicitly build a `Config`:

```python
from pathlib import Path
from lium.sdk import Lium, Config

lium = Lium()                                        # env var or config.ini
lium = Lium(config=Config(api_key="sk_...", ssh_key_path=Path("~/.ssh/id_ed25519").expanduser()))
```

`Config.load()` raises `ValueError("No API key found. Set LIUM_API_KEY or
~/.lium/config.ini")` when neither source has a key. The SSH private key is
auto-discovered from `~/.ssh/id_ed25519`, `~/.ssh/id_rsa`, `~/.ssh/id_ecdsa` (first
that exists); its `.pub` is what gets registered on the pod. `LIUM_BASE_URL`
(default `https://lium.io/api`) points the SDK at another backend.

---

## High-Level SDK (lium.sdk.Lium)

```python
from lium.sdk import Lium
lium = Lium()
```

Signatures follow Python notation: everything after `*` is keyword-only and raises
`TypeError` when passed positionally. `lium.exec(pod, "nvidia-smi")` fails — it has
to be `lium.exec(pod, command="nvidia-smi")`. Methods that take a `pod` want a
`PodInfo` (from `ps()` / `wait_ready()`), not an id string, unless stated.

Every HTTP call goes through one `_request` with a 30 s timeout (none for
`logs(follow=True)`). Reads (`GET`, `HEAD`, `OPTIONS`) get **up to 3 attempts with
back-off** on 429, 5xx and connection
errors; anything that mutates (`POST`, `PUT`, `PATCH`, `DELETE`) is, by default,
repeated only after a 429 — a timed-out `POST` may have succeeded server-side, and
repeating it blindly would create a second pod, template or backup. Three
idempotent POSTs opt in to the full retry (`schedule_termination`,
`backup_cancel`, `restore_cancel`); `pod_events` and the rent are sent exactly once. The rent inside `up()` is
sent exactly once with an `Idempotency-Key` header; if that request fails
(timeout, 5xx, 429), `up()` first looks for a pod with your `name` on that node
(`ps()`, 3 tries) and only re-sends when none exists. Give every pod a unique
`name` — it is what makes that lookup unambiguous — and check `ps()` before
retrying yourself.

### Discovery

| Method | Returns | Notes |
|--------|---------|-------|
| `ls(*, gpu_type=None, gpu_count=None, lat=None, lon=None, max_distance_miles=None, min_cuda_version=None)` | `list[ExecutorInfo]` | `gpu_type` is a short name (`"H200"`, `"RTX4090"`); `gpu_count` matches nodes with exactly that many GPUs. No country or price filter — filter the list yourself. |
| `get_executor(executor_id)` | `ExecutorInfo \| None` | Linear scan of `ls()` by UUID. |
| `gpu_types()` | `set[str]` | Machine names advertised by `/machines`. |
| `ps()` | `list[PodInfo]` | Your pods. `executor.price_per_hour` is the pod's billed $/h. |
| `pod(pod_id)` | `dict` | Raw `GET /pods/{id}` payload (template, executor, ports, status…). |
| `templates(filter=None, only_my=False)` | `list[Template]` | Substring match on image or name. Objects carry `.id`. |
| `get_template(template_id)` | `Template \| None` | `GET /templates/{id}`; swallows errors and returns `None`. |
| `get_template_by_image_name(image_name, image_tag)` | `Template \| None` | Exact image + tag match. |
| `default_docker_template(executor_id)` | `Template` | The PyTorch template the node's driver supports; what `lium up` uses without `-t`. |
| `get_deployment_estimate(executor_id, template_id)` | `dict` | `estimated_seconds`, `is_slow_machine`, `warning_message`, `is_cached_template`, `docker_image_size`. |

### Pod Lifecycle

| Method | Returns | Notes |
|--------|---------|-------|
| `rent(*, gpu_type, gpu_count=1, name=, template_id=, min_vram_gb=, min_cpus=, min_ram_gb=, min_disk_gb=, min_download_mbps=, max_price_per_gpu_hour=, country=, dry_run=)` | `RentResult` | **Since 0.0.39 (lium#209)** — on 0.0.37/0.0.38 (`pip show lium.io`) use `ls()` + `up(executor_id=)` below. Rent the cheapest node matching a spec in one call (the backend picks when `GET /version` lists `rent_by_spec` — production does today; against an older backend the client picks the cheapest exact match; `dry_run=True` prices without renting). `.pod`, `.executor`, `.price_per_hour`. |
| `up(*, executor_id, name="Your Pod", template_id=None, dockerfile_content=None, volume_id=None, ports=None, ssh_keys=None, ssh_name=None, enable_volume_encryption=True, backup_id=None, restore_path=None)` | `dict` | Raw rent response (`id`, `pod_name`, `status`, …). **Not** a `PodInfo` — pass it to `wait_ready`. Registers your SSH public key server-side first. `template_id` and `dockerfile_content` are mutually exclusive; `backup_id`/`restore_path` go together. Raises `ValueError` for an unknown executor or when no SSH key is found. |
| `wait_ready(pod, *, timeout=300, poll_interval=None, on_poll=None)` | `PodInfo \| None` | `pod` may be an id string, a `PodInfo` or the dict from `up()`. Polls `ps()` until `status == "RUNNING"` and `ssh_cmd` is set — every 2 s for the first 90 s, then every 10 s (`poll_interval` fixes the interval; `on_poll(pod, status, elapsed)` is called after each poll). **Returns `None` on timeout** (`timeout=None` waits until ready or failed) — the pod may still be provisioning and billing; check `ps()` and `down()` it. **Raises `PodStartError`** when the pod reaches `FAILED`, `CREATION_FAILED`, `STOPPED`, `BROKEN`, … , vanishes after being listed, or is still not listed 20 s after the first poll; the error carries `.pod`, `.status`, `.history` and `.cause` (the backend's reason). |
| `refresh_pod(pod)` | `PodInfo` | Re-read one pod (`pod` may be an id or a `PodInfo`); `LiumNotFoundError` when it is gone. |
| `pod_events(pod_id)` / `pod_failure_cause(pod_id)` | `list[dict]` / `str \| None` | The pod's event log (`GET /pods/{id}/events`) and the last failure reason in it — what `PodStartError.cause` is filled from. |
| `poll_delay(elapsed, poll_interval=None)` | `float` | Class method: the sleep `wait_ready` uses (2 s under 90 s elapsed, 10 s after). |
| `down(pod)` / `rm(pod)` | `dict` | `DELETE /pods/{id}`. Irreversible. |
| `reboot(pod, volume_id=None)` | `dict` | Re-creates the container; only the volume (`/workspace` by default) survives. |
| `logs(pod_id, *, tail=100, follow=False)` | `Generator[bytes]` | Container PID 1 output. Takes an **id string**. |
| `schedule_termination(pod, *, termination_time)` | `dict` | `termination_time` is an ISO 8601 UTC string, e.g. `"2026-09-05T18:00:00Z"`. This is what `lium up --ttl` calls. |
| `cancel_scheduled_termination(pod)` | `dict` | |
| `switch_template(pod, *, template_id)` | `PodInfo` | `PUT /pods/{id}/switch-template`. |
| `edit(pod_id, **kwargs)` | `dict` | Merges kwargs into the pod's template and `PUT`s it. |
| `install_jupyter(pod, *, jupyter_internal_port)` | `dict` | |

There is no `wait=`, `ttl=`, `verify_gpus=` or context-manager form of `up()` in
0.0.37 — compose them yourself (see [Agent Recipe](#agent-recipe)).

### Remote Execution

| Method | Returns | Notes |
|--------|---------|-------|
| `exec(pod, *, command, env=None)` | `dict` | `{"stdout", "stderr", "exit_code", "success"}`. Runs over paramiko with stdin closed. **No timeout** — wrap the remote side in `timeout 600 bash -lc '...'` when a hang would block you. Blocks until every process holding stdout/stderr exits, so detach long jobs (below). |
| `stream_exec(pod, *, command, env=None)` | `Generator[dict]` | Yields `{"type": "stdout"\|"stderr", "data": str}` with a PTY. |
| `exec_all(pods, *, command, env=None, max_workers=10)` | `list[dict]` | Threaded `exec` across pods; each result carries `"pod"`. |
| `ssh(pod, *, refresh=False)` | `str` | `ssh -i <key> -p <port> -o StrictHostKeyChecking=accept-new -o 'UserKnownHostsFile="/home/<you>/.lium/known_hosts/<pod id>"' root@<host>` — a ready command line with the pod's host key pinned. `refresh=True` re-reads the pod first. |
| `ssh_argv(pod)` | `list[str]` | The same command as an argument list for `subprocess`. |
| `ssh_connection(pod, timeout=30)` | context manager → `paramiko.SSHClient` | For SFTP or custom channels. Pins the host key the same way; a changed key raises `LiumHostKeyError` (`LIUM_SSH_INSECURE=1` disables the check). |

`env` values are exported with `export NAME=<shlex.quote(value)>`, so any value is
safe (spaces, quotes, `$`).

### File Transfer

| Method | Returns | Notes |
|--------|---------|-------|
| `scp(pod, *, local, remote)` / `upload(pod, *, local, remote)` | `None` | SFTP **single file**, local → pod. `remote` must be a file path, not a directory. |
| `download(pod, *, remote, local)` | `None` | SFTP single file, pod → local. |
| `rsync(pod, *, local, remote)` | `None` | `rsync -avz` **local → pod only** over the pinned-host-key `ssh`; raises `RuntimeError` on failure. No download direction, no `--bwlimit`, and `-z` is always on. |
| `get_default_images(gpu_model, driver_version)` | `list[dict]` | The default images the backend offers for a GPU model + driver (`GET /executors/default-docker-image`). |

For directories coming **back**, or for bandwidth-limited / resumable transfers,
call `rsync` yourself with `pod.host`, `pod.ssh_port` and `lium.config.ssh_key_path`
(recipe below).

### Templates, Volumes, Backups

| Method | Notes |
|--------|-------|
| `create_template(name, docker_image, docker_image_digest="", docker_image_tag="latest", ports=None, start_command=None, **kwargs)` | Positional-friendly. kwargs: `category` (default `"UBUNTU"`), `is_private` (`True`), `volumes` (`["/workspace"]`), `description`, `environment`, `entrypoint`, `one_time_template`, `readme`. Image must be Debian/Ubuntu-based (verification installs `openssh-server` with apt). |
| `update_template(template_id, name, docker_image, docker_image_digest, docker_image_tag="latest", ports=None, start_command=None, **kwargs)` | Only your own templates; triggers re-verification. |
| `wait_template_ready(template_id, timeout=300)` | `Template` on `VERIFY_SUCCESS`, `None` on timeout, raises `LiumError` on `VERIFY_FAILED`. |
| `volumes()`, `volume(volume_id)`, `volume_create(name, *, description="")`, `volume_update(volume_id, *, name=None, description=None)`, `volume_delete(volume_id)` | `VolumeInfo` objects. |
| `backup_create(pod, *, path, frequency_hours=6, retention_days=7)` | `path` is required; warns when it equals the whole volume. |
| `backup_now(pod, *, name, description="")` | Immediate backup. |
| `backup_config(pod)`, `backup_list()`, `backup_logs(pod)`, `backup_logs_all()`, `backup_log(backup_id)` | Config and history. |
| `backup_delete(config_id)`, `backup_cancel(backup_id)`, `backup_log_delete(backup_id)` | Remove the config / cancel an active backup / delete a completed backup's data. |
| `restore(pod, *, backup_id, restore_path=None)` | Default `restore_path` is `pod.default_restore_path` (`<volume>/restored`). |
| `restore_logs(pod)`, `restore_cancel(restore_id)` | |
| `resolve_backup_id(short)`, `resolve_restore_id(short)` | Expand the 8-char ids the CLI prints. |

### Account

| Method | Returns | Notes |
|--------|---------|-------|
| `balance()` | `float` | USD, from `GET /users/me`. Raises `LiumAuthError` on a bad key — the cheapest auth check. |
| `get_my_user_id()` | `str` | |
| `list_ssh_keys()` / `register_ssh_key(*, name, public_key)` | `list[SSHKey]` / `SSHKey` | `up()` calls this for you. |
| `topup_currencies(refresh=False)` | `list[dict]` | Stablecoin `{code, network, …}` pairs. |
| `topup_create_invoice(amount, crypto_currency, crypto_network)` | `dict` | `deposit_address`, `crypto_amount`, `expires_at`, … |
| `wallets()`, `add_wallet(bt_wallet)`, `convert_alpha(usd)`, `company_wallet(app_id)` | | Bittensor funding plumbing used by `lium fund`. |

---

## Agent Recipe

Everything an autonomous run needs, with the safety rails the SDK does not add
on its own: unique name, TTL, GPU-count check, detached job, resumable pull,
guaranteed teardown.

```python
import shlex, subprocess, time, uuid
from datetime import datetime, timedelta, timezone
from lium.sdk import Lium, LiumError, PodStartError

lium = Lium()
name = f"job-{uuid.uuid4().hex[:6]}"          # unique: lets you find it in ps() after a timeout
want = 8

nodes = [e for e in lium.ls(gpu_type="H200", gpu_count=want) if e.tier != "spot"]
if not nodes:
    raise SystemExit("no matching node")
node = min(nodes, key=lambda e: e.price_per_gpu)
# Since 0.0.39 (lium#209): the same in one call, no listing
#   rented = lium.rent(gpu_type="H200", gpu_count=want, name=name)
#   pod = lium.wait_ready(rented.pod, timeout=600)

pod = None
try:
    created = lium.up(executor_id=node.id, name=name)
    try:
        pod = lium.wait_ready(created, timeout=600)
    except PodStartError as exc:                 # FAILED / CREATION_FAILED / vanished: dead, not slow
        pod = exc.pod                            # may still be listed — the finally removes it
        raise LiumError(f"pod failed to start: {exc.status}; cause: {exc.cause}") from exc
    if pod is None:                              # still billing — find it and stop it
        pod = next((p for p in lium.ps() if p.name == name), None)
        raise LiumError("pod did not become ready")

    # TTL — the equivalent of `lium up --ttl 4h`
    until = (datetime.now(timezone.utc) + timedelta(hours=4)).strftime("%Y-%m-%dT%H:%M:%SZ")
    lium.schedule_termination(pod, termination_time=until)

    # Verify what you pay for: billed count vs devices the container can see.
    # pod.gpu_count is the pod row's own count (a GPU-split rental bills a share of
    # the node); executor.gpu_count is the whole host.
    billed = pod.gpu_count if pod.gpu_count is not None else (pod.executor.gpu_count if pod.executor else None)
    seen = int(lium.exec(pod, command="nvidia-smi -L | wc -l")["stdout"].strip() or 0)
    if seen != want or (billed is not None and billed != want):
        raise LiumError(f"GPU count mismatch: requested {want}, billed {billed}, visible {seen}")

    # Detached job — exec() would otherwise block until the job ends
    job = "cd /workspace && python train.py"
    r = lium.exec(pod, command=(
        "mkdir -p /workspace/logs && nohup setsid bash -lc "
        + shlex.quote(job) + " > /workspace/logs/train.log 2>&1 < /dev/null & echo $!"))
    pid = int(r["stdout"].strip())

    while lium.exec(pod, command=f"kill -0 {pid}")["success"]:
        time.sleep(60)
        print(lium.exec(pod, command="tail -n 3 /workspace/logs/train.log")["stdout"])

    # Pull results: rsync back, resumable, no compression for binary output.
    # ssh_argv() carries -i, -p and the pinned host key; drop the trailing user@host.
    ssh = shlex.join(lium.ssh_argv(pod)[:-1])
    subprocess.run(["rsync", "-a", "--partial", "--inplace", "--bwlimit=20000", "-e", ssh,
                    f"{pod.username}@{pod.host}:/workspace/out/", "./out/"], check=True)
finally:
    if pod is not None:
        lium.down(pod)                           # always; the TTL is only the backstop
```

Notes:

- `exec(..., command="kill -0 PID")` is a cheap liveness probe; `tail -n` the log
  file rather than streaming it.
- For pod-to-pod copies (edit on a cheap pod after an 8-GPU render), rsync from
  inside the source pod to the destination's `host:port`; the destination must
  trust the source's SSH key — generate one on the source with `ssh-keygen -N ""`
  and append its `.pub` to the destination's `~/.ssh/authorized_keys` via `exec`.
- Keep `HF_HOME=/workspace/hf` and venvs under `/workspace` — `/root` is an
  encrypted FUSE mount and is slow for large files (details in the skill).

---

## @machine Decorator

Run one Python function on a GPU pod: rents the cheapest node matching `machine`, ships the function's `def`, installs `requirements` once per pod (on top of the image's own packages — torch is already there on the PyTorch template), streams the function's stdout/stderr live, returns the result or re-raises the remote exception, removes the pod or keeps it warm.

**Since 0.0.40 (lium#208, DAH-3014).** On 0.0.37–0.0.39 the decorator takes only `machine`, `template_id`, `cleanup` and `requirements`, and its `requirements` go into a plain `python3 -m venv` that does **not** see the image's packages — list torch and every other import there; `timeout`, `keep_warm`, `quiet`, `local`, `.map`/`.local`/`.close`, the venv that sees the image's packages and the result/error semantics below need 0.0.40 — the example as written raises `TypeError` on the older releases.

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

| Parameter | Type | Description |
|-----------|------|-------------|
| `machine` | str | `"<count>x<gpu>"` or `"<gpu>"`: `"1xH200"`, `"RTX4090"`, `"2xA100"`. Count defaults to 1. Cheapest matching node is rented. |
| `requirements` | list, optional | pip packages, installed once per pod into a venv that also sees the image's packages |
| `template_id` | str, optional | Docker template to rent with (default: the node's default template) |
| `timeout` | float, default 3600 | seconds the function may run; `None` = no process limit. Pod removal is scheduled at `timeout + 15 min` (plus `keep_warm`), or 24 h when `timeout=None` |
| `keep_warm` | float, default 0 | seconds the pod stays after a call for the next one (also from the next run of the script); removal re-armed to `keep_warm + 2 min` after each call |
| `cleanup` | bool, default True | `False` skips the `down()` after the call; the pod still goes at its scheduled removal time |
| `local` | bool, default False | run in-process (`LIUM_MACHINE_LOCAL=1` does it for every function; since 0.0.40, lium#208) |
| `quiet` | bool, default False | suppress the `[lium]` progress lines on stderr |

**On the decorated function:** `f.remote(*a)` (= `f(*a)`), `f.local(*a)`, `f.map(iterable)` (one item per call, all on one pod), `f.close()`.

**What travels:** only the function's own `def` (decorators/annotations stripped) plus pickled arguments (your bytes, loaded on your pod). The result is not pickled: it comes back as a JSON envelope plus an `.npz` sidecar for numpy arrays, read with `allow_pickle=False`. What round-trips, each as its own type: `None`, `bool`, `int`, `float`, `str`, `bytes`; `list`, `tuple`, `set`, `frozenset`, `dict` of those, nested; `datetime`/`date`/`time`/`timedelta`, `Decimal`, `pathlib.Path`, `uuid.UUID`; `numpy.ndarray` (any dtype without Python objects) and numpy scalars. Anything else — a tensor, `torch.__version__`, a dataclass, an `Enum` — is a `lium.ResultEncodingError` raised on the pod naming the type; return `str(...)`, `.tolist()`, `.cpu().numpy()`, `dict(x)` instead. Import inside the body; a closure variable or a module-level name used inside is refused when the function is decorated (`LiumError` naming it). Nested functions and `async def` work; lambdas do not, and a method's `self` is pickled by reference, so it works only when its class is importable on the pod (not a class defined in the script).

**Errors:** a remote exception of a builtin type (`ValueError`, `RuntimeError`, …) is re-raised with its own type and `e.__cause__` is `lium.RemoteExecutionError` with `exception_type`, `remote_traceback`, `exit_code`, `stdout`, `stderr`; any other class (`torch.OutOfMemoryError`, …) arrives as `RemoteExecutionError` itself, its name in `exception_type`, no `__cause__`. Timeout → `RemoteExecutionError: <fn> exceeded timeout=Ns and was killed`, no `__cause__`; no matching node or a failed rental → `LiumError`. Prints from the pod appear on the caller's terminal while the function runs.

**Progress lines (stderr):**
```
[lium] run: renting 1xH200 $2.75/h (swift-fox-c8, United States), removal in 0.6h
[lium] run: pod ready in 45s
[lium] run: preparing environment (2 package(s): transformers, accelerate)
[lium] run: environment ready in 31s
[lium] run: running
[lium] run: done in 118s (~$0.0901)
[lium] run: pod stays warm 300s
```

Measured (6 Sep 2026, 1×RTX 4090 at $0.30/h): cold call ~70 s (~$0.006), warm call ~19 s, `transformers`+`accelerate` install 32 s once per pod. **Everything above except `machine`, `template_id`, `cleanup` and `requirements` needs 0.0.40 (lium#208, DAH-3014)**: on 0.0.37–0.0.39 the decorator takes only those four, picks the first node whose name contains `machine` as a substring (`"H200"` — the `"<count>x<gpu>"` form matches nothing there), installs `requirements` into an isolated venv (torch included, if the function needs it), has no `timeout`/`keep_warm`/`local`/`quiet`, no `.map`/`.local`/`.close`, and results must be JSON-serialisable.


---

## Models

Plain dataclasses (`lium.sdk.models`). Convert with `dataclasses.asdict(obj)`.

### ExecutorInfo

| Field | Type | Description |
|-------|------|-------------|
| `id` | `str` | Executor UUID (pass to `up(executor_id=…)`) |
| `huid` | `str` | Human-readable id derived from the UUID (`cosmic-hawk-f2`) |
| `machine_name` | `str` | Full machine name, e.g. `NVIDIA H200` |
| `gpu_type` | `str` | Short type parsed from the name (`H200`, `RTX4090`, …) |
| `gpu_count` | `int` | GPUs on the node |
| `price_per_hour` | `float` | USD/h for the whole node |
| `price_per_gpu` | `float` | USD/h per GPU |
| `location` | `dict` | `{"country": ..., "country_code": ..., ...}` when known |
| `specs` | `dict` | Raw specs: `gpu.details[].name`, `gpu.driver`, `ram`, `hard_disk`, … |
| `status` | `str` | |
| `docker_in_docker` | `bool` | sysbox runtime available |
| `ip` | `str` | Executor IP |
| `available_port_count` | `int \| None` | |
| `effective_upload_speed_mbps` / `effective_download_speed_mbps` | `float \| None` | Also as properties `upload_speed` / `download_speed` (0.0 when unknown) |
| `max_cuda_version` | `float \| None` | Driver's CUDA ceiling, e.g. `13.0` |
| `tier` | `str \| None` | `"secure"` or `"spot"` (reclaimable) |
| `available_gpu_count` | `int \| None` | GPUs still free on a node that is partly rented (GPU splitting); `None` when the API did not say |

Properties: `driver_version` (str), `gpu_model` (first GPU's full name from specs).

### PodInfo

| Field | Type | Description |
|-------|------|-------------|
| `id` | `str` | Pod UUID |
| `name` | `str` | Pod name (`pod_name` in the API) |
| `status` | `str` | `PENDING`, `RUNNING`, `FAILED`, `CREATION_FAILED`, … |
| `huid` | `str` | Human-readable id |
| `ssh_cmd` | `str \| None` | `ssh root@<host> -p <port>` once ready |
| `ports` | `dict` | Internal → external port map |
| `created_at` / `updated_at` | `str` | ISO timestamps |
| `executor` | `ExecutorInfo \| None` | The node; `executor.gpu_count` is the **whole host's** GPU count, `executor.price_per_hour` the billed $/h |
| `gpu_count` | `int \| None` | The **billed** GPU count — the pod row's own `gpu_count` from `/pods` (a GPU-split rental takes a share of the node); `None` on an older backend, fall back to `executor.gpu_count` |
| `estimated_ready_seconds`, `eta_basis`, `phase` | `int \| None`, `str \| None`, `str \| None` | The backend's readiness estimate while the pod starts; the method `pod.eta_hint()` renders them as one line (`est. ready in ~18 s (phase: pulling image)`), `None` when absent |
| `template` | `dict` | Raw template payload (`id`, `name`, `docker_image`, `volumes`, …) |
| `removal_scheduled_at` | `str \| None` | TTL / scheduled termination |
| `jupyter_installation_status`, `jupyter_url` | `str \| None` | |
| `enable_volume_encryption`, `volume_encryption_status` | `bool \| None`, `str \| None` | |

Properties: `host`, `username`, `ssh_port` (parsed from `ssh_cmd`; `ssh_port`
defaults to 22), `volume_path` (first template volume, default `/root`),
`default_restore_path` (`<volume>/restored`). There is **no** `started_at`,
`restart_count` or `spend_to_date` — the API does not expose them yet; compute
spend as `(now − created_at) × executor.price_per_hour` like `lium ps` does.

### Template

| Field | Type |
|-------|------|
| `id`, `huid`, `name` | `str` |
| `docker_image`, `docker_image_tag` | `str` |
| `category` | `str` (`PYTORCH`, `UBUNTU`, `DOCKER`, …) |
| `status` | `str` (`VERIFY_SUCCESS`, `VERIFY_PENDING`, `VERIFY_FAILED`, …) |

### VolumeInfo

`id`, `huid`, `name`, `description`, `created_at`, `updated_at`,
`current_size_bytes`, `current_file_count`, `current_size_gb`, `current_size_mb`,
`last_metrics_update`.

### BackupConfig / BackupLog / RestoreLog / SSHKey

- `BackupConfig`: `id`, `huid`, `pod_executor_id`, `backup_frequency_hours`,
  `retention_days`, `backup_path`, `is_active`, `created_at`, `updated_at`.
- `BackupLog`: `id`, `huid`, `backup_config_id`, `status`, `started_at`,
  `completed_at`, `error_message`, `progress`, `stage`, `total_bytes`,
  `processed_bytes`, `throughput_bytes_per_second`, `estimated_remaining_seconds`, …
- `RestoreLog`: `id`, `huid`, `backup_id`, `pod_id`, `status`, `progress`,
  `restore_path`, `stage`, `error_message`, …
- `SSHKey`: `id`, `name`, `public_key`, `created_at`.

---

## Exceptions

All in `lium.sdk` (and re-exported from `lium`):

| Exception | Trigger |
|-----------|---------|
| `LiumError` | Base class; also raised for unmapped HTTP errors (`API error <code>: …`) and when `up()` cannot find the pod it created |
| `LiumAuthError` | 401 — invalid or revoked API key |
| `LiumPermissionError` | 403 — `Permission denied: Insufficient balance` is the common one |
| `LiumNotFoundError` | 404 |
| `LiumRateLimitError` | 429 (retried 3× first for every call except the rent POST inside `up()` and `pod_events()`, which are sent once) |
| `LiumServerError` | 5xx (retried 3× first for `GET`/`HEAD`/`OPTIONS` and the three `retry=True` POSTs named above; raised at once for any other mutating call) |
| `PodStartError` | `wait_ready()`: the pod reached a terminal status or vanished; carries `.pod_id`, `.pod`, `.status`, `.history`, `.cause` |
| `RemoteExecutionError` | an `@lium.machine` call returned no result: carries `exception_type`, `remote_traceback`, `exit_code`, `stdout`, `stderr`; builtin exceptions re-raise with it as `__cause__` (since 0.0.40, lium#208) |
| `ResultEncodingError` | (a `TypeError`) the function's return value is not in the round-trip list — JSON scalars/containers, bytes, numpy arrays (since 0.0.40, lium#208) |
| `LiumHostKeyError` | `ssh_connection()` (so `exec()`, `scp()`, …): the pod's SSH host key differs from the one pinned under `~/.lium/known_hosts/<pod id>` (`LIUM_SSH_INSECURE=1` disables the check) |

`ValueError` (not a `LiumError`) is raised for local problems: no API key, no SSH
key, unknown executor id, conflicting arguments. `RuntimeError` comes from
`rsync()`. paramiko exceptions (`paramiko.SSHException`, `socket.timeout`)
surface unchanged from `exec()`/`scp()`.

The 403 message does not say which key or account was used. When `balance()`
works but `up()` says `Insufficient balance`, check that both processes resolve
the same key (`LIUM_API_KEY` beats `~/.lium/config.ini`).

Debugging: the SDK has no debug switch of its own (`LIUM_DEBUG=1` is read by the CLI's UI only); what remains is

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```
