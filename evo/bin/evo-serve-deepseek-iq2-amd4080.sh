#!/usr/bin/env bash
# DeepSeek-V4-Flash IQ2XXS on EVO AMD+4080. Standard GGUF — MIX Vulkan can see both.
# Do not use ROCmFP4 here. Do not pkill other servers; only this port.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${DS_GGUF:-$HOME/models/gguf/DeepSeek-V4-Flash-IQ2XXS/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf}"
LOG="${HOME}/logs/serve-deepseek-iq2-amd4080.log"
PORT="${PORT:-8080}"
CTX="${CTX:-32768}"
TS="${TS:-86,14}"
NEED=86720111488
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }
sz=$(stat -c%s "$MODEL" 2>/dev/null || echo 0)
[[ "$sz" -eq "$NEED" ]] || { echo "incomplete $MODEL ($sz / $NEED)"; exit 1; }

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias deepseek4-iq2-amd4080 \
  --device Vulkan1,Vulkan0 --split-mode layer --tensor-split "$TS" \
  --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT device=Vulkan1,Vulkan0 ts=$TS ctx=$CTX"
