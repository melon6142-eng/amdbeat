#!/usr/bin/env bash
# DeepSeek-V4-Flash IQ2 (standard GGUF, deepseek4) — EVO host scatters:
#   4080 ~15 GiB (Vulkan0) + AMD rest (Vulkan1) + Mac MTL0 overflow via RPC.
# ROCmFP4 101G is EVO-only; Metal/MIX cannot read file_type 119.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${DS_GGUF:-$HOME/models/gguf/DeepSeek-V4-Flash-IQ2XXS/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf}"
LOG="${HOME}/logs/serve-deepseek-iq2-cluster.log"
PORT="${PORT:-8080}"
CTX="${CTX:-4096}"
# Must name RPC0 in --device or the 3rd TS slot is ignored and 4080 eats Mac's share.
# 16% of 81G ≈ 13 GiB on 4080 — leave ~3 GiB for the 731 MiB compute buffer + KV.
TS="${TS:-72,16,12}"
RPC="${RPC:-<host>:50052}"
mkdir -p "$(dirname "$LOG")"
NEED=86720111488
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }
sz=$(stat -c%s "$MODEL" 2>/dev/null || echo 0)
[[ "$sz" -eq "$NEED" ]] || { echo "incomplete $MODEL ($sz / $NEED)"; exit 1; }

pkill -x llama-server || true
sleep 2
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GGML_RPC_NO_RDMA=1

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias deepseek4-iq2-cluster \
  --rpc "$RPC" \
  --device Vulkan1,Vulkan0,RPC0 --split-mode layer --tensor-split "$TS" \
  --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT ts=$TS rpc=$RPC"
echo "Wait: curl -s http://127.0.0.1:${PORT}/health"
