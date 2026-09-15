#!/usr/bin/env bash
# Tune1: strix-llama Vulkan + Flash-Next STRIX_LEAN. GPU only while measuring.
set -euo pipefail
OUT="${OUT:-$HOME/logs/tune1-flash}"
PORT="${PORT:-8080}"
CTX="${CTX:-131072}"
TEMP=0
GEN=128
LEAN="${FLASH_GGUF:-$HOME/models/rocmfp4/flash-next-strix-lean/Qwen3.8-Flash-Next-Q4_0-ROCmFP4-STRIX_LEAN-00001-of-00003.gguf}"
STX="${LLAMA_SERVER:-$HOME/src/strix-llama.cpp/build-vulkan/bin/llama-server}"
BENCH="${LLAMA_BENCH:-$HOME/src/strix-llama.cpp/build-vulkan/bin/llama-bench}"
HIT="${HIT:-$HOME/scripts/evo-repro-hit.py}"
SERVE="${SERVE:-$HOME/scripts/evo-serve-flash-amd.sh}"
mkdir -p "$OUT"

export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="${RADV_PERFTEST:-gpl,sam,nggc}"
unset VK_DRIVER_FILES

stop_port() {
  fuser -k "${PORT}/tcp" 2>/dev/null || true
  sleep 2
}

wait_health() {
  local deadline=$((SECONDS + 1200))
  while (( SECONDS < deadline )); do
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      echo "health ok"
      return 0
    fi
    sleep 5
  done
  echo "health timeout" >&2
  return 1
}

pair() {
  local name="$1"
  python3 "$HIT" --url "http://127.0.0.1:${PORT}" --model qwen38-flash-next-amd \
    --max-tokens "$GEN" --label cold --out "$OUT/${name}-cold.json"
  python3 "$HIT" --url "http://127.0.0.1:${PORT}" --model qwen38-flash-next-amd \
    --max-tokens "$GEN" --label warm --out "$OUT/${name}-warm.json"
}

echo "=== llama-bench STRIX_LEAN KYUZ0 d0/32k/64k ==="
"$BENCH" \
  -m "$LEAN" \
  -ngl 99 -fa on -dev Vulkan0 \
  --no-host 1 --load-mode mmap \
  -b 2048 -ub 512 -ctk q8_0 -ctv q8_0 \
  -p 0 -n 128 -d 0,32768,65536 -r 1 -o jsonl \
  >"$OUT/lean-bench.jsonl" 2>"$OUT/lean-bench.log"
echo BENCH_DONE

echo "=== API MTP off ==="
stop_port
PORT="$PORT" CTX="$CTX" PARALLEL=1 TEMP="$TEMP" \
  LLAMA_SERVER="$STX" FLASH_GGUF="$LEAN" DRAFT=/dev/null \
  bash "$SERVE"
wait_health
pair mtp-off
stop_port

echo "=== API MTP on ==="
PORT="$PORT" CTX="$CTX" PARALLEL=1 TEMP="$TEMP" \
  LLAMA_SERVER="$STX" FLASH_GGUF="$LEAN" \
  bash "$SERVE"
if wait_health; then
  pair mtp-on
else
  echo MTP_ON_HEALTH_FAIL | tee "$OUT/mtp-on-blocker.txt"
  tail -n 40 "$HOME/logs/serve-flashnext-amd-only.log" | tee "$OUT/mtp-on-tail.txt"
fi
stop_port
echo TUNE1_DONE
