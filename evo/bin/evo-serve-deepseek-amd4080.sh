#!/usr/bin/env bash
# DeepSeek-V4-Flash Q3 ROCmFP4 on EVO AMD+4080. Same 101G shards as AMD-only.
# rocmfpx required. Vulkan1=AMD, Vulkan0=4080 when ICD unset.
# Same batch/KV as evo-serve-deepseek-q3-amd.sh so speed is comparable.
set -euo pipefail
BIN="${LLAMA_SERVER:-$HOME/code/llama.cpp-rocmfpx/build/bin/llama-server}"
MODEL="${DS_GGUF:-$HOME/models/rocmfp4/deepseek-v4-flash-q3/DeepSeek-V4-Flash-0731-Q3-ROCmFP4-00001-of-00004.gguf}"
LOG="${HOME}/logs/serve-deepseek-amd4080.log"
PORT="${PORT:-8080}"
CTX="${CTX:-32768}"
TS="${TS:-56,8}"
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL"; exit 1; }

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
unset VK_ICD_FILENAMES

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias DeepSeek-V4-Flash-0731-Q3-ROCmFP4 \
  --device Vulkan1,Vulkan0 --split-mode layer --tensor-split "$TS" \
  --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 16 --threads-batch 16 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT device=Vulkan1,Vulkan0 ts=$TS ctx=$CTX"
