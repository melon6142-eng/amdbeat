#!/bin/bash
set -euo pipefail
OUT="$HOME/models/rocmfp4/flash-next-strix-lean"
LOG="$HOME/logs/dl-flash-strix-lean.log"
mkdir -p "$OUT"
BASE=https://hf-mirror.com/kingjones777/Qwen3.8-Flash-Next-ROCmFP4-STRIX_LEAN-GGUF/resolve/main
for f in \
  Qwen3.8-Flash-Next-Q4_0-ROCmFP4-STRIX_LEAN-00001-of-00003.gguf \
  Qwen3.8-Flash-Next-Q4_0-ROCmFP4-STRIX_LEAN-00002-of-00003.gguf \
  Qwen3.8-Flash-Next-Q4_0-ROCmFP4-STRIX_LEAN-00003-of-00003.gguf
do
  echo "[$(date -Is)] GET $f" | tee -a "$LOG"
  if [ -f "$OUT/$f" ] && [ "$(stat -c%s "$OUT/$f")" -eq 0 ]; then rm -f "$OUT/$f"; fi
  wget -4 -c --tries=0 --timeout=30 --read-timeout=60 --progress=dot:giga -O "$OUT/$f" "$BASE/$f" 2>&1 | tee -a "$LOG"
  echo "[$(date -Is)] OK $f $(stat -c%s "$OUT/$f")" | tee -a "$LOG"
done
echo "[$(date -Is)] FLASH STRIX_LEAN COMPLETE" | tee -a "$LOG"
