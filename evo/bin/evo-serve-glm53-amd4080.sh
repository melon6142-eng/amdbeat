#!/usr/bin/env bash
# GLM-5.3-Flash AJ-IQ2_XXS on EVO: fill RTX 4080 (~16Gi) + rest on AMD GTT.
#
# ROCm gfx1151 binary cannot see the 4080. Hybrid = Unsloth MIX *Vulkan*
# (has glm5next) with both devices. Hilbert's ROCm-only 14.63 t/s is the
# AMD-only speed ceiling; this path trades some of that to actually use the 4080.
#
# Placement: 4080 ~15 GiB, rest AMD (Vulkan1), then Mac MTL0 via RPC= if set.
# llama.cpp names (not MLX): Vulkan0=4080, Vulkan1=AMD RADV, ROCm0=AMD HIP, MTL0=Mac Metal.
# RPC=<host>:50052  → attach Mac overflow. TS then 82,18,0
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${GLM_GGUF:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
LOG="${HOME}/logs/serve-glm53-amd4080.log"
PORT="${PORT:-8080}"
CTX="${CTX:-4096}"
TS="${TS:-82,18}"
RPC="${RPC:-}"
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN — extract Unsloth MIX linux-x64-vulkan tarball to $MIX"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL — wait for rsync"; exit 1; }

pkill -f 'llama-server' || true
sleep 2
# MIX Vulkan: system ICD (NVIDIA + RADV). Do not pin Nathanw ICD.
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GGML_RPC_NO_RDMA=1
RPC_ARGS=()
if [[ -n "$RPC" ]]; then
  RPC_ARGS+=(--rpc "$RPC")
  [[ "$TS" == "82,18" ]] && TS=82,18,0
fi

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias glm53-flash-aj-iq2-4080 \
  --device Vulkan1,Vulkan0 --split-mode layer --tensor-split "$TS" \
  "${RPC_ARGS[@]}" \
  --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size "$CTX" --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 \
  --reasoning off --reasoning-budget 0 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! log=$LOG port=$PORT ctx=$CTX ts=$TS rpc=${RPC:-none}"
echo "Mac overflow: RPC=<host>:50052 $0"
echo "Wait: curl -s http://127.0.0.1:${PORT}/health"
