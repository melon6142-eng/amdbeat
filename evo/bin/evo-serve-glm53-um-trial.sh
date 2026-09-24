#!/usr/bin/env bash
set -euo pipefail
ROCM="${ROCM:-$HOME/opt/unsloth-llama-b10698-mix-rocm-gfx1151}"
MODEL="${GLM_GGUF:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
LOG="${HOME}/logs/serve-glm53-um.log"
PORT="${PORT:-8080}"
CTX="${CTX:-36864}"
LOAD_MODE="${LOAD_MODE:-mmap}"
CPU_MOE="${CPU_MOE:-0}"
mkdir -p "$(dirname "$LOG")"
# stop previous carefully (avoid matching this script)
for p in $(pgrep -f "${ROCM}/llama-server" || true); do kill -9 "$p" 2>/dev/null || true; done
sleep 2
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$ROCM"
export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1
export HSA_XNACK=1
# disable CUDA/HIP graphs — graphs + managed memory faulted previously
export GGML_CUDA_DISABLE_GRAPHS=1
EXTRA=()
if [[ "$CPU_MOE" == "1" ]]; then EXTRA+=(--cpu-moe); fi
nohup "$ROCM/llama-server" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias glm53-flash-aj-iq2 \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode "$LOAD_MODE" \
  "${EXTRA[@]}" \
  --ctx-size "$CTX" --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 \
  --cache-reuse 256 \
  --reasoning off --reasoning-budget 0 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! UM=1 HSA_XNACK=1 DISABLE_GRAPHS=1 load=$LOAD_MODE cpu_moe=$CPU_MOE log=$LOG"
