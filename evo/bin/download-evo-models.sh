#!/bin/bash
set -euo pipefail
LOGDIR="$HOME/logs"
mkdir -p "$LOGDIR"
log(){ echo "[$(date -Is)] $*" | tee -a "$LOGDIR/download-evo-models.log"; }
WGET=(wget -c --retry-connrefused --tries=0 --timeout=30 --read-timeout=60 --progress=dot:giga)

dl(){
  local url="$1" outdir="$2"
  mkdir -p "$outdir"
  local name=$(basename "$url")
  log "GET $name"
  "${WGET[@]}" -O "$outdir/$name" "$url" 2>&1 | tee -a "$LOGDIR/dl-$(echo "$name"|tr '/ ' '__').log"
  log "OK $name size=$(stat -c%s "$outdir/$name")"
}

# Flash-Next STRIX_LEAN shards
BASE_LEAN=https://huggingface.co/kingjones777/Qwen3.8-Flash-Next-ROCmFP4-STRIX_LEAN-GGUF/resolve/main
dl "$BASE_LEAN/Qwen3.8-Flash-Next-Q4_0-ROCmFP4-STRIX_LEAN-00001-of-00003.gguf" "$HOME/models/rocmfp4/flash-next-strix-lean"
dl "$BASE_LEAN/Qwen3.8-Flash-Next-Q4_0-ROCmFP4-STRIX_LEAN-00002-of-00003.gguf" "$HOME/models/rocmfp4/flash-next-strix-lean"
dl "$BASE_LEAN/Qwen3.8-Flash-Next-Q4_0-ROCmFP4-STRIX_LEAN-00003-of-00003.gguf" "$HOME/models/rocmfp4/flash-next-strix-lean"

# Qwen27 FAST full (~13.55G) — remove truncated
rm -f "$HOME/models/rocmfp4/qwen27/Qwen3.8-27B-ROCmFP4-FAST.gguf"
BASE27=https://huggingface.co/julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF/resolve/main
dl "$BASE27/Qwen3.8-27B-ROCmFP4-FAST.gguf" "$HOME/models/rocmfp4/qwen27"
SZ=$(stat -c%s "$HOME/models/rocmfp4/qwen27/Qwen3.8-27B-ROCmFP4-FAST.gguf")
if [ "$SZ" -lt 14000000000 ]; then log "ERROR qwen27 size $SZ"; exit 2; fi

# Qwen27 STRIX_LEAN quality
dl "$BASE27/Qwen3.8-27B-ROCmFP4-STRIX_LEAN.gguf" "$HOME/models/rocmfp4/qwen27-strix-lean"

log "ALL DOWNLOADS FINISHED"
ls -lh "$HOME/models/rocmfp4/flash-next-strix-lean" "$HOME/models/rocmfp4/qwen27" "$HOME/models/rocmfp4/qwen27-strix-lean" | tee -a "$LOGDIR/download-evo-models.log"
