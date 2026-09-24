#!/usr/bin/env bash
set -euo pipefail
BACKEND="${1:-strix}"  # strix | unsloth
PORT="${PORT:-8081}"
MODEL="$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf"
OUT="$HOME/logs/bench-glm53-s/fast-20260924"
mkdir -p "$OUT"
unset VK_ICD_FILENAMES
case "$BACKEND" in
  strix)
    ROOT="$HOME/src/strix-llama.cpp/build-vulkan"
    BIN="$ROOT/bin/llama-server"
    export LD_LIBRARY_PATH="$ROOT/bin:$ROOT"
    LOG="$OUT/vk-strix11060-full.log"
    ALIAS="glm-vk-strix11060"
    ;;
  unsloth)
    ROOT="$HOME/opt/unsloth-llama-b10698-mix-vulkan"
    BIN="$ROOT/llama-server"
    export LD_LIBRARY_PATH="$ROOT"
    LOG="$OUT/vk-unsloth10698-full.log"
    ALIAS="glm-vk-unsloth"
    ;;
  *) echo "bad backend"; exit 1;;
esac
for p in $(pgrep -f "$BIN" || true); do kill -9 "$p" 2>/dev/null || true; done
sleep 1
nohup "$BIN" -m "$MODEL" --host 0.0.0.0 --port "$PORT" --alias "$ALIAS" \
  --device Vulkan0 --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size 36864 --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 \
  --cache-reuse 256 \
  --reasoning off --reasoning-budget 0 \
  --jinja --no-webui --metrics --parallel 1 \
  --temp 0.7 --top-p 0.8 --top-k 20 \
  >"$LOG" 2>&1 &
echo "PID=$! backend=$BACKEND port=$PORT log=$LOG"
