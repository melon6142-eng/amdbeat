#!/bin/bash
# China mirror: ModelScope (hf-mirror/huggingface.co timed out from EVO 2026-10-21)
exec 9>/tmp/dl-qwen38-27b-gguf.lock
flock -n 9 || { echo "$(date -Is) another instance holds lock"; exit 0; }
OUT="$HOME/models/gguf/Qwen3.8-27B"
LOG="$HOME/logs/dl-qwen38-27b-gguf.log"
mkdir -p "$OUT" "$LOGDIR" 2>/dev/null; mkdir -p "$OUT"
log(){ echo "$(date -Is) $*" | tee -a "$LOG"; }

dl(){
  local url="$1" dest="$2" expect="$3"
  mkdir -p "$(dirname "$dest")"
  local name=$(basename "$dest")
  if [ -f "$dest.done" ]; then log "SKIP $name already done"; return 0; fi
  for i in $(seq 1 400); do
    cur=$(stat -c %s "$dest" 2>/dev/null || echo 0)
    if [ -n "$expect" ] && [ "$cur" -ge "$expect" ]; then break; fi
    log "GET $name try=$i at=$cur"
    curl -4 -sSL -C - --retry 5 --retry-delay 5 --connect-timeout 30 \
      --speed-limit 51200 --speed-time 180 \
      -o "$dest" "$url"
    rc=$?
    cur=$(stat -c %s "$dest" 2>/dev/null || echo 0)
    log "curl_exit=$rc size=$cur expect=$expect"
    if [ -n "$expect" ] && [ "$cur" = "$expect" ]; then break; fi
    # if no expect size, stop when curl succeeded and file non-empty and no growth needed
    if [ -z "$expect" ] && [ $rc -eq 0 ] && [ "$cur" -gt 1000000 ]; then break; fi
    sleep 5
  done
  cur=$(stat -c %s "$dest" 2>/dev/null || echo 0)
  if [ -n "$expect" ] && [ "$cur" != "$expect" ]; then
    log "FAIL $name size=$cur expected=$expect"
    return 1
  fi
  echo "$cur $(date -Is)" > "$dest.done"
  log "DONE $name size=$cur"
}

log "START downloads via ModelScope"
# unsloth UD-Q6_K
dl "https://modelscope.cn/models/unsloth/Qwen3.8-27B-GGUF/resolve/master/Qwen3.8-27B-UD-Q6_K.gguf" \
   "$OUT/Qwen3.8-27B-UD-Q6_K.gguf" 21983677344
# unsloth MTP
dl "https://modelscope.cn/models/unsloth/Qwen3.8-27B-GGUF/resolve/master/MTP/mtp-Qwen3.8-27B-Q4_0.gguf" \
   "$OUT/mtp-Qwen3.8-27B-Q4_0.gguf" 1369590656
# bartowski Q6_K compare
dl "https://modelscope.cn/models/bartowski/Qwen3.8-27B-GGUF/resolve/master/Qwen3.8-27B-Q6_K.gguf" \
   "$OUT/bartowski-Qwen3.8-27B-Q6_K.gguf" 23860565728
log "ALL DOWNLOADS FINISHED"
ls -lah "$OUT" | tee -a "$LOG"
