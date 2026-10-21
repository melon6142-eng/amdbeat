# AMDBeat — Reproducible LLM Quantization and Inference Benchmarks for AMD GPUs

AMDBeat publishes **measured** quantization + serving recipes for AMD GPUs, starting with the Radeon **R9700 (gfx1201, 32GB)**. Every number comes with the engine build, flags, and commands needed to reproduce it. Ryzen AI Max+ **395** (Strix Halo) is a planned second target.

## Headline results — Qwen3.8-27B on R9700 (2026-10-21, Asia/Shanghai)

llama.cpp **b10698**, `-ngl 99 -fa 1`, KV **q8_0**, `llama-bench` r3.

| Quant | Backend | pp512 | pp8192 | tg128 | VRAM |
|---|---|---|---|---|---|
| unsloth UD-Q6_K | **Vulkan** (unsloth mix b6e334953) | **872.17** | **798.41** | **24.63** | ~21.06 GiB |
| unsloth UD-Q6_K | ROCm 7.2.1 HIP gfx1201 | 864.42 | 780.19 | 23.65 | - |
| bartowski Q6_K | Vulkan | 871.79 | 799.26 | 22.98 | 22.21 GiB file |

**MTP** (Vulkan, `mtp-Q4_0` draft, server smoke):

| spec-draft-n-max | code tok/s (accept) | prose tok/s (accept) | VRAM |
|---|---|---|---|
| **3** (live) | **58.4** (0.758) | **41.2** (0.434) | ~24.2 GiB |
| 4 | 55.9 | 38.4 | - |

On this card and build, **Vulkan edged out ROCm**; unsloth **UD-Q6_K + MTP n-max 3** is the live default. Full notes: [`r9700-qwen38-27b/results/RESULTS-2026-10-21.md`](r9700-qwen38-27b/results/RESULTS-2026-10-21.md).

## Reproduce

Placeholders: `$MODELS_DIR`, `$LLAMA_SERVER`, `$LLAMA_BENCH`, `<host>`, `$PORT`.

### llama-bench (speed table above)

```bash
$LLAMA_BENCH \
  -m "$MODELS_DIR/Qwen3.8-27B-UD-Q6_K.gguf" \
  -ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 \
  -p 512,8192 -n 128 -r 3 \
  --device Vulkan0
# ROCm: build a HIP binary and omit --device / set HIP_VISIBLE_DEVICES=0
```

### llama-server (MTP live config)

```bash
$LLAMA_SERVER \
  -m "$MODELS_DIR/Qwen3.8-27B-UD-Q6_K.gguf" \
  --host 0.0.0.0 --port "${PORT:-8216}" \
  -a qwen3.8-27b-ud-q6k \
  -ngl 99 -fa on -c 32768 \
  -ctk q8_0 -ctv q8_0 --jinja \
  --device Vulkan0 \
  --spec-type draft-mtp \
  -md "$MODELS_DIR/mtp-Qwen3.8-27B-Q4_0.gguf" \
  -devd Vulkan0 -ngld all \
  --spec-draft-n-max 3
```

Recipe details and quant ladder: [`r9700-qwen38-27b/RECIPE.md`](r9700-qwen38-27b/RECIPE.md).

### Client dry-run (no GPU)

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python scripts/mock_openai_server.py --port 18765 &
.venv/bin/python scripts/bench_client.py --endpoint mock --dry-run
.venv/bin/python scripts/kl_compare.py --ref mock --cand mock --cand-model mock-quant
.venv/bin/pytest -q
```

## What we measure

| Axis | Metrics | Notes |
|---|---|---|
| **Quality loss** (vs BF16 / Q8 ref) | Partial KL + top-1 agreement over HTTP top-k logprobs; full-vocab KL via `llama-perplexity --kl-divergence` | HTTP path is a **lower-bound** approximation — see `scripts/kl_compare.py` |
| **Speed** | Prefill / decode tok/s, TTFT, optional MTP acceptance | Label speculative decoding on/off |
| **Memory** | Weights GiB, KV capacity at a given ctx | From server logs / VRAM readouts |
| **Reproducibility** | Engine commit, flags, weight revision | Pin before publishing comparisons |

HumanEval pass@1 executes model code in a timed subprocess — **unsafe outside a sandbox**; see warnings in `scripts/bench_client.py`.

## Layout

- `r9700-qwen38-27b/` — R9700 recipe, verified files, results, serve scripts
- `configs/` — bench + example endpoints (placeholders only)
- `prompts/fixed_prompts.jsonl` — KL / eval subset
- `scripts/` — `bench_client.py`, `kl_compare.py`, mock server
- `tests/` — pytest (KL math, HumanEval executor, dry-run smoke)
- `PIPELINE.md` / `FIRST_TARGET.md` — how we pick the next model
- `evo/` — archived run logs (scrubbed for public release)

## Roadmap

- **Ryzen AI Max+ 395** (Strix Halo iGPU) — same scorecard, bandwidth-bound decode
- Broader AMD GPU coverage as hardware is available
- Optional **DGX Spark** / general quant-lab cross-checks when a machine window exists (secondary; not the project lead)
- Phase 2: own imatrix quants vs unsloth / bartowski on the same card
- Publish only after commands + scorecard are reproducible by a third party

## License

Apache-2.0 — see [`LICENSE`](LICENSE). Copyright 2026 melon6142-eng.

## Reference labs (methodology)

- MiaAI-Lab Spark recipes: https://github.com/MiaAI-Lab
- turboderp EXL3 + KL: https://github.com/turboderp-org/exllamav3
- unsloth Dynamic GGUF / bartowski imatrix GGUF on Hugging Face
- NVIDIA FP4/NVFP4 public recipes
