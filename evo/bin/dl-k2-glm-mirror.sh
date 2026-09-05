#!/bin/bash
set -euo pipefail
LOG=~/logs/dl-mirror-evo.log
exec > >(tee -a "$LOG") 2>&1
echo "[$(date -Iseconds)] START mirror downloads"
BASE_K2=https://hf-mirror.com/Baekpica/K2-Horizon-375B-A23B-Mixed-Quant-GGUF/resolve/main
DEST_K2=$MODELS_DIR/gguf/K2-Horizon-375B-A23B-MQ87
BASE_GLM=https://hf-mirror.com/vcruz305/GLM-5.3-Flash-GGUF/resolve/main
DEST_GLM=$MODELS_DIR/gguf/GLM-5.3-Flash-GGUF
mkdir -p "$DEST_K2" "$DEST_GLM"
dl() {
  local url="$1" out="$2"
  echo "[$(date -Iseconds)] GET $out"
  # resume; 8 connections if aria2 exists else curl
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -c -x 8 -s 8 -k 1M -d "$(dirname "$out")" -o "$(basename "$out")" "$url"
  else
    curl -L --retry 20 --retry-delay 5 -C - -o "$out" "$url"
  fi
  echo "[$(date -Iseconds)] OK $(ls -lh "$out" | awk '{print $5,$9}')"
}
# small first
dl "$BASE_K2/MQ87-SHA256SUMS" "$DEST_K2/MQ87-SHA256SUMS"
# K2 shards (smallest first for smoke)
for f in \
  K2-Horizon-375B-A23B-MQ87-00004-of-00004.gguf \
  K2-Horizon-375B-A23B-MQ87-00001-of-00004.gguf \
  K2-Horizon-375B-A23B-MQ87-00002-of-00004.gguf \
  K2-Horizon-375B-A23B-MQ87-00003-of-00004.gguf
do
  # remove 0-byte stubs
  if [ -f "$DEST_K2/$f" ] && [ ! -s "$DEST_K2/$f" ]; then rm -f "$DEST_K2/$f"; fi
  dl "$BASE_K2/$f" "$DEST_K2/$f"
done
for f in mmproj-GLM-5.3-Flash-F16.gguf GLM-5.3-Flash-Q2_K.gguf; do
  if [ -f "$DEST_GLM/$f" ] && [ ! -s "$DEST_GLM/$f" ]; then rm -f "$DEST_GLM/$f"; fi
  dl "$BASE_GLM/$f" "$DEST_GLM/$f"
done
echo "[$(date -Iseconds)] ALL_DONE"
