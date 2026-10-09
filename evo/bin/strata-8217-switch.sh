#!/bin/bash
# usage: strata-8217-switch.sh <config.json>
CFG=$1; cd ~/src/strata-0140 || exit 1
for p in $(pgrep -f "serve.server --engine strata --config strata-.*-8217.*json"); do kill $p; done
for i in $(seq 1 40); do pgrep -f "^$HOME/src/strata-0140/engine/strata --serve" >/dev/null || break; sleep 1; done
pkill -f "^$HOME/src/strata-0140/engine/strata --serve"; sleep 3
ts=$(date +%Y%m%d-%H%M%S)
[ -f ~/logs/strata-8217.log ] && cp -p ~/logs/strata-8217.log ~/logs/strata-8217.log.$ts
[ -f ~/logs/strata-8217-console.log ] && cp -p ~/logs/strata-8217-console.log ~/logs/strata-8217-console.log.$ts
setsid nohup ./.venv/bin/python -m serve.server --engine strata --config "$CFG" --port 8217 --host 0.0.0.0 > ~/logs/strata-8217-console.log 2>&1 < /dev/null &
echo "launched $CFG pid $!"
