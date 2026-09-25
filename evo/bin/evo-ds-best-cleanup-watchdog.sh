#!/usr/bin/env bash
# Force cleanup at 06:05 if runner still holding GPU or GLM down.
set -euo pipefail
OUT=~/logs/ds-best-20260925
mkdir -p "$OUT"
LOG=$OUT/watchdog.log
exec >>"$LOG" 2>&1
DEADLINE=$(date -d "2026-09-25 06:05:00" +%s)
echo "[$(date -Is)] watchdog armed"
while true; do
  now=$(date +%s)
  if (( now >= DEADLINE )); then
    echo "[$(date -Is)] DEADLINE hit — force cleanup"
    for n in $(podman ps -a --format "{{.Names}}" 2>/dev/null | grep -E "^ds4-best|^ds4-dspark-gate" || true); do
      echo "stop $n"; podman stop -t 30 "$n" || true; podman rm "$n" || true
    done
    pkill -TERM -f "evo-ds-best-runner-20260925" || true
    pkill -TERM -f luce_server || true
    if [[ -f ~/.gpu-owner ]] && grep -q "hop-grok-4.7" ~/.gpu-owner; then
      rm -f ~/.gpu-owner
      echo "released our lock"
    fi
    if ! curl -sf -m 3 http://127.0.0.1:8080/health >/dev/null 2>&1; then
      if ! ss -ltn | grep -q ":8080 "; then
        nohup ~/bin/evo-serve-glm53-dflash.sh > "$OUT/glm-watchdog-restore.log" 2>&1 &
        echo "started GLM restore pid=$!"
      fi
    fi
    for i in $(seq 1 90); do
      if curl -sf -m 3 http://127.0.0.1:8080/health >/dev/null 2>&1; then
        echo "GLM_HEALTH_OK $(date -Is)" | tee "$OUT/glm-health-watchdog.txt"
        exit 0
      fi
      sleep 2
    done
    echo "GLM_HEALTH_FAIL $(date -Is)" | tee "$OUT/glm-health-watchdog.txt"
    exit 1
  fi
  sleep 30
done
