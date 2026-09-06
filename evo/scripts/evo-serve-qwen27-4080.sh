#!/usr/bin/env bash
# Qwen3.8-27B on the 4080 only (Vulkan0). Pair with DeepSeek on Vulkan1.
# Q3_K_M is ~13.2 GiB so 16 GiB card has room for KV. Do not touch Vulkan1.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${QWEN_GGUF:-$HOME/models/gguf/Qwen3.8-27B/Qwen3.8-27B-Q3_K_M.gguf}"
LOG="${HOME}/logs/serve-qwen27-4080.log"
PORT="${PORT:-8081}"
CTX="${CTX:-4096}"
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
  --host 0.0.0.0 --port "$PORT" --alias qwen38-27b-4080 \
  --device Vulkan0 --gpu-layers all --flash-attn on --fit on \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size 256 --ubatch-size 64 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 8 --threads-batch 8 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT device=Vulkan0"
