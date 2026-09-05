#!/bin/bash
set -euo pipefail
DESTDIR=$MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS
LOG=~/logs/dl-deepseek-iq2-mirror.log
URL=https://hf-mirror.com/antirez/deepseek-v4-gguf/resolve/main/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf
NAME=DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf
EXPECT=86720111488
mkdir -p "$DESTDIR"
echo "[$(date -Is)] START $NAME" | tee -a "$LOG"
if command -v aria2c >/dev/null 2>&1; then
  aria2c -c -x 8 -s 8 -k 1M -d "$DESTDIR" -o "$NAME" "$URL" 2>&1 | tee -a "$LOG"
else
  wget -4 -c --tries=0 --timeout=30 --read-timeout=60 --progress=dot:giga -O "$DESTDIR/$NAME" "$URL" 2>&1 | tee -a "$LOG"
fi
SZ=$(stat -c%s "$DESTDIR/$NAME")
echo "[$(date -Is)] size=$SZ expect=$EXPECT" | tee -a "$LOG"
if [ "$SZ" -eq "$EXPECT" ]; then
  echo "[$(date -Is)] COMPLETE" | tee -a "$LOG"
else
  echo "[$(date -Is)] INCOMPLETE" | tee -a "$LOG"
  exit 2
fi
