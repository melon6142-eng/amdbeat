#!/usr/bin/env bash
# sparkDash launcher (r9700 / port 8216): Strata on the R9700 only. Config chosen in ~/strata-8216.conf (CFG=...json). Stays alive while server runs.
PAT="serve.server --engine strata --config strata-.*-r9700-8216.*[.]json"
if ! pgrep -f "$PAT" >/dev/null; then
  cd "$HOME" && setsid nohup ./strata-8216.sh > "$HOME/logs/strata-8216-console.log" 2>&1 < /dev/null &
fi
for i in $(seq 1 100); do curl -s -m 3 http://127.0.0.1:8216/v1/models | grep -q flash-next && break; sleep 3; done
curl -s -m 3 http://127.0.0.1:8216/v1/models | grep -q flash-next && echo "strata 8216 loaded: http://EVO_HOST:8216/v1" || echo "API not up yet"
while pgrep -f "$PAT" >/dev/null; do sleep 15; done
echo "strata 8216 stopped"
