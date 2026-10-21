#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

echo "=== pidfile ==="
if [[ -f "${PIDFILE:-/tmp/llama-qwen38-27b-r9700.pid}" ]]; then
  pid="$(cat "$PIDFILE")"
  if kill -0 "$pid" 2>/dev/null; then
    echo "running pid=$pid"
  else
    echo "pidfile present but process dead: $pid"
  fi
else
  echo "no pidfile"
fi

echo "=== HTTP /v1/models ==="
curl -sS --max-time 5 "http://${EVO_HOST}:${PORT}/v1/models" || echo "(unreachable)"
echo
