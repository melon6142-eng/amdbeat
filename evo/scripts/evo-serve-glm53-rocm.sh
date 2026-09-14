#!/usr/bin/env bash
# GLM-5.3-Flash AJ-IQ2_XXS — AMD-only Vulkan0.
# HIP/ROCm0 advertises 120 GiB but only ~29 GiB is allocatable after the
# 96 GiB VRAM carve-out, so an 82 GiB cudaMalloc always OOMs. MIX Vulkan
# sees VRAM+GTT together (same path as DeepSeek IQ2 / Flash).
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${GLM_GGUF:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
LOG="${HOME}/logs/serve-glm53-rocm.log"
PORT="${PORT:-8080}"
CTX="${CTX:-131072}"
BATCH="${BATCH:-2048}"
UBATCH="${UBATCH:-512}"
TEMP="${TEMP:-0.7}"
TOP_P="${TOP_P:-0.8}"
TOP_K="${TOP_K:-20}"
CACHE_K="${CACHE_K:-q8_0}"
CACHE_V="${CACHE_V:-q8_0}"
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN — extract Unsloth MIX linux-x64-vulkan tarball to $MIX"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL — wait for rsync"; exit 1; }

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="${RADV_PERFTEST:-gpl,sam,nggc}"
unset VK_DRIVER_FILES
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias glm53-flash-aj-iq2 \
  --device Vulkan0 --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size "$BATCH" --ubatch-size "$UBATCH" \
  --cache-type-k "$CACHE_K" --cache-type-v "$CACHE_V" \
  --threads 32 --threads-batch 32 \
  --reasoning off --reasoning-budget 0 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp "$TEMP" --top-p "$TOP_P" --top-k "$TOP_K" \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT ctx=$CTX batch=$BATCH ubatch=$UBATCH device=Vulkan0"
echo "Wait: curl -s http://127.0.0.1:${PORT}/health"
