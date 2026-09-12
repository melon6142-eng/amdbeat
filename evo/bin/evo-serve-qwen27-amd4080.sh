#!/usr/bin/env bash
# Qwen3.8-27B Q3 on EVO AMD+4080. Same file as 4080-only / AMD-only compare.
# MIX Vulkan: Vulkan0=4080, Vulkan1=AMD. Start candidate 4/6 (AMD,4080).
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${QWEN_GGUF:-$HOME/models/gguf/Qwen3.8-27B/Qwen3.8-27B-Q3_K_M.gguf}"
LOG="${HOME}/logs/serve-qwen27-amd4080.log"
PORT="${PORT:-8080}"
CTX="${CTX:-16384}"
PARALLEL="${PARALLEL:-6}"
TS="${TS:-4,6}"
NEED=14210448032
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }
sz=$(stat -c%s "$MODEL" 2>/dev/null || echo 0)
[[ "$sz" -eq "$NEED" ]] || { echo "incomplete $MODEL ($sz / $NEED)"; exit 1; }

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias qwen38-27b-amd4080 \
  --device Vulkan1,Vulkan0 --split-mode layer --tensor-split "$TS" \
  --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$((CTX * PARALLEL))" --kv-unified-per-slot "$CTX" --parallel "$PARALLEL" \
  --batch-size 256 --ubatch-size 64 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 8 --threads-batch 8 \
  --no-cache-prompt --no-cache-idle-slots --cache-ram 0 \
  --jinja --no-webui --metrics \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT device=Vulkan1,Vulkan0 ts=$TS parallel=$PARALLEL ctx=$CTX"
