#!/usr/bin/env bash
# K2-Horizon-375B MQ87 on EVO AMD-only (Vulkan0).
set -euo pipefail
K2BIN="${K2BIN:-$HOME/code/llama.cpp-k2horizon/build-vulkan/bin}"
BIN="${LLAMA_SERVER:-$K2BIN/llama-server}"
MODEL="${K2_GGUF:-$HOME/models/gguf/K2-Horizon-375B-A23B-MQ87/K2-Horizon-375B-A23B-MQ87-00001-of-00004.gguf}"
LOG="${HOME}/logs/serve-k2-amd.log"
PORT="${PORT:-8080}"
CTX="${CTX:-131072}"
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN — build ~/code/llama.cpp-k2horizon/build-vulkan first"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL — wait for rsync"; exit 1; }
export LD_LIBRARY_PATH="$(dirname "$BIN")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
unset VK_DRIVER_FILES

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
nohup "$BIN" \
  -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  -ngl 999 --no-host --load-mode mmap \
  -dev Vulkan0 -sm layer \
  -c "$CTX" --jinja \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT device=Vulkan0"
echo "Wait: curl -s http://127.0.0.1:${PORT}/v1/models"
