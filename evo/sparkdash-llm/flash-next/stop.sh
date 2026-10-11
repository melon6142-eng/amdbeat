#!/usr/bin/env bash
pkill -TERM -f "serve.server --engine strata" || echo "server not running"
for i in $(seq 1 40); do pgrep -f "^$HOME/src/strata-0140/engine/strata --serve" >/dev/null || break; sleep 1; done
pkill -KILL -f "^$HOME/src/strata-0140/engine/strata --serve" 2>/dev/null
echo "flash-next stopped"
