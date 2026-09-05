#!/usr/bin/env bash
# EVO RPC workers — llama.cpp discussion #9257:
#   one ggml-rpc-server per GPU, mixed backends OK.
# Do NOT run a worker for a GPU the host already owns.
# Current MIX has no --mem; the server advertises the device it binds.
set -euo pipefail
VULKAN="${VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
ROCM="${ROCM:-$HOME/opt/unsloth-llama-b10698-mix-rocm-gfx1151}"
LOGDIR="${LOGDIR:-$HOME/logs}"
mkdir -p "$LOGDIR"

# #9257: local llama-server and rpc-server cannot share a GPU
pkill -f 'llama-server' || true
pkill -f 'ggml-rpc-server' || true
sleep 2

# AMD GTT ~120 GiB — ROCm0 (same MIX commit as Mac/Spark)
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$ROCM"
nohup "$ROCM/ggml-rpc-server" \
  -H 0.0.0.0 -p 50052 -d ROCm0 -c \
  >"$LOGDIR/rpc-amd.log" 2>&1 &
echo "AMD  ROCm0   :50052  pid=$!  log=$LOGDIR/rpc-amd.log"

# 4080 16 GiB — Vulkan0 only (do not also expose Vulkan1)
export LD_LIBRARY_PATH="$VULKAN"
nohup "$VULKAN/ggml-rpc-server" \
  -H 0.0.0.0 -p 50053 -d Vulkan0 -c \
  >"$LOGDIR/rpc-4080.log" 2>&1 &
echo "4080 Vulkan0 :50053  pid=$!  log=$LOGDIR/rpc-4080.log"
echo "LAN only. Host: --rpc EVO_HOST:50052,EVO_HOST:50053"
