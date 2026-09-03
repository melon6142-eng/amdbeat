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
exec $HOME/code/llama.cpp-rocmfpx/build/bin/llama-server  -m $HOME/models/rocmfp4/qwen27/Qwen3.8-27B-ROCmFP4-FAST.gguf  -md $HOME/models/rocmfp4/dflash2/Qwen3.8-27B-DFlash2-Q4_0_ROCMFP4_FAST.gguf  --spec-type draft-dflash --spec-draft-adaptive  --spec-draft-n-min 3 --spec-draft-n-max 7 --spec-draft-ngl 99  -ngl 999 -fa on -b 2048 -ub 512 -c 32768  -ctk q8_0 -ctv q8_0 --host 0.0.0.0 --port 8080 --sleep-idle-seconds 300 --jinja
