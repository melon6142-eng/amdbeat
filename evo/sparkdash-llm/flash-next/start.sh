#!/usr/bin/env bash
# sparkDash launcher: qwen3.8-flash-next via ~/bin/strata-8217-switch.sh. Stays alive while server runs.
CFG="strata-unsloth-ud-iq4_xs-strix-8217-rocm7141-fast-ctx256k.json"
if ! pgrep -f "serve.server --engine strata" >/dev/null; then
  "$HOME/bin/strata-8217-switch.sh" "$CFG" || { echo "strata switch failed"; exit 1; }
fi
for i in $(seq 1 60); do curl -s -m 3 http://127.0.0.1:8217/v1/models | grep -q flash-next && break; sleep 3; done
curl -s -m 3 http://127.0.0.1:8217/v1/models | grep -q flash-next && echo "flash-next loaded: http://EVO_HOST:8217/v1" || echo "API not up yet"
while pgrep -f "serve.server --engine strata" >/dev/null; do sleep 15; done
echo "flash-next stopped"
