#!/usr/bin/env bash
# EVO: start exactly one llama-server model. Kills every other llama-server first.
# Usage: evo-wake-model.sh <flashnext|flash-lean|qwen27|qwen27-lean|deepseek>
set -euo pipefail

TARGET=${1:-}
[[ -n $TARGET ]] || {
  echo "usage: $0 <flashnext|flash-lean|qwen27|qwen27-lean|deepseek>"
  exit 2
}

LOCK=/tmp/evo-model.lock
mkdir -p "$HOME/logs"

log(){ echo "[$(date -Is)] $*" | tee -a "$HOME/logs/evo-wake-model.log"; }

# Serialize wake attempts so two shells cannot race-load two models
exec 9>"$LOCK"
if ! flock -n 9; then
  log "ERROR: another wake/serve holds $LOCK — refusing duplicate load"
  exit 1
fi

stop_all_llama() {
  log "stopping all llama-server processes"
  pkill -f '/llama-server ' 2>/dev/null || true
  pkill -f 'llama-server ' 2>/dev/null || true
  # wait until gone
  for i in $(seq 1 30); do
    if ! pgrep -f '/bin/llama-server |/llama-server ' >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if pgrep -f '/bin/llama-server |/llama-server ' >/dev/null 2>&1; then
    log "force kill remaining llama-server"
    pkill -9 -f 'llama-server' 2>/dev/null || true
    sleep 2
  fi
  # free ports we use
  for p in 8080 8081 8082 8084; do
    fuser -k "${p}/tcp" 2>/dev/null || true
  done
  sleep 1
  free -h | head -2 | tee -a "$HOME/logs/evo-wake-model.log" || true
}

start_bg() {
  local script=$1
  local logf=$2
  [[ -x $script ]] || { log "missing $script"; exit 1; }
  EVO_WAKE_OK=1 nohup "$script" >"$logf" 2>&1 &
  echo $! > "$HOME/logs/evo-current-server.pid"
  log "started $script pid=$! log=$logf"
}

stop_all_llama

case $TARGET in
  flashnext)
    start_bg "$HOME/bin/serve-flash-next.sh" "$HOME/logs/serve-flash-next.log"
    PORT=8081
    ;;
  flash-lean)
    start_bg "$HOME/bin/serve-flash-strix-lean.sh" "$HOME/logs/serve-flash-strix-lean.log"
    PORT=8082
    ;;
  qwen27)
    # require weights
    MODEL=$HOME/models/rocmfp4/qwen27/Qwen3.8-27B-ROCmFP4-FAST.gguf
    [[ -s $MODEL ]] || { log "missing $MODEL"; exit 1; }
    start_bg "$HOME/bin/serve-qwen27-dflash.sh" "$HOME/logs/serve-qwen27.log"
    PORT=8080
    ;;
  qwen27-lean)
    start_bg "$HOME/bin/serve-qwen27-strix-lean.sh" "$HOME/logs/serve-qwen27-strix-lean.log"
    PORT=8080
    ;;
  deepseek)
    start_bg "$HOME/bin/serve-deepseek-q3.sh" "$HOME/logs/serve-deepseek.log"
    PORT=8084
    ;;
  *)
    log "unknown target $TARGET"
    exit 2
    ;;
esac

echo "$TARGET" > "$HOME/logs/evo-current-model.txt"
# wait for listen (load can take minutes)
log "waiting for :$PORT"
for i in $(seq 1 180); do
  if ss -lntp 2>/dev/null | grep -q ":${PORT} "; then
    # health may fail while loading; listening is enough to know one server owns the port
    if curl -sf -m 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 \
       || curl -sf -m 2 "http://127.0.0.1:${PORT}/v1/models" >/dev/null 2>&1; then
      log "ready $TARGET on :$PORT"
      # assert exclusivity
      n=$(pgrep -f '/bin/llama-server |/llama-server ' | wc -l || true)
      if [[ ${n:-0} -gt 1 ]]; then
        log "ERROR: $n llama-server processes — killing extras"
        stop_all_llama
        exit 1
      fi
      exit 0
    fi
  fi
  # still only one process?
  n=$(pgrep -f '/bin/llama-server |/llama-server ' | wc -l || true)
  if [[ ${n:-0} -gt 1 ]]; then
    log "ERROR during boot: $n llama-server — abort"
    stop_all_llama
    exit 1
  fi
  sleep 5
done
log "TIMEOUT waiting for $TARGET :$PORT"
exit 1
