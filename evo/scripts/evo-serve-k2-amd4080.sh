#!/usr/bin/env bash
# K2-Horizon-375B MQ87 on EVO: fill RTX 4080 (~16Gi) + rest on AMD GTT.
# Default -ts 82,18 ≈ 16 GiB of ~87 GiB on the 4080. OOM: TS=90,10.
#
# Needs IFM llama.cpp model/K2Horizon (pin 35999d101). Production
# llama.cpp-rocmfpx refuses the arch. Isolated tree:
#   ~/code/llama.cpp-k2horizon/build-vulkan
set -euo pipefail
K2BIN="${K2BIN:-$HOME/code/llama.cpp-k2horizon/build-vulkan/bin}"
BIN="${LLAMA_SERVER:-$K2BIN/llama-server}"
MODEL="${K2_GGUF:-$HOME/models/gguf/K2-Horizon-375B-A23B-MQ87/K2-Horizon-375B-A23B-MQ87-00001-of-00004.gguf}"
LOG="${HOME}/logs/serve-k2-amd4080.log"
PORT="${PORT:-8080}"
CTX="${CTX:-16384}"
TS="${TS:-82,18}"
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN — build ~/code/llama.cpp-k2horizon/build-vulkan first"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL — wait for rsync"; exit 1; }
export LD_LIBRARY_PATH="$(dirname "$BIN")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
unset VK_ICD_FILENAMES

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
# Vulkan0=4080 (~16Gi), Vulkan1=AMD RADV (~221Gi visible)
nohup "$BIN" \
  -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  -ngl 999 --no-host --load-mode mmap \
  -dev Vulkan1,Vulkan0 -sm layer -ts "$TS" \
  -c "$CTX" --jinja \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT ts=$TS (AMD,4080)"
echo "Wait: curl -s http://127.0.0.1:${PORT}/v1/models"
