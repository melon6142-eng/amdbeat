#!/bin/bash
# Best R9700 dense 27B (2026-10-21): llama.cpp master ROCm gfx1201 + UD-Q4_K_XL + MTP n=3
set -euo pipefail
BIN=${LLAMA_BIN:-$HOME/code/llama.cpp-master/build-hip/bin}
MODEL=${MODELS_DIR:-$HOME/models}/gguf/Qwen3.8-27B/Qwen3.8-27B-UD-Q4_K_XL.gguf
MTP=${MODELS_DIR:-$HOME/models}/gguf/Qwen3.8-27B/mtp-Qwen3.8-27B-Q4_0.gguf
LOG=$HOME/logs/serve-qwen38-27b-ud-q6k.log
PIDF=$HOME/logs/serve-qwen38-27b-ud-q6k.pid
export LD_LIBRARY_PATH="$BIN:${LD_LIBRARY_PATH:-}" HIP_VISIBLE_DEVICES=0
if ss -tnl sport = :8216 2>/dev/null | grep -q 8216; then echo "port busy"; exit 1; fi
cd "$BIN"
setsid nohup ./llama-server -m "$MODEL" --host 0.0.0.0 --port 8216 -a qwen3.8-27b-ud-q4kxl-mtp \
  -ngl 99 -fa on -c 65536 -b 2048 -ub 2048 -ctk f16 -ctv f16 --jinja \
  --spec-type draft-mtp -md "$MTP" -ngld all --spec-draft-n-max 3 \
  > "$LOG" 2>&1 < /dev/null &
echo $! > "$PIDF"; echo "$(date -Is) started pid=$(cat $PIDF)"
