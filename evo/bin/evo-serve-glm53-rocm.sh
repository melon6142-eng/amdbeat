#!/usr/bin/env bash
# GLM-5.3-Flash AJ-IQ2_XXS — AMD-only ROCm A/B (Hilbert 14.63 t/s).
# Default / preferred path is AMD+4080 Vulkan: ~/bin/evo-serve-glm53-amd4080.sh
# This binary cannot see the 4080.
set -euo pipefail
ROCM="${ROCM:-$HOME/opt/unsloth-llama-b10698-mix-rocm-gfx1151}"
MODEL="${GLM_GGUF:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
LOG="${HOME}/logs/serve-glm53-rocm.log"
PORT="${PORT:-8080}"
CTX="${CTX:-4096}"
mkdir -p "$(dirname "$LOG")"
[[ -x $ROCM/llama-server ]] || { echo "missing $ROCM/llama-server — extract Unsloth MIX gfx1151 tarball"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL — wait for rsync"; exit 1; }

pkill -f 'llama-server' || true
sleep 2
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$ROCM"
nohup "$ROCM/llama-server" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias glm53-flash-aj-iq2 \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --ctx-size "$CTX" --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 \
  --reasoning off --reasoning-budget 0 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT ctx=$CTX"
echo "Hermes 128k: CTX=131072 $0"
echo "Wait: curl -s http://127.0.0.1:${PORT}/health"
