#!/bin/bash
# Serve unsloth UD-Q6_K on R9700 Vulkan0 port 8216. Do NOT touch 8217.
set -euo pipefail
BIN=$HOME/opt/unsloth-llama-b10698-mix-vulkan
MODEL=$MODELS_DIR/gguf/Qwen3.8-27B/Qwen3.8-27B-UD-Q6_K.gguf
LOG=$HOME/logs/serve-qwen38-27b-ud-q6k.log
PIDF=$HOME/logs/serve-qwen38-27b-ud-q6k.pid
export LD_LIBRARY_PATH="$BIN:${LD_LIBRARY_PATH:-}"

if ss -tnl sport = :8216 2>/dev/null | grep -q 8216; then
  echo "$(date -Is) port 8216 already listening" | tee -a "$LOG"
  exit 1
fi
if [ ! -f "$MODEL" ]; then echo "missing $MODEL"; exit 1; fi
SZ=$(stat -c%s "$MODEL")
[ "$SZ" = "21983677344" ] || { echo "bad size $SZ"; exit 1; }

# kill any stale llama-server on 8216 only (by pidfile)
if [ -f "$PIDF" ]; then
  old=$(cat "$PIDF" || true)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    echo "already running pid $old"; exit 1
  fi
fi

cd "$BIN"
setsid nohup ./llama-server \
  -m "$MODEL" \
  --host 0.0.0.0 --port 8216 \
  -a qwen3.8-27b-ud-q6k \
  -ngl 99 \
  -fa on \
  -c 32768 \
  -ctk q8_0 -ctv q8_0 \
  --jinja \
  --device Vulkan0 \
  --spec-type draft-mtp \
  -md $MODELS_DIR/gguf/Qwen3.8-27B/mtp-Qwen3.8-27B-Q4_0.gguf \
  -devd Vulkan0 -ngld all \
  --spec-draft-n-max 3 \
  > "$LOG" 2>&1 < /dev/null &
echo $! > "$PIDF"
echo "$(date -Is) started pid=$(cat "$PIDF") log=$LOG"
