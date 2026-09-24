#!/usr/bin/env bash
set -euo pipefail
BIN="${BIN:-$HOME/src/llama-iq2-opt/build-hip-opt/bin/llama-server}"
MODEL="${MODEL:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
HOST="${HOST:-0.0.0.0}"; PORT="${PORT:-8092}"; CTX="${CTX:-36864}"
export LD_LIBRARY_PATH="$HOME/src/llama-iq2-opt/build-hip-opt/bin:/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST=1
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true
exec "$BIN" -m "$MODEL" --host "$HOST" --port "$PORT" --alias glm53-iq2-opt \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap+mlock --ctx-size "$CTX" --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui "$@"
