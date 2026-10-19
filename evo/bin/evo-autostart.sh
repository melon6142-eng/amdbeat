#!/bin/bash
# EVO @reboot autostart (user crontab, no sudo): 8217 halogen (podman) then 8216 Strata (sparkDash launcher).
# halogen: podman start; if that fails (e.g. /dev/dri card numbers changed after reboot), the container is renamed
# and re-created with its own original create command (so it follows whatever image/env --go or --rollback set).
LOG=$HOME/logs/evo-autostart.log; exec >> "$LOG" 2>&1
say(){ echo "$(date +%FT%T) $*"; }
say "boot autostart begin"
for i in $(seq 1 36); do [ -d /run/user/$(id -u) ] && break; sleep 5; done
[ -d /run/user/$(id -u) ] && export XDG_RUNTIME_DIR=/run/user/$(id -u)
for i in $(seq 1 60); do [ -e /dev/kfd ] && [ $(ls /dev/dri/card* 2>/dev/null | wc -l) -ge 2 ] && break; sleep 5; done
sleep 20
if ! curl -sf -m 5 localhost:8217/health >/dev/null; then
  if ! podman start halogen; then
    cmd=$(podman inspect halogen --format '{{json .Config.CreateCommand}}')
    old=halogen-autostart-stale-$(date +%Y%m%d-%H%M%S)
    podman rename halogen $old && say "renamed failed container to $old"
    python3 -c 'import json,sys,os; a=json.loads(sys.argv[1]); os.execvp(a[0], a)' "$cmd" && say "re-created halogen"
  fi
  for i in $(seq 1 120); do curl -sf -m 5 localhost:8217/health >/dev/null && break; sleep 5; done
fi
curl -sf -m 5 localhost:8217/health >/dev/null && say "8217 healthy" || say "8217 NOT healthy"
cd $HOME/sparkdash-llm/qwen38-27b && setsid nohup ./start.sh > $HOME/logs/launcher-8216-boot.log 2>&1 < /dev/null &
for i in $(seq 1 120); do curl -sf -m 5 localhost:8216/v1/models >/dev/null && break; sleep 5; done
curl -sf -m 5 localhost:8216/v1/models >/dev/null && say "8216 up" || say "8216 NOT up"
