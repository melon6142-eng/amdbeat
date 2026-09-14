#!/usr/bin/env bash
# Qwen3.8-27B on EVO AMD GTT only. No RTX 4080.
# RADV ICD so Vulkan0 is the APU. Q4_K_M preferred, Q3 if Q4 is missing.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
Q4="$HOME/models/gguf/Qwen3.8-27B/Qwen3.8-27B-Q4_K_M.gguf"
Q3="$HOME/models/gguf/Qwen3.8-27B/Qwen3.8-27B-Q3_K_M.gguf"
NEED_Q4=17743780512
NEED_Q3=14210448032
if [[ -z "${QWEN_GGUF:-}" && -s "$Q4" && $(stat -c%s "$Q4") -eq $NEED_Q4 ]]; then
  MODEL=$Q4
  NEED=$NEED_Q4
  ALIAS=qwen38-27b-q4-amd
else
  MODEL="${QWEN_GGUF:-$Q3}"
  NEED=$NEED_Q3
  ALIAS=qwen38-27b-q3-amd
fi
LOG="${HOME}/logs/serve-qwen27-amd.log"
PORT="${PORT:-8080}"
CTX="${CTX:-262144}"
PARALLEL="${PARALLEL:-4}"
if [[ -z "${BATCH:-}" ]]; then
  if [[ "$PARALLEL" -eq 1 ]]; then BATCH=2048; else BATCH=256; fi
fi
if [[ -z "${UBATCH:-}" ]]; then
  if [[ "$PARALLEL" -eq 1 ]]; then UBATCH=512; else UBATCH=64; fi
fi
TEMP="${TEMP:-0.7}"
TOP_P="${TOP_P:-0.8}"
TOP_K="${TOP_K:-20}"
CACHE_K="${CACHE_K:-q8_0}"
CACHE_V="${CACHE_V:-q8_0}"
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
  --host 0.0.0.0 --port "$PORT" --alias "$ALIAS" \
  --device Vulkan0 --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$((CTX * PARALLEL))" --kv-unified-per-slot "$CTX" --parallel "$PARALLEL" \
  --batch-size "$BATCH" --ubatch-size "$UBATCH" \
  --cache-type-k "$CACHE_K" --cache-type-v "$CACHE_V" \
  --threads 8 --threads-batch 8 \
  --no-cache-prompt --no-cache-idle-slots --cache-ram 0 \
  --jinja --no-webui --metrics \
  --temp "$TEMP" --top-p "$TOP_P" --top-k "$TOP_K" \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT alias=$ALIAS model=$(basename "$MODEL") device=Vulkan0(AMD) parallel=$PARALLEL ctx=$CTX batch=$BATCH ubatch=$UBATCH"
