#!/bin/bash
# Wait for UD-Q6_K download, then serve on 8216. Resume bartowski after.
exec 9>/tmp/watch-qwen38-27b-go.lock
flock -n 9 || exit 0
OUT=$MODELS_DIR/gguf/Qwen3.8-27B
UD=$OUT/Qwen3.8-27B-UD-Q6_K.gguf
EXPECT=21983677344
LOG=$HOME/logs/watch-qwen38-27b-go.log
STATUS=$HOME/lab-notes/qwen38-27b-status.txt
log(){ echo "$(date -Is) $*" | tee -a "$LOG"; }

log "watching $UD"
while true; do
  cur=$(stat -c%s "$UD" 2>/dev/null || echo 0)
  if [ "$cur" = "$EXPECT" ]; then
    echo "$cur $(date -Is)" > "$UD.done"
    log "UD complete size=$cur"
    break
  fi
  # stall detect: if no curl for UD and incomplete, restart
  if ! pgrep -f "Qwen3.8-27B-UD-Q6_K.gguf" >/dev/null 2>&1; then
    if [ "$cur" -lt "$EXPECT" ]; then
      log "UD curl missing at $cur — restarting curl"
      setsid nohup curl -4 -sSL -C - --retry 5 --retry-delay 5 --connect-timeout 30 \
        --speed-limit 51200 --speed-time 180 \
        -o "$UD" \
        https://modelscope.cn/models/unsloth/Qwen3.8-27B-GGUF/resolve/master/Qwen3.8-27B-UD-Q6_K.gguf \
        >> $HOME/logs/dl-ud-retry.log 2>&1 < /dev/null &
    fi
  fi
  log "progress $cur / $EXPECT ($(( 100*cur/EXPECT ))%)"
  sleep 60
done

# ensure 8217 untouched; stop anything that might conflict on 8216
if ss -tnl 2>/dev/null | grep -q ':8216'; then
  log "8216 still listening — abort serve"
  echo "FAIL port busy" > "$STATUS"
  exit 1
fi

log "starting llama-server"
$HOME/bin/serve-qwen38-27b-ud-q6k.sh | tee -a "$LOG"

# wait for /v1/models
ok=0
for i in $(seq 1 120); do
  if curl -sS --max-time 3 http://127.0.0.1:8216/v1/models 2>/dev/null | grep -q qwen3.8-27b-ud-q6k; then
    ok=1; log "models ok at try $i"; break
  fi
  sleep 5
done
if [ "$ok" != 1 ]; then
  log "FAIL models never ready"
  echo "FAIL models" > "$STATUS"
  exit 1
fi

# smoke chat
SMOKE=$(curl -sS --max-time 120 http://127.0.0.1:8216/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-ud-q6k","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":16,"temperature":0}' 2>&1)
log "smoke=$SMOKE"
echo "$SMOKE" > $HOME/logs/smoke-qwen38-27b-ud-q6k.json

# resume bartowski if incomplete
B=$OUT/bartowski-Qwen3.8-27B-Q6_K.gguf
BE=23860565728
bc=$(stat -c%s "$B" 2>/dev/null || echo 0)
if [ "$bc" != "$BE" ] && ! pgrep -f "bartowski-Qwen3.8-27B-Q6_K.gguf" >/dev/null 2>&1; then
  log "resuming bartowski at $bc"
  setsid nohup curl -4 -sSL -C - --retry 5 --retry-delay 5 --connect-timeout 30 \
    --speed-limit 51200 --speed-time 180 \
    -o "$B" \
    https://modelscope.cn/models/bartowski/Qwen3.8-27B-GGUF/resolve/master/Qwen3.8-27B-Q6_K.gguf \
    >> $HOME/logs/dl-bartowski-qwen38.log 2>&1 < /dev/null &
fi

# MTP done marker if complete
M=$OUT/mtp-Qwen3.8-27B-Q4_0.gguf
ME=1369590656
mc=$(stat -c%s "$M" 2>/dev/null || echo 0)
[ "$mc" = "$ME" ] && echo "$mc $(date -Is)" > "$M.done"

{
  echo "status=UP"
  echo "time=$(date -Is)"
  echo "endpoint=http://EVO_HOST:8216/v1"
  echo "alias=qwen3.8-27b-ud-q6k"
  echo "binary=$HOME/opt/unsloth-llama-b10698-mix-vulkan/llama-server"
  echo "backend=Vulkan0 R9700"
  echo "build=10698 commit b6e334953"
  echo "model=$UD"
  echo "mtp=$M size=$mc"
  echo "bartowski=$B size=$bc"
  echo "smoke_file=$HOME/logs/smoke-qwen38-27b-ud-q6k.json"
  echo "restore_strata=cd ~/sparkdash-llm/qwen38-27b && setsid nohup ./start.sh > ~/logs/launcher-8216-restore.log 2>&1 < /dev/null &"
} > "$STATUS"
log "STATUS written $STATUS"
