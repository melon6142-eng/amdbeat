# quant-lab — quantization & serving scorecard

Goal: whenever a new open **general-purpose** model ships, produce a quantization + serving recipe for DGX Spark (GB10, 128GB unified, TP1/TP2) that beats other public labs (MiaAI-Lab, unsloth, turboderp, NVIDIA NVFP4, bartowski, …) on **lower quality loss** and **higher tok/s**. Building our own general open model comes after that.

This directory is a **measurement framework scaffold**. It does not touch Spark/EVO GPU servers. The default path is a local mock-endpoint dry-run.

## What “better than other labs” means

Every model × quant × runtime is compared on the same **scorecard**.

| Axis | Metrics | Notes |
|---|---|---|
| **Quality loss** (vs BF16 ref) | Fixed-prompt KL / top-1·top-k agreement, fixed-corpus PPL, small general evals (MMLU-Pro, GSM8K/MATH, HumanEval/LiveCodeBench, IFEval, long-needle subset, **fixed seed**) | HTTP top-k logprobs only give a **partial KL** — see comments in `scripts/kl_compare.py`. For EXL3 prefer turboderp’s `measure_model` path. |
| **Speed** | Prefill tok/s, decode tok/s @ concurrency 1 and 4, depth 0 / 32k / 128k | TTFT = first streamed token. Speculative decoding (MTP/DFlash/EAGLE) on/off must be labeled on the table. |
| **Memory** | Weights GB, KV capacity (tokens) at a given ctx | From server logs, `GPU_MEMORY_UTILIZATION`, or the engine report. |
| **Reproducibility** | Engine git commit, container image digest, weight HF revision SHA, sampling flags | Pin these in the README; don’t publish bare numbers. |

## Fair comparison rules

1. **Same hardware** (same Spark count/TP, same EVO/R9700, etc.). Re-measure on our machines — don’t reuse another lab’s README numbers.
2. **Same prompt set, seed, temperature/top_p** (`configs/bench.yaml`).
3. Pull competitor quants at a **pinned revision**, serve them, and hit them with the same client.
4. If BF16 won’t fit on Spark: (a) validate the KL pipeline on a same-architecture smaller proxy, (b) treat public turboderp `kld_table` / benches as **reference only** — never mix them into a “we win” claim.
5. Prefer **hf-mirror / ModelScope** for downloads. No GitHub push or HF upload without the user’s GO.

## Quick start (dry-run, no GPU)

```bash
cd /workspace/quant-lab
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python scripts/mock_openai_server.py --port 18765 &
.venv/bin/python scripts/bench_client.py --endpoint mock --dry-run
.venv/bin/python scripts/kl_compare.py --ref mock --cand mock --cand-model mock-quant
```

Outputs: `results/*.json`, `results/*_scorecard.md`.

## Layout

- `configs/` — endpoint and bench settings
- `prompts/fixed_prompts.jsonl` — KL / eval subset
- `scripts/bench_client.py` — speed, eval, scorecard
- `scripts/kl_compare.py` — reference vs candidate top-logprob compare
- `scripts/mock_openai_server.py` — mock for dry-run
- `PIPELINE.md` — playbook for each new model
- `FIRST_TARGET.md` — first head-to-head target
- `evo/` — archived EVO run logs, scripts, and configs (chronological history)

## Reference labs (methodology)

- MiaAI-Lab Spark recipes: https://github.com/MiaAI-Lab
- turboderp EXL3 + KL: https://huggingface.co/turboderp/Qwen3.8-27B-exl3 , https://github.com/turboderp-org/exllamav3
- unsloth Dynamic GGUF: https://huggingface.co/unsloth/Qwen3.8-27B-GGUF
- bartowski imatrix GGUF: https://huggingface.co/bartowski/Qwen3.8-27B-GGUF
- NVIDIA FP4/NVFP4: https://huggingface.co/nvidia/Qwen3.8-Flash-Next-FP4-Local

Lab GPUs (dsv41 TP2, EVO 8216/8217) are **shared and often saturated**. Bench/quant runs need a lab-ops + user window first. See `FIRST_TARGET.md`.
