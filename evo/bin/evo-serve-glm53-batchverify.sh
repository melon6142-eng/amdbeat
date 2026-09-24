#!/usr/bin/env bash
set -euo pipefail
# Experimental DFlash serve with raised MoE MMVQ batch ceiling (batchverify worktree).
# Do NOT start while GPU is busy with other measurements.
BIN="${BIN:-$HOME/src/llama-dflash2-batchverify/build-hip-batchverify/bin/llama-server}"
MODEL="${MODEL:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
DRAFT="${DRAFT:-$HOME/models/gguf/GLM-5.3-Flash-DFlash2/GLM-5.3-Flash-DFlash2-BF16.gguf}"
HOST="${HOST:-0.0.0.0}"; PORT="${PORT:-8088}"; CTX="${CTX:-36864}"
NMAX="${SPEC_DRAFT_N_MAX:-3}"
export LD_LIBRARY_PATH="$HOME/src/llama-dflash2-batchverify/build-hip-batchverify/bin:/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST=1
# Optional: GGML_MMVQ_MMID_MAX=8 (default behavior after patch) or 16 for n_max=8 experiments
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true
exec "$BIN" -m "$MODEL" -md "$DRAFT" --spec-type draft-dflash --spec-draft-n-max "$NMAX" \
  --spec-draft-ngl 999 \
  --host "$HOST" --port "$PORT" --alias glm53-batchverify \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap+mlock --ctx-size "$CTX" --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui "$@"
