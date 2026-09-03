#!/bin/bash
# REFUSE_DUPLICATE_LLAMA: do not start if another llama-server is already up
if [[ "${EVO_WAKE_OK:-}" != 1 ]] && pgrep -f "llama-server" >/dev/null 2>&1; then
  echo "REFUSE: llama-server already running — use ~/bin/evo-wake-model.sh instead" >&2
  ps -ef | grep llama-server | grep -v grep >&2 || true
  exit 1
fi
set -euo pipefail
export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="${RADV_PERFTEST:-gpl,sam,nggc}"
exec $HOME/code/llama.cpp-rocmfpx/build/bin/llama-server  -m $HOME/models/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf  -ngl 99 -ctk q8_0 -ctv q8_0 -fa on -c 32768 -b 2048 -ub 512  --host 0.0.0.0 --port 8081 --sleep-idle-seconds 300 --jinja
