#!/bin/bash
set -euo pipefail
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export NO_PROXY=127.0.0.1,localhost
DESTDIR=$MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS
LOG=~/logs/dl-deepseek-iq2-mirror.log
URL=https://huggingface.co/antirez/deepseek-v4-gguf/resolve/main/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf
NAME=DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf
EXPECT=86720111488
mkdir -p "$DESTDIR"
echo "[$(date -Is)] START via KR proxy $URL" | tee -a "$LOG"
wget -4 -c --tries=0 --timeout=30 --read-timeout=60 --progress=dot:giga \
  -e use_proxy=yes -e https_proxy=127.0.0.1:7890 \
  -O "$DESTDIR/$NAME" "$URL" 2>&1 | tee -a "$LOG"
SZ=$(stat -c%s "$DESTDIR/$NAME")
echo "[$(date -Is)] size=$SZ expect=$EXPECT" | tee -a "$LOG"
[ "$SZ" -eq "$EXPECT" ]
