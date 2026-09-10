# Lium Recipes for Agents

Copy-paste jobs against the released lium CLI (0.0.37). Each one follows the playbook in
`SKILL.md`: unique name, `--ttl`, GPU-count check, `/workspace` for everything,
detached work, results pulled with `rsync`, and a teardown that is confirmed with
`lium ps`. Replace the GPU type, count and model to taste. All of them assume
`LIUM_API_KEY` is exported and `jq` is installed locally. Run each one as a script
(`bash job.sh`), not pasted into an interactive shell: the `trap teardown EXIT` that
removes the pod fires when the script ends.

Shared helpers used below:

```bash
# Remote stdout of one command, without the CLI's status line
rexec() { local out; out=$(lium exec "$1" --json "$2") || return $?; jq -r '.results[0].stdout' <<<"$out"; }   # keeps lium's exit code (5 when the pod is gone)
# Host and port of a pod's SSH endpoint
sshinfo() { lium ps "$1" --format json | jq -r '.[0].ssh_cmd | capture("@(?<h>\\S+).*-p (?<p>\\d+)") | "\(.h) \(.p)"'; }
# Rent with the built-in GPU check; when up fails after the rent was accepted (pod_not_ready
# after --timeout, a check that could not run), remove the pod so nothing keeps billing.
# Uses $NAME for the cleanup — set it and pass --name "$NAME" (every recipe below does).
rent() { lium up "$@" -y --no-ssh --verify-gpus --strict-gpus && return 0
  lium ps "$NAME" --format json >/dev/null 2>&1 && lium rm "$NAME" -y; return 1; }
# The pod's ready ssh command from lium ps --format json: -p, the pinned host key (accept-new +
# ~/.lium/known_hosts/<pod id>) and root@host; only -i is missing
sshcmd() { lium ps "$1" --format json | jq -r '.[0].ssh_command'; }
# Pull a directory from a pod (resumable, throttled, no compression): -e is the ssh command
# without its trailing root@host, plus the key — `ssh.key_path` in `lium config show`, id_ed25519
# by default ($HOME, not ~: ssh expands ~ from passwd, not $HOME)
pull() { local C; C=$(sshcmd "$1"); rsync -a --partial --inplace --progress --bwlimit="${4:-20000}" \
  -e "${C% root@*} -i $HOME/.ssh/id_ed25519" "${C##* }:$2" "$3"; }
# Is the pod gone (TTL fired, removed elsewhere)? `lium ps <name>` exits 5 for a missing pod; any other
# non-zero exit from lium is an API/SSH hiccup — the loops below retry on those, and only stop on 5.
gone() { lium ps "$1" --format json >/dev/null 2>&1; [ $? -eq 5 ]; }
# Tear the pod down however the script ends (success, a failed step, Ctrl-C): a pod left behind bills
# until its TTL. Set right after rent(); prints the number of pods still listed (0 = nothing billing).
teardown() { lium rm "$NAME" -y >/dev/null 2>&1; echo "pods left: $(lium ps --format json | jq length)"; }
```

## Table of Contents

