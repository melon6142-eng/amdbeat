# RECIPE — Qwen3.8-27B on R9700 32GB (llama.cpp GGUF)

Do **not** run these on EVO until lab-ops clears port **8216** and confirms binary/backend.  
Placeholders: `$EVO_MODELS`, `$LLAMA_SERVER`, `$HOST`, `$PORT`.

## Quant ladder (max efficiency = quality × speed, full offload)

| priority | repo | file | GiB | target ctx | notes |
|---|---|---|---:|---|---|
| **P0 primary** | unsloth | `Qwen3.8-27B-UD-Q6_K.gguf` | 20.47 | 32k–64k | best default on 32GB |
| P1 rival | bartowski | `Qwen3.8-27B-Q6_K.gguf` | 22.22 | 32k (64k tight) | same-bpw H2H |
| P2 | unsloth | `Qwen3.8-27B-UD-Q5_K_M.gguf` | 18.41 | 64k–128k | more KV headroom |
| P2b | bartowski | `Qwen3.8-27B-Q5_K_M.gguf` | 19.49 | 64k–128k | same-bpw H2H |
| P3 | bartowski | `Qwen3.8-27B-Q4_K_M.gguf` | 16.24 | 128k+ | long-ctx fallback |
| P3b | unsloth | `Qwen3.8-27B-UD-Q4_K_M.gguf` | 15.33 | 128k+ | |
| P4 ref | either | `Qwen3.8-27B-Q8_0.gguf` | ~27.1 | ≤8–16k | quality ceiling only |
| draft | unsloth | `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` | 1.28 | — | speculative; needs server support |

### Estimated VRAM budget (P0 @ f16 KV)

```
weights          20.47 GiB
KV @ 32k          2.00 GiB
scratch/graph  ~1.5–3.0 GiB   # TODO: measure with -b/-ub on R9700
MTP draft (opt)   1.28 GiB
--------------------------------
@32k no draft   ~24–25.5 GiB   ← fits
@64k no draft   ~26–27.5 GiB   ← fits
@128k no draft  ~30–31.5 GiB   ← borderline; drop to Q5 or lower -b
@32k + MTP      ~25.5–27 GiB   ← ok if binary supports draft
```

R9700 usable ≈ 31–31.5 GiB after driver. Prefer **one concurrent request**.

## Download (templates — do not run yet)

Prefer mirrors later: **hf-mirror.com**, **ModelScope**. Exact filenames from `VERIFIED_FILES.md`.

### huggingface-cli / hf (official or mirror)

```bash
export EVO_MODELS="${EVO_MODELS:-/data/models}"   # agree with lab-ops
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"  # or unset for huggingface.co

# Primary
hf download unsloth/Qwen3.8-27B-GGUF \
  Qwen3.8-27B-UD-Q6_K.gguf \
  --local-dir "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF"

# Rival (same-bpw)
hf download bartowski/Qwen3.8-27B-GGUF \
  Qwen3.8-27B-Q6_K.gguf \
  --local-dir "$EVO_MODELS/bartowski-Qwen3.8-27B-GGUF"

# Optional draft
hf download unsloth/Qwen3.8-27B-GGUF \
  MTP/mtp-Qwen3.8-27B-Q4_0.gguf \
  --local-dir "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF"
```

### ModelScope (example)

```bash
# pip install modelscope
modelscope download --model unsloth/Qwen3.8-27B-GGUF \
  Qwen3.8-27B-UD-Q6_K.gguf \
  --local_dir "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF"
# TODO: confirm ModelScope id mirrors HF path; if missing, use hf-mirror only.
```

### aria2c direct (hf-mirror)

```bash
aria2c -x16 -s16 -c \
  -d "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF" \
  "https://hf-mirror.com/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q6_K.gguf"
```

Disk: leave ~50+ GiB free — P0+P1 ≈ 43 GiB; leave room for Q5/Q4 pair if sweeping.

