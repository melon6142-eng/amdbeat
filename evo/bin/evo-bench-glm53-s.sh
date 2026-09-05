#!/usr/bin/env bash
# S-class GLM A/B on EVO — same flags as kjaiswal: -p 512 -n 128 -r 3 -ngl 99
#
# 1) AMD-only ROCm (Hilbert ceiling)
# 2) Max-4080 Vulkan: 4080 is device 0 (scratch/small tensors + filled VRAM)
#
# 4080 is eGPU — do not use -sm tensor/row (PCIe tax). Layer split + fill.
# TS default 20,80 ≈ 16 GiB of 81 GiB on the 4080. OOM → retry 18,82.
set -euo pipefail
ROCM="${ROCM:-$HOME/opt/unsloth-llama-b10698-mix-rocm-gfx1151}"
VULKAN="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
MODEL="${GLM_GGUF:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
OUTDIR="${OUTDIR:-$HOME/logs/bench-glm53-s}"
STAMP="${STAMP:-$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"
[[ -s $MODEL ]] || { echo "missing $MODEL"; exit 1; }

BENCH_FLAGS=(-m "$MODEL" -ngl 99 -p 512 -n 128 -r 3 -fa on)

echo "=== devices ==="
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$VULKAN"
"$VULKAN/llama-cli" --list-devices 2>&1 | sed -n '/Available devices/,+5p' || true
export LD_LIBRARY_PATH="$ROCM"
"$ROCM/llama-cli" --list-devices 2>&1 | sed -n '/Available devices/,+3p' || true

echo
echo "=== 1/2 Vulkan AMD-only (ROCm 82Gi one-shot cudaMalloc OOM on this MIX) ==="
export LD_LIBRARY_PATH="$VULKAN"
unset VK_ICD_FILENAMES
"$VULKAN/llama-bench" "${BENCH_FLAGS[@]}" -dev Vulkan1 --no-host 1 -lm mmap \
  | tee "$OUTDIR/vk-amd-$STAMP.txt"

echo
echo "=== 2/3 AMD-main, fill 4080 (llama-bench uses / not comma) ==="
"$VULKAN/llama-bench" "${BENCH_FLAGS[@]}" \
  -dev Vulkan1/Vulkan0 -sm layer -ts 84/16 --no-host 1 -lm mmap \
  | tee "$OUTDIR/vk-amdmain-ts84_16-$STAMP.txt"

echo
echo "=== 3/3 4080-main, light weights (scratch/KV on 4080) ==="
"$VULKAN/llama-bench" "${BENCH_FLAGS[@]}" \
  -dev Vulkan0/Vulkan1 -sm layer -ts 8/92 --no-host 1 -lm mmap \
  | tee "$OUTDIR/vk-4080main-ts8_92-$STAMP.txt"

echo
echo "=== nvidia after ==="
nvidia-smi --query-gpu=name,memory.used,utilization.gpu --format=csv || true
echo "logs: $OUTDIR"
