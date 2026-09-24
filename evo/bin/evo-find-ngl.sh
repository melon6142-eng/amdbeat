#!/usr/bin/env bash
set +e
OUT="$HOME/logs/bench-glm53-s/fast-20260924"
mkdir -p "$OUT"
MODEL="$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf"
ROCM="$HOME/opt/unsloth-llama-b10698-mix-rocm-gfx1151"
VK="$HOME/opt/unsloth-llama-b10698-mix-vulkan"
LOG="$OUT/find-ngl.log"
exec >>"$LOG" 2>&1
echo "START $(date)"
unset VK_ICD_FILENAMES

try_rocm() {
  local ngl="$1"
  local tag="rocm-ngl${ngl}"
  echo "TRY $tag $(date)"
  export LD_LIBRARY_PATH="$ROCM"
  timeout 100s "$ROCM/llama-cli" -m "$MODEL" -ngl "$ngl" -dev ROCm0 -fa on -c 512 -n 1 \
    -p "Hi" --no-display-prompt -lv 0 -fit off \
    >"$OUT/try-$tag.out" 2>&1
  local ec=$?
  if grep -qiE "cudaMalloc failed|out of memory|failed to load|unable to allocate" "$OUT/try-$tag.out"; then
    echo "FAIL_OOM $tag ec=$ec"; return 1
  fi
  if grep -qiE "prompt eval|tokens per second|eval time" "$OUT/try-$tag.out"; then
    echo "OK $tag ec=$ec"
    grep -iE "prompt eval|eval time|tokens per second" "$OUT/try-$tag.out" | tail -5
    return 0
  fi
  echo "FAIL_OTHER $tag ec=$ec"; tail -15 "$OUT/try-$tag.out"; return 1
}

for ngl in 20 40 50 55 60 65 70; do
  try_rocm "$ngl" || true
  sleep 2
done

echo "TRY rocm-cpu-moe $(date)"
export LD_LIBRARY_PATH="$ROCM"
timeout 120s "$ROCM/llama-cli" -m "$MODEL" -ngl 99 -dev ROCm0 -fa on -c 512 -n 1 \
  -p "Hi" --no-display-prompt -lv 0 -fit off --cpu-moe \
  >"$OUT/try-rocm-cpu-moe.out" 2>&1
echo "cpu-moe ec=$?"
grep -iE "cudaMalloc|OOM|prompt eval|eval time|failed|offload|CPU|allocate" "$OUT/try-rocm-cpu-moe.out" | tail -25

export LD_LIBRARY_PATH="$VK"
for ngl in 40 55 60; do
  tag="vk-ngl${ngl}"
  echo "TRY $tag $(date)"
  timeout 100s "$VK/llama-cli" -m "$MODEL" -ngl "$ngl" -dev Vulkan0 -fa on -c 512 -n 1 \
    -p "Hi" --no-display-prompt -lv 0 -fit off --no-host -lm mmap \
    >"$OUT/try-$tag.out" 2>&1
  ec=$?
  if grep -qiE "prompt eval|tokens per second|eval time" "$OUT/try-$tag.out"; then
    echo "OK $tag ec=$ec"
    grep -iE "prompt eval|eval time|tokens per second" "$OUT/try-$tag.out" | tail -5
  else
    echo "FAIL $tag ec=$ec"
    grep -iE "error|failed|OOM|DeviceLost|memory|allocate" "$OUT/try-$tag.out" | tail -10
  fi
  sleep 2
done
echo ALL_DONE $(date)
