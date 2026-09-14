#!/usr/bin/env bash
# DeepSeek IQ2 on AMD GTT only (Vulkan0). Fastest overnight result: ~11.2 t/s.
# Does not kill a GLM server on another port.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${DS_GGUF:-$HOME/models/gguf/DeepSeek-V4-Flash-IQ2XXS/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf}"
LOG="${HOME}/logs/serve-deepseek-amd.log"
PORT="${PORT:-8080}"
CTX="${CTX:-131072}"
BATCH="${BATCH:-2048}"
UBATCH="${UBATCH:-512}"
TEMP="${TEMP:-0.7}"
TOP_P="${TOP_P:-0.8}"
TOP_K="${TOP_K:-20}"
CACHE_K="${CACHE_K:-q8_0}"
CACHE_V="${CACHE_V:-q8_0}"
NEED=86720111488
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }
sz=$(stat -c%s "$MODEL" 2>/dev/null || echo 0)
[[ "$sz" -eq "$NEED" ]] || { echo "incomplete $MODEL ($sz / $NEED)"; exit 1; }

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="${RADV_PERFTEST:-gpl,sam,nggc}"
unset VK_DRIVER_FILES
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias deepseek4-iq2-amd \
  --device Vulkan0 --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size "$BATCH" --ubatch-size "$UBATCH" \
  --cache-type-k "$CACHE_K" --cache-type-v "$CACHE_V" \
  --threads 32 --threads-batch 32 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp "$TEMP" --top-p "$TOP_P" --top-k "$TOP_K" \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT ctx=$CTX batch=$BATCH ubatch=$UBATCH device=Vulkan0"
