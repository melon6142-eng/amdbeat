#!/usr/bin/env bash
set +e
OUT="$HOME/logs/bench-glm53-s/fast-20260924"
mkdir -p "$OUT"
MODEL="$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf"
ROCM="$HOME/opt/unsloth-llama-b10698-mix-rocm-gfx1151"
VK="$HOME/opt/unsloth-llama-b10698-mix-vulkan"
STRIX_HIP="$HOME/src/strix-llama.cpp/build-hip/bin"
exec > >(tee -a "$OUT/load-strategies.log") 2>&1
run_probe() {
  local name="$1"; shift
  echo "===== $name $(date) ====="
  echo "CMD: $*"
  timeout 240s "$@" -m "$MODEL" -c 1024 -n 1 -p "Say hi in 5 words." --no-display-prompt -fa on -lv 1 2>&1 | tee "$OUT/probe-$name.log" | tail -40
  echo "EXIT_$name=${PIPESTATUS[0]} $(date)"
  pkill -9 -f "llama-cli.*GLM" 2>/dev/null
  sleep 3
}
pkill -9 -f "llama-cli.*GLM" 2>/dev/null
pkill -9 -f llama-server 2>/dev/null
sleep 2
unset VK_ICD_FILENAMES
export LD_LIBRARY_PATH="$ROCM"
run_probe rocm-fit "$ROCM/llama-cli" -ngl 99 -dev ROCm0 -fit on
run_probe rocm-ncmoe "$ROCM/llama-cli" -ngl 99 -dev ROCm0 -fit off --n-cpu-moe 999 -lm mmap
export HSA_XNACK=1
run_probe rocm-xnack-fit "$ROCM/llama-cli" -ngl 99 -dev ROCm0 -fit on
unset HSA_XNACK
export LD_LIBRARY_PATH="$VK"
run_probe vk-fit "$VK/llama-cli" -ngl 99 -dev Vulkan0 -fit on --no-host -lm mmap
run_probe vk-ncmoe "$VK/llama-cli" -ngl 99 -dev Vulkan0 -fit off --n-cpu-moe 999 --no-host -lm mmap
if [[ -x $STRIX_HIP/llama-cli ]]; then
  export LD_LIBRARY_PATH="$HOME/src/strix-llama.cpp/build-hip/bin:$HOME/src/strix-llama.cpp/build-hip"
  run_probe strix-hip-fit "$STRIX_HIP/llama-cli" -ngl 99 -fit on
fi
echo ALL_DONE $(date)