- [Verify what you paid for](#verify-what-you-paid-for)
- [LLM serving on 8 GPUs (vLLM or SGLang)](#llm-serving-on-8-gpus-vllm-or-sglang)
- [Image/video diffusion, best-of-N, one process per GPU](#imagevideo-diffusion-best-of-n-one-process-per-gpu)
- [RL / simulation](#rl--simulation)
- [Batch data job](#batch-data-job)
- [Teardown checklist](#teardown-checklist)

## Verify what you paid for

Run this immediately after every `lium up`. It fails (and removes the pod) when
the billed GPU count or the visible GPU count is not the requested count.

```bash
#!/usr/bin/env bash
# usage: verify_gpus.sh <pod-name> <expected-count>
set -euo pipefail
POD=$1; WANT=$2
lium ps "$POD" --format json > "/tmp/$POD.json"
BILLED=$(jq -r '.[0].gpu_count' "/tmp/$POD.json")     # the node's GPU count: what a whole-node rent (-c N on a free node) is billed for
PRICE=$(jq -r '.[0].price_per_hour' "/tmp/$POD.json")   # the pod's own $/h — the billing evidence
lium exec "$POD" --json "nvidia-smi -L" > "/tmp/$POD.nvidia-smi.json"
SEEN=$(jq -r '.results[0].stdout' "/tmp/$POD.nvidia-smi.json" | grep -c '^GPU ' || true)
echo "requested=$WANT billed=$BILLED visible=$SEEN price_per_hour=$PRICE"
if [ "$BILLED" != "$WANT" ] || [ "$SEEN" != "$WANT" ]; then
  echo "GPU count mismatch — removing $POD (evidence in /tmp/$POD.*.json)" >&2
  lium rm "$POD" -y
  exit 1
fi
```

If it fails, rent again on a **different** executor: pick the `id` (the UUID;
the released CLI rejects the HUID) from `lium ls --gpu <type> --count <n> --format json`
and pass it first (`rent <id> --name ... --ttl ...`; the helper forwards it to `lium up`).
Keep the two JSON files.

## LLM serving on 8 GPUs (vLLM or SGLang)

Serves an open model behind an OpenAI-compatible endpoint, reachable through the
pod's external port map. Cold start for a 70B-class model is 10–25 minutes
(download + engine init + CUDA graph capture); do not conclude it is broken
before that.

```bash
NAME=serve-$(date +%s); MODEL=Qwen/Qwen2.5-72B-Instruct; WANT=8
rent --gpu H200 -c $WANT --name "$NAME" --ttl 8h || exit 1
trap teardown EXIT                            # from here on, every exit removes the pod
./verify_gpus.sh "$NAME" $WANT || exit 1     # it removed the pod; stop here

cat > setup.sh <<'EOF'
set -e
mkdir -p /workspace/{logs,hf}
apt-get update -qq && apt-get install -y -qq libnuma1 jq >/dev/null
python3 -m venv --system-site-packages /workspace/venv
. /workspace/venv/bin/activate
pip install -q "huggingface_hub[hf_transfer]" vllm        # vLLM wheels ship their own torch/CUDA
EOF
lium exec "$NAME" --script setup.sh

# Which internal port is mapped? Bind the server to one of them.
lium ps "$NAME" --format json | jq '.[0].ports'          # e.g. {"22": 31022, "8000": 31080}
PORT=8000

# Download weights first (detached; hf_transfer), then start the server (detached)
DLPID=$(rexec "$NAME" "cd /workspace && HF_HOME=/workspace/hf HF_HUB_ENABLE_HF_TRANSFER=1 nohup setsid /workspace/venv/bin/hf download $MODEL > /workspace/logs/download.log 2>&1 < /dev/null & echo \$!")
until rexec "$NAME" "tail -n 1 /workspace/logs/download.log" | grep -q '/workspace/hf'; do
  gone "$NAME" && { echo "pod gone (TTL or removal)"; exit 1; }
  # the remote always exits 0 here, so a failed rexec is an API/SSH hiccup (retried), not a verdict
  STATE=$(rexec "$NAME" "kill -0 $DLPID 2>/dev/null && echo running || echo exited") || STATE=unknown
  [ "$STATE" = exited ] && { echo "download exited before finishing — see /workspace/logs/download.log"; exit 1; }
  sleep 30
done

SRVPID=$(rexec "$NAME" "cd /workspace && HF_HOME=/workspace/hf nohup setsid /workspace/venv/bin/vllm serve $MODEL --tensor-parallel-size $WANT --host 0.0.0.0 --port $PORT --gpu-memory-utilization 0.92 > /workspace/logs/vllm.log 2>&1 < /dev/null & echo \$!")
# SGLang instead:
#   pip install -q "sglang[all]"  (in setup.sh)
#   ... nohup setsid /workspace/venv/bin/python -m sglang.launch_server --model-path $MODEL --tp $WANT --host 0.0.0.0 --port $PORT ...

# Wait for readiness from inside the pod, then hit it from outside
until lium exec "$NAME" "curl -sf localhost:$PORT/v1/models" >/dev/null 2>&1; do
  gone "$NAME" && { echo "pod gone (TTL or removal)"; exit 1; }
  STATE=$(rexec "$NAME" "kill -0 $SRVPID 2>/dev/null && echo running || echo exited") || STATE=unknown
  [ "$STATE" = exited ] && { echo "server exited — see /workspace/logs/vllm.log"; exit 1; }
  rexec "$NAME" "tail -n 1 /workspace/logs/vllm.log"; sleep 30
done
read -r HOST _ < <(sshinfo "$NAME"); EXT=$(lium ps "$NAME" --format json | jq -r ".[0].ports[\"$PORT\"]")
curl -s "http://$HOST:$EXT/v1/chat/completions" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":8}"

# ... run the evaluation / traffic ...
# the EXIT trap removes the pod and prints "pods left: 0"
```

Notes: `libnuma1` is needed by SGLang's kernels; Blackwell nodes need a vLLM /
SGLang build with CUDA 12.8+ (recent wheels are) — if the server dies with
`no kernel image is available`, the torch inside the venv is too old for the GPU.
Never leave a serving pod up "for later": `--ttl` is the backstop, `rm` is the plan.

## Image/video diffusion, best-of-N, one process per GPU

Generate N candidates per prompt with one worker per GPU, each pinned with
`CUDA_VISIBLE_DEVICES`. Outputs land in `/workspace/out/<gpu>/`; pull them, then
tear down. Editing, upscaling and encoding happen on a cheap pod or locally.

```bash
NAME=gen-$(date +%s); WANT=8
rent --gpu H200 -c $WANT --name "$NAME" --ttl 4h || exit 1
trap teardown EXIT
./verify_gpus.sh "$NAME" $WANT || exit 1     # it removed the pod; stop here

cat > setup.sh <<'EOF'
set -e
mkdir -p /workspace/{logs,out,hf}
apt-get update -qq && apt-get install -y -qq ffmpeg rsync >/dev/null
python3 -m venv --system-site-packages /workspace/venv
. /workspace/venv/bin/activate
pip install -q "huggingface_hub[hf_transfer]" diffusers transformers accelerate safetensors
# Blackwell only (B200/B300/RTX PRO 6000/5090): torch with sm_100/sm_120 kernels
python - <<'PY' || pip install -q --upgrade torch torchvision --index-url https://download.pytorch.org/whl/cu130
import torch, sys; sys.exit(0 if any(a in torch.cuda.get_arch_list() for a in ("sm_100","sm_103","sm_120")) else 1)
PY
EOF
lium exec "$NAME" --script setup.sh
lium scp "$NAME" ./gen.py /workspace/gen.py            # reads PROMPTS, writes /workspace/out/$GPU/*.png
lium scp "$NAME" ./prompts.txt /workspace/prompts.txt

# One detached worker per GPU; each handles every 8th prompt
for G in $(seq 0 $((WANT-1))); do
  rexec "$NAME" "cd /workspace && CUDA_VISIBLE_DEVICES=$G HF_HOME=/workspace/hf HF_HUB_ENABLE_HF_TRANSFER=1 nohup setsid /workspace/venv/bin/python gen.py --shard $G/$WANT --out /workspace/out/$G > /workspace/logs/gen-$G.log 2>&1 < /dev/null & echo \$!"
done
# GPU sampler as evidence that all 8 are busy
rexec "$NAME" "nohup setsid nvidia-smi --query-gpu=timestamp,index,utilization.gpu,memory.used --format=csv -l 60 > /workspace/logs/gpu.csv 2>&1 < /dev/null & echo \$!"

# Wait for the workers, watching utilisation
# `[p]ython` keeps pgrep from matching the shell that runs this very command; `|| true` because
# pgrep -c exits 1 on a zero count; the remote therefore always exits 0 and a failed rexec is lium's own error
while :; do
  if LEFT=$(rexec "$NAME" "pgrep -fc '[p]ython gen.py' || true"); then
    [ "$LEFT" != "0" ] || break
    rexec "$NAME" "nvidia-smi --query-gpu=index,utilization.gpu --format=csv,noheader | tr '\n' ' '"
  else
    gone "$NAME" && { echo "pod gone (TTL or removal)"; exit 1; }    # anything else: an API/SSH hiccup, retry
  fi
  sleep 60
done

pull "$NAME" /workspace/out/ ./out/                 # rsync, resumable, no -z
pull "$NAME" /workspace/logs/ ./logs/
# the EXIT trap removes the pod and prints "pods left: 0"
```

Video: encode on the pod with `ffmpeg` only if it is already rented for the
render; otherwise copy frames pod-to-pod to a 1-GPU node (SKILL.md, "Moving
Data") and free the 8-GPU node first. FlashAttention-3 only helps on
H100/H200; on Blackwell rely on SDPA/cuDNN attention.

## RL / simulation

Environment stepping is CPU-bound and the policy update is GPU-bound: use one
GPU, plenty of RAM (`ram_gb` is in `lium ls --format json`; the CLI shows no CPU count — read `nproc` on the pod right after `up`), and
checkpoint to `/workspace` every few minutes because container restarts kill
processes but keep `/workspace`.

```bash
NAME=rl-$(date +%s)
lium ls --gpu H100 --count 1 --format json | jq -r 'sort_by(.price_per_hour) | .[0:5][] | "\(.huid) \(.ram_gb)GB RAM $\(.price_per_hour)/h \(.country)"'
rent --gpu H100 -c 1 --name "$NAME" --ttl 12h || exit 1
trap teardown EXIT
./verify_gpus.sh "$NAME" 1 || exit 1     # it removed the pod; stop here

cat > setup.sh <<'EOF'
set -e
mkdir -p /workspace/{logs,ckpt}
apt-get update -qq && apt-get install -y -qq rsync libgl1 libglib2.0-0 >/dev/null   # headless envs need these
python3 -m venv --system-site-packages /workspace/venv
. /workspace/venv/bin/activate && pip install -q gymnasium "stable-baselines3[extra]" tensorboard
EOF
lium exec "$NAME" --script setup.sh
lium rsync "$NAME" ./rl /workspace/rl                # code; must --resume from /workspace/ckpt when present

rexec "$NAME" "cd /workspace/rl && nohup setsid /workspace/venv/bin/python train.py --ckpt-dir /workspace/ckpt --resume > /workspace/logs/train.log 2>&1 < /dev/null & echo \$!" > pid.txt
# Detect a restart: PID 1's age resets. Relaunch with --resume if so.
while :; do
  ALIVE=$(rexec "$NAME" "kill -0 $(cat pid.txt) 2>/dev/null && echo yes || echo no") || { gone "$NAME" && { echo "pod gone (TTL or removal)"; exit 1; }; sleep 120; continue; }
  if [ "$ALIVE" = no ]; then
    if rexec "$NAME" "test -f /workspace/ckpt/DONE && echo done" | grep -q done; then break; fi
    echo "worker gone (pod uptime $(rexec "$NAME" 'ps -p 1 -o etimes=')s) — resuming"
    rexec "$NAME" "cd /workspace/rl && nohup setsid /workspace/venv/bin/python train.py --ckpt-dir /workspace/ckpt --resume >> /workspace/logs/train.log 2>&1 < /dev/null & echo \$!" > pid.txt
  fi
  sleep 120
done
pull "$NAME" /workspace/ckpt/ ./ckpt/
# the EXIT trap removes the pod and prints "pods left: 0"
```

TensorBoard: bind it to an internal port from `lium ps --format json | jq '.[0].ports'`
and `lium port-forward "$NAME" 6006` from your machine.

## Batch data job

Embed, transcribe, OCR or transform a large dataset. Upload the input once,
process with one worker per GPU writing parquet shards to `/workspace/out`, pull
the shards, tear down. Use the cheapest node that fits the model — this is where
an idle 8-GPU node hurts most.

```bash
NAME=batch-$(date +%s); WANT=2
rent --gpu RTX4090 -c $WANT --name "$NAME" --ttl 6h || exit 1
trap teardown EXIT
./verify_gpus.sh "$NAME" $WANT || exit 1     # it removed the pod; stop here

cat > setup.sh <<'EOF'
set -e
mkdir -p /workspace/{logs,in,out,hf}
apt-get update -qq && apt-get install -y -qq rsync ffmpeg tesseract-ocr >/dev/null
python3 -m venv --system-site-packages /workspace/venv
. /workspace/venv/bin/activate && pip install -q "huggingface_hub[hf_transfer]" pyarrow sentence-transformers
EOF
lium exec "$NAME" --script setup.sh

# Upload the input (rsync handles directories; re-runs only send the difference)
lium rsync "$NAME" ./data /workspace/in
lium scp "$NAME" ./process.py /workspace/process.py    # args: --shard i/n --in /workspace/in --out /workspace/out/part-i.parquet

for G in $(seq 0 $((WANT-1))); do
  rexec "$NAME" "cd /workspace && CUDA_VISIBLE_DEVICES=$G HF_HOME=/workspace/hf nohup setsid /workspace/venv/bin/python process.py --shard $G/$WANT --in /workspace/in --out /workspace/out/part-$G.parquet > /workspace/logs/part-$G.log 2>&1 < /dev/null & echo \$!"
done
while :; do
  if LEFT=$(rexec "$NAME" "pgrep -fc '[p]ython process.py' || true"); then
    [ "$LEFT" != "0" ] || break
    rexec "$NAME" "tail -qn 1 /workspace/logs/part-*.log"
  else
    gone "$NAME" && { echo "pod gone (TTL or removal)"; exit 1; }
  fi
  sleep 60
done
rexec "$NAME" "ls -l /workspace/out && du -sh /workspace/out"
pull "$NAME" /workspace/out/ ./out/ 50000
# the EXIT trap removes the pod and prints "pods left: 0"
```

## Teardown checklist

```bash
lium rm "$NAME" -y                          # exit 5 if the name did not match — read it
lium ps --format json | jq -r '.[] | "\(.name) \(.status) $\(.price_per_hour)/h spent $\(.spent_usd)"'
lium schedules list                         # nothing pending that you still need
```

Before removing: everything you want is under `./out` locally (or on the cheap
pod), the `nvidia-smi -L` / `lium ps` snapshots from the verification step are
saved, and `spent_usd` matches your expectation of uptime × price.
