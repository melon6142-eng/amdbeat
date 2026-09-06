#!/usr/bin/env bash
# GLM-5.3 AJ-IQ2 as a second process on the 4080 only.
# Experts stay on CPU (--cpu-moe) so this does not steal DeepSeek's AMD GTT.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${GLM_GGUF:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
LOG="${HOME}/logs/serve-glm53-4080-parallel.log"
PORT="${PORT:-8081}"
CTX="${CTX:-2048}"
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL"; exit 1; }

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias glm53-flash-aj-iq2-4080 \
  --device Vulkan0 --cpu-moe \
  --gpu-layers all --flash-attn on --fit on \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size 256 --ubatch-size 64 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 16 --threads-batch 16 \
  --reasoning off --reasoning-budget 0 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT device=Vulkan0 cpu-moe fit=on"
