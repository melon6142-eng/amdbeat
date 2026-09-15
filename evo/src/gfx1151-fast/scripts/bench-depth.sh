#!/usr/bin/env bash
# Decode/prefill at context depth. Default 8K,32K. Pass 131072 only when you can wait.
# Usage: bench-depth.sh <arm> [depths]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARM="${1:-vulkan-rocmfpx}"
DEPTHS="${2:-8192,32768}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MODEL="${FLASH_GGUF:-$HOME/models/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf}"
OUT="$ROOT/results/depth-$ARM-$STAMP.jsonl"
mkdir -p "$ROOT/results"
[[ -s $MODEL ]] || { echo "missing $MODEL"; exit 1; }

export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="${RADV_PERFTEST:-gpl,sam,nggc}"
unset VK_DRIVER_FILES

case "$ARM" in
  vulkan-rocmfpx) BIN="${LLAMA_BENCH:-$HOME/code/llama.cpp-rocmfpx/build/bin/llama-bench}"; DEV=Vulkan0 ;;
  vulkan-strix)   BIN="${LLAMA_BENCH:-$HOME/src/strix-llama.cpp/build-vulkan/bin/llama-bench}"; DEV=Vulkan0 ;;
  *) echo "unknown arm $ARM"; exit 1 ;;
esac
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }

echo "arm=$ARM depths=$DEPTHS out=$OUT"
"$BIN" \
  -m "$MODEL" \
  -ngl 99 -fa on \
  -dev "$DEV" \
  --no-host 1 --load-mode mmap \
  -b 2048 -ub 512 \
  -ctk q8_0 -ctv q8_0 \
  -p 512 -n 128 -d "$DEPTHS" \
  -r 5 -o jsonl \
  >"$OUT"
echo "wrote $OUT"
