#!/usr/bin/env bash
set -euo pipefail
BIN="${BIN:-$HOME/src/llama-dflash2-vcruz/build-hip-dflash/bin/llama-server}"
MODEL="${MODEL:-$HOME/models/gguf/GLM-5.3-Flash-UD-IQ2_XXS/GLM-5.3-Flash-UD-IQ2_XXS-00001-of-00004.gguf}"
HOST="${HOST:-0.0.0.0}"; PORT="${PORT:-8080}"; CTX="${CTX:-36864}"
NMAX="${SPEC_DRAFT_N_MAX:-2}"
export LD_LIBRARY_PATH="$(dirname "$BIN"):/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST=1
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true
exec "$BIN" -m "$MODEL" \
  --spec-type draft-mtp,ngram-mod --spec-draft-n-max "$NMAX" \
  --spec-ngram-mod-n-match 6 --spec-ngram-mod-n-min 12 --spec-ngram-mod-n-max 16 \
  --host "$HOST" --port "$PORT" --alias glm53-mtp-ngram \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap+mlock --ctx-size "$CTX" --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui "$@"
