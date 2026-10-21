# R9700 × Qwen3.8-27B — max-efficiency GGUF recipe

**Goal:** Run Qwen3.8-27B on a single AMD Radeon **R9700 32GB** with the best **quality × speed** product.  
“Efficiency” means not the smallest file, but the highest bpw×speed under **full GPU offload + usable context (≥32k)**.

**Engine:** llama.cpp (`qwen35` / Gated DeltaNet) · GGUF · ROCm and/or Vulkan.  
**Out of scope for this doc folder alone:** EVO SSH, multi-GB downloads, stopping 8216. Docs and scripts live under `r9700-qwen38-27b/`.

## Primary quant

| Field | Value |
|---|---|
| File | `unsloth/Qwen3.8-27B-GGUF` → **`Qwen3.8-27B-UD-Q6_K.gguf`** |
| Size | **20.47 GiB** (HF LFS, 2026-10-21) |
| Why | Full offload on 32GB with **32k–64k** KV left; higher quality ceiling than Q4/IQ. Lighter than same-class bartowski `Q6_K` (22.22 GiB), so more room for KV/overhead. |
| Budget (est.) | weights 20.5 + KV@32k 2.0 + scratch ~2 ≈ **~24.5 GiB** · @64k ≈ **~26.5** · @128k ≈ **~30.5 (tight)** |

## Fallback ladder

1. **bartowski `Q6_K`** (22.22 GiB) — same-bpw competitor  
2. **unsloth `UD-Q5_K_M`** (18.41) / **bartowski `Q5_K_M`** (19.49) — when stretching to 128k or large scratch  
3. **bartowski `Q4_K_M`** (16.24) / **unsloth `UD-Q4_K_M`** (15.33) — long context, stable single request  
4. **`Q8_0`** (~27.1 GiB) — quality ceiling / short-ctx (≤8–16k) reference only (not for 32k+)

Ultra-low IQ (UD-IQ*) is not the #1 “max efficiency” pick — when VRAM remains, **Q5/Q6** wins on quality×speed.

## Head-to-head plan

Same card, same llama.cpp flags:

| vs | Ours (or primary) | Competitor | Measure |
|---|---|---|---|
| A | unsloth UD-Q6_K | bartowski Q6_K | tok/s (pp/tg), fixed-prompt agreement, KL if possible |
| B | UD-Q5_K_M | Q5_K_M | same |
| C | (Phase 2) our imatrix Q6 | winner of A | same + PPL |

Hooks: `../scripts/bench_client.py` · scorecard: `results/scorecard_template.md`.

## What lab-ops needs before running

1. **8216** (`strata-qwen3.8-flash-next-iq3_xxs`) **stop/swap approval** — free the R9700  
2. EVO **llama.cpp binary path** (`llama-server` or custom build) + whether ROCm or Vulkan is the live backend  
3. Agreed model disk path (`$EVO_MODELS`, ~320G free)  
4. (Optional) mirror: hf-mirror / ModelScope

Details, flags, download templates → [`RECIPE.md`](RECIPE.md) · file list → [`VERIFIED_FILES.md`](VERIFIED_FILES.md) · Phase 2 → [`PHASE2.md`](PHASE2.md).

## Latest (2026-10-21): rdna-boosts live config

1327 pp2048, 30.9 tg, and 75.4 / 62.1 MTP chat on one R9700. See [`results/RDNA-BOOSTS-2026-10-21.md`](results/RDNA-BOOSTS-2026-10-21.md).