## llama.cpp serve flags (AMD)

### Baseline (recommended start)

```bash
$LLAMA_SERVER \
  -m "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q6_K.gguf" \
  --host 0.0.0.0 --port "${PORT:-8216}" \
  -ngl 99 \
  -c 32768 \
  -b 2048 -ub 512 \
  -fa on \
  --jinja \
  --mmap \
  -np 1 \
  --alias qwen38-27b-ud-q6k
```

| flag | intent | notes |
|---|---|---|
| `-ngl 99` | full GPU offload | required for max speed |
| `-c 32768` | ≥32k ctx | raise to 65536 if VRAM OK; 131072 only on Q5/Q4 or after measure |
| `-b` / `-ub` | prefill batch | **TODO:** R9700 sweet spot; Vulkan had garbage at batch 512 on some qwen35 builds — try 1024/2048 |
| `-fa on` | flash-attn | ROCm/Vulkan support varies by build; if unsupported, server may ignore or error — **TODO measure** |
| `--jinja` | Qwen chat template | required for thinking/tools template |
| `--mmap` | map weights from disk | lowers RSS; first token may be slower cold |
| `-np 1` | single slot | prefer one concurrent request on 32GB |
| `--alias` | OpenAI model id | for `bench_client.py` |

### Speculative (optional)

```bash
# Only if $LLAMA_SERVER build supports --draft / MTP for qwen35
$LLAMA_SERVER ... \
  -md "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF/MTP/mtp-Qwen3.8-27B-Q4_0.gguf" \
  # TODO: confirm exact draft flags for this binary (--draft-max, -ngld, etc.)
```

### ROCm vs Vulkan (tradeoffs — measure on R9700)

| | ROCm/HIP | Vulkan |
|---|---|---|
| GDN (Qwen3.5/3.8) | fused kernels exist; quality depends on build age | GDN shaders added 2026-03+; still evolving |
| Flash-attn | some RDNA forks have fattn kernels | often available; verify `-fa` |
| Known footguns | older HIP GDN could be slow on iGPU class | batch-size quirks on hybrid models |
| Recommendation | **try both** with identical `-m/-c/-b`; pick higher tg/s with correct text | |

**TODO on hardware:** `rocminfo` / Vulkan device name for R9700; which binary EVO already runs for 8216/8217; decode tok/s @ depth 0/8k/32k.

Pin GPU (example — adjust to real index):

```bash
export HIP_VISIBLE_DEVICES=0          # ROCm path
# or
export GGML_VK_VISIBLE_DEVICES=0      # Vulkan path — name may differ by build
```

Do **not** target the 395 iGPU for this recipe.

## Scripts in this folder

| script | role |
|---|---|
| `scripts/env.example` | copy to `scripts/env.local` (gitignored locally) |
| `scripts/download_primary.sh` | download P0 (+ optional P1) via hf/aria2 |
| `scripts/start.sh` | start llama-server with P0 flags |
| `scripts/stop.sh` | stop by pidfile / port |
| `scripts/status.sh` | health + `/v1/models` |
| `scripts/smoke.sh` | one short chat completion |
| `scripts/bench.sh` | wraps `../../scripts/bench_client.py` |

All are **templates** with placeholders; they refuse to run if `EVO_CONFIRM=1` is unset (safety).

## Smoke + bench hooks

```bash
# after server is up (from any host that can reach <host>)
cd /path/to/amdbeat
. .venv/bin/activate

# smoke
curl -s http://<host>:${PORT:-8216}/v1/models | head

# bench (same flags for both competitors — swap model alias/endpoint only)
python scripts/bench_client.py \
  --config configs/bench.yaml \
  --endpoint http://<host>:${PORT:-8216}/v1 \
  --model qwen38-27b-ud-q6k \
  --out results/r9700_ud_q6k.json
```

Fill `results/scorecard_template.md` after A vs B runs.
