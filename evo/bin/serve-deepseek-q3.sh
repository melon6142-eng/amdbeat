#!/bin/bash
if [[ "${EVO_WAKE_OK:-}" != 1 ]] && ps -C llama-server --no-headers 2>/dev/null | grep -q .; then
  echo "REFUSE" >&2; exit 1
fi
set -euo pipefail
export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="${RADV_PERFTEST:-gpl,sam,nggc}"
exec $HOME/code/llama.cpp-rocmfpx/build/bin/llama-server \
  -m $HOME/models/rocmfp4/deepseek-v4-flash-q3/DeepSeek-V4-Flash-0731-Q3-ROCmFP4-00001-of-00004.gguf \
  -dev Vulkan0 -ngl 999 -fa on -fit off \
  --load-mode mmap \
  -c 8192 -b 1024 -ub 512 -t 16 --poll 50 \
  --sleep-idle-seconds 300 \
  --host 0.0.0.0 --port 8084 --jinja \
  --reasoning-format deepseek \
  --reasoning off
