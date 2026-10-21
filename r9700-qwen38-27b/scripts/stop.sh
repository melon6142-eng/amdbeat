#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"
require_confirm

if [[ -f "$PIDFILE" ]]; then
  pid="$(cat "$PIDFILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    echo "sent SIGTERM to $pid"
  else
    echo "stale pidfile $PIDFILE"
  fi
  rm -f "$PIDFILE"
else
  echo "No pidfile; refusing to kill by port alone (ask lab-ops)." >&2
  exit 1
fi
