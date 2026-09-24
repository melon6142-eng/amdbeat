#!/usr/bin/env bash
# HIP hostreg DeepSeek on :8091. No fuser -k. Exits if 8091 already in use.
set -euo pipefail
BIN="${BIN:-$HOME/src/unsloth-llama-hostreg/build-hip-hostreg/bin/llama-server}"
MODEL="${MODEL:-$HOME/models/gguf/DeepSeek-V4-Flash-IQ2XXS/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf}"
PORT="${PORT:-8091}"
CTX="${CTX:-36864}"
NGL="${NGL:-all}"
REGISTER="${REGISTER:-1}"
LOG="${LOG:-$HOME/logs/bench-ds-20260924/serve-hostreg-${TAG:-run}.log}"
if ss -ltn | grep -q ":${PORT} "; then
  echo "port $PORT already listening; refuse to start" >&2
  exit 1
fi
export LD_LIBRARY_PATH="$HOME/src/unsloth-llama-hostreg/build-hip-hostreg/bin:/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
if [[ "$REGISTER" == "1" ]]; then export GGML_CUDA_REGISTER_HOST=1; else unset GGML_CUDA_REGISTER_HOST || true; fi
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true
EXTRA=()
if [[ -n "${SPEC_TYPE:-}" ]]; then
  EXTRA+=(--spec-type "$SPEC_TYPE")
fi
if [[ -n "${DRAFT_MODEL:-}" ]]; then
  EXTRA+=(--spec-draft-model "$DRAFT_MODEL" --spec-draft-n-max "${DRAFT_N_MAX:-5}")
fi
mkdir -p "$(dirname "$LOG")"
exec "$BIN" -m "$MODEL" --host 0.0.0.0 --port "$PORT" --alias deepseek4-iq2-amd \
  --device ROCm0 --gpu-layers "$NGL" --flash-attn on --fit off \
  --load-mode mmap+mlock --ctx-size "$CTX" --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --jinja --no-webui "${EXTRA[@]}" "$@"
