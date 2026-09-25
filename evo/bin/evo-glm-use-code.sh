#!/usr/bin/env bash
# Switch EVO GLM to CODE mode: UD-IQ2_XXS + draft-mtp,ngram-mod on :8088.
# Stops chat :8080 first (cannot co-run — memory).
set -euo pipefail

LOCK="$HOME/.gpu-owner"
LOGDIR="$HOME/logs"
mkdir -p "$LOGDIR"
CODE_LOG="$LOGDIR/evo-glm-code-$(date +%Y%m%d_%H%M%S).log"
AGENT_TAG="${GPU_OWNER_TAG:-hop-grok4.7-2 glm-split $(date "+%Y-%m-%d %H:%M CST")}"

log() { printf "[%s] %s\n" "$(date "+%Y-%m-%d %H:%M:%S CST")" "$*"; }

stop_by_port() {
  local port="$1"
  local pids=""
  pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
  if [[ -z "${pids:-}" ]]; then
    pids=$(ss -tlnp 2>/dev/null | grep -E ":${port}\\b" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | sort -u | tr '\n' ' ')
  fi
  if [[ -n "${pids:-}" ]]; then
    log "Stopping listeners on :$port → $pids"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    sleep 2
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

stop_glm_servers() {
  stop_by_port 8080
  stop_by_port 8088
  local extra
  extra=$(pgrep -f "llama-server.*(glm53-|GLM-5\\.3-Flash)" 2>/dev/null || true)
  if [[ -n "${extra:-}" ]]; then
    log "Stopping remaining glm llama-server pids: $extra"
    # shellcheck disable=SC2086
    kill $extra 2>/dev/null || true
    sleep 2
    # shellcheck disable=SC2086
    kill -9 $extra 2>/dev/null || true
  fi
  pkill -f "evo-serve-glm53-(dflash|code-mtp|mtp-ngram|mtp)\\.sh" 2>/dev/null || true
  sleep 1
}

wait_health() {
  local port="$1" timeout="${2:-180}"
  local i=0
  while (( i < timeout )); do
    if curl -sS -m 2 "http://127.0.0.1:${port}/health" 2>/dev/null | grep -q '"ok"'; then
      log "Health OK on :$port"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  log "ERROR: /health not ok on :$port after ${timeout}s"
  return 1
}

if [[ -f "$LOCK" ]]; then
  owner=$(cat "$LOCK" || true)
  if echo "$owner" | grep -Eq 'hop-grok-4\.7|hop-grok4\.7' && ! echo "$owner" | grep -q 'glm-split'; then
    log "YIELD: GPU owned by other agent: $owner"
    exit 2
  fi
fi

log "Switching to CODE (MTP :8088)"
echo "$AGENT_TAG" > "$LOCK"
stop_glm_servers

if ss -tlnp 2>/dev/null | grep -qE ':8080|:8088'; then
  log "WARN: ports still busy after stop; forcing again"
  stop_by_port 8080
  stop_by_port 8088
  sleep 2
fi

nohup "$HOME/bin/evo-serve-glm53-code-mtp.sh" >"$CODE_LOG" 2>&1 &
echo $! > "$LOGDIR/evo-glm-code.pid"
log "Started code-mtp pid=$(cat "$LOGDIR/evo-glm-code.pid") log=$CODE_LOG"

wait_health 8088 300
log "CODE mode ready on :8088"
if [[ "${CLEAR_LOCK:-0}" == "1" ]]; then
  rm -f "$LOCK"
  log "Cleared $LOCK"
fi