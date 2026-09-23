# vLLM serving benchmark on Lium: 1× H100, 1× H200, 1× B200 (23 Sep 2026)

One model, one prompt set, one seed, one vLLM version on three single-GPU Lium pods.
Every number below comes from the raw JSON in `results/`, and `run_benchmark.sh` reproduces it.

## Results

| GPU (1×) | Output tokens/s | TTFT p50 | TTFT p95 | Price per hour | $ per 1M output tokens |
|---|---:|---:|---:|---:|---:|
| H100 80GB HBM3 | 3,846 | 711 ms | 1,294 ms | $1.30 | $0.094 |
| H200 | 4,478 | 727 ms | 1,261 ms | $3.00 | $0.186 |
| B200 | 7,249 | 526 ms | 938 ms | $5.50 | $0.211 |

- $ per 1M output tokens = price per hour ÷ (output tokens/s × 3,600) × 1,000,000.
- The prices are what each pod was billed. They match the `min_price_usd_per_gpu_hour` for each model in
  [lium.io/pricing.json](https://lium.io/pricing.json), read at 2026-09-23T10:48:49Z (feed `generated_at` 10:44:36Z).
  Prices change. Read the feed again before you compare.
- All 512 requests completed on every GPU, with 0 failures.
- 8× B300 was not measured in this run.

## What was measured

| Setting | Value |
|---|---|
| Model | `Qwen/Qwen3-8B`, BF16, `--max-model-len 4096`, tensor parallel 1 |
| vLLM | 0.29.0 (pip wheel), torch 2.13.0+cu130 |
| Driver / CUDA | 580.178.04 / 13.0 (H100, H200); 580.126.20 / 13.0 (B200) |
| Benchmark | `vllm bench serve` (in vLLM 0.29.0, `benchmarks/benchmark_serving.py` is a stub that points to this command) |
| Dataset | `random`: 1,024 input tokens and 256 output tokens per request, `--ignore-eos` |
| Load | 512 prompts, `--max-concurrency 64`, request rate unlimited |
| Sampling | the model's server-side defaults from its `generation_config`; the client sends no temperature; `--ignore-eos` fixes the output length |
| Seed | 42 (server and prompt sampling) |
| Pod image | Lium's default `Pytorch (Cuda + DinD)` template |

A run is one pass after the server is healthy. The server compiles kernels and captures CUDA graphs at start-up,
so the first request is not part of the timing.

## Reproduce

Rent a pod with an auto-stop, run the script, then remove the pod:

```bash
lium up --gpu H100 -c 1 --name vllm-bench --ttl 75m --budget 2.5 -y
lium exec vllm-bench -e GPU_LABEL=h100 -e PRICE_PER_HOUR=1.30 --script run_benchmark.sh
lium scp -d vllm-bench /root/bench-out/h100/result.json ./result.json
lium rm vllm-bench -y
```

Set `PRICE_PER_HOUR` to the price the pod shows in `lium ps`. The script installs vLLM in a venv, starts the
server, waits for `/health`, runs the benchmark and writes these files to `/root/bench-out/<GPU_LABEL>/`:

| File | Contents |
|---|---|
| `result.json` | Raw `vllm bench serve` output, including TPOT and ITL percentiles |
| `summary.json` | Output tokens/s, TTFT p50/p95, $ per 1M output tokens, completed and failed request counts |
| `versions.txt` | vLLM, torch and torch CUDA versions |
| `gpu.csv`, `cuda_driver_version.txt` | GPU name, driver version and the driver's CUDA version |

Override `VLLM_VERSION`, `MODEL`, `TP`, `SEED`, `INPUT_LEN`, `OUTPUT_LEN`, `NUM_PROMPTS`, `MAX_CONCURRENCY` or
`MAX_MODEL_LEN` (default 4096; it must cover `INPUT_LEN + OUTPUT_LEN`) with `-e NAME=value` to change the workload.
The script exits non-zero when any request fails. On a pod, the whole run takes about 5 minutes. Most of that time is the
install and the first-start kernel compile.

Only vLLM is pinned. Its dependencies, torch included, resolve at install time, and `versions.txt` records the
vLLM, torch and CUDA versions that were used. The `MAX_MODEL_LEN` guard and the failed-request exit were added to
the script after these runs, together with the `failed` key in `summary.json`. The committed `summary.json` files come
from the earlier version and have no `failed` key; `result.json` shows 0 failed requests for every GPU.
