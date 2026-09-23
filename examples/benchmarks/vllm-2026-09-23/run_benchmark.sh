#!/usr/bin/env bash
# Reproducible vLLM serving benchmark for one Lium pod.
# Usage: GPU_LABEL=h100 PRICE_PER_HOUR=1.30 bash run_benchmark.sh
set -euo pipefail

VLLM_VERSION="${VLLM_VERSION:-0.29.0}"
MODEL="${MODEL:-Qwen/Qwen3-8B}"
TP="${TP:-1}"
SEED="${SEED:-42}"
INPUT_LEN="${INPUT_LEN:-1024}"
OUTPUT_LEN="${OUTPUT_LEN:-256}"
NUM_PROMPTS="${NUM_PROMPTS:-512}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-64}"
GPU_LABEL="${GPU_LABEL:?set GPU_LABEL, e.g. h100}"
PRICE_PER_HOUR="${PRICE_PER_HOUR:?set PRICE_PER_HOUR in USD for the whole pod}"
OUT="${OUT:-/root/bench-out/$GPU_LABEL}"
VENV="${VENV:-/root/vllm-$VLLM_VERSION}"
PORT="${PORT:-8000}"

mkdir -p "$OUT"
exec > >(tee -a "$OUT/run.log") 2>&1

echo "== environment"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv | tee "$OUT/gpu.csv"
nvidia-smi | sed -n 's/.*CUDA Version: *\([0-9.]*\).*/\1/p' | head -1 > "$OUT/cuda_driver_version.txt"
echo "CUDA (driver): $(cat "$OUT/cuda_driver_version.txt")"

echo "== install vLLM $VLLM_VERSION"
if [ ! -x "$VENV/bin/vllm" ]; then
  python3 -m pip install -q uv
  python3 -m uv venv -q --python 3.12 "$VENV"
  python3 -m uv pip install -q --python "$VENV/bin/python" "vllm==$VLLM_VERSION"
fi
"$VENV/bin/python" - <<'PY' | tee "$OUT/versions.txt"
import torch, vllm
print(f"vllm {vllm.__version__}")
print(f"torch {torch.__version__}")
print(f"torch_cuda {torch.version.cuda}")
PY

echo "== start server"
"$VENV/bin/vllm" serve "$MODEL" \
  --tensor-parallel-size "$TP" --seed "$SEED" --max-model-len 4096 \
  --port "$PORT" > "$OUT/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 180); do
  if curl -sf "localhost:$PORT/health" >/dev/null; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then echo "server exited"; tail -50 "$OUT/server.log"; exit 1; fi
  sleep 5
done
curl -sf "localhost:$PORT/health" >/dev/null

echo "== benchmark"
"$VENV/bin/vllm" bench serve \
  --backend vllm --base-url "http://localhost:$PORT" --model "$MODEL" \
  --dataset-name random --random-input-len "$INPUT_LEN" --random-output-len "$OUTPUT_LEN" \
  --num-prompts "$NUM_PROMPTS" --max-concurrency "$MAX_CONCURRENCY" --seed "$SEED" --ignore-eos \
  --percentile-metrics ttft,tpot,itl --metric-percentiles 50,95 \
  --save-result --result-dir "$OUT" --result-filename "result.json"

"$VENV/bin/python" - "$OUT/result.json" "$PRICE_PER_HOUR" "$GPU_LABEL" <<'PY' | tee "$OUT/summary.json"
import json, sys
r = json.load(open(sys.argv[1])); price = float(sys.argv[2])
tok_s = r["output_throughput"]
print(json.dumps({
    "gpu": sys.argv[3],
    "output_tokens_per_s": round(tok_s, 1),
    "ttft_p50_ms": round(r["p50_ttft_ms"], 1),
    "ttft_p95_ms": round(r["p95_ttft_ms"], 1),
    "price_usd_per_hour": price,
    "usd_per_1m_output_tokens": round(price / (tok_s * 3600) * 1e6, 4),
    "completed": r["completed"],
}, indent=1))
PY
