#!/usr/bin/env bash
set -euo pipefail
DIR="$HOME/models/gguf/Qwen3.8-27B"
FILE="$DIR/Qwen3.8-27B-Q3_K_M.gguf"
URL="https://huggingface.co/qtum/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-Q3_K_M.gguf"
NEED=14210448032
mkdir -p "$DIR" "$HOME/logs"
exec wget -4 -c --tries=0 --timeout=30 --read-timeout=60 --progress=dot:giga \
  -e use_proxy=yes -e https_proxy=127.0.0.1:7890 \
  -O "$FILE" "$URL"
