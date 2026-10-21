#!/usr/bin/env bash
# Start llama-server for P0 on R9700. Requires EVO_CONFIRM=1 and free GPU (8216 stopped).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"
require_confirm

if [[ ! -f "$MODEL_FILE" ]]; then
  echo "Missing MODEL_FILE=$MODEL_FILE — run download_primary.sh first" >&2
  exit 1
fi
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Already running pid=$(cat "$PIDFILE")" >&2
  exit 1
fi

EXTRA=()
case "${BACKEND}" in
  rocm) export HIP_VISIBLE_DEVICES="${HIP_VISIBLE_DEVICES:-0}" ;;
  vulkan) EXTRA+=() ;; # TODO: set GGML_VK_* if your build needs it
  *) echo "BACKEND must be rocm|vulkan" >&2; exit 1 ;;
esac

# shellcheck disable=SC2086
nohup $LLAMA_SERVER \
  -m "$MODEL_FILE" \
  --host 0.0.0.0 --port "$PORT" \
  -ngl "$NGL" \
  -c "$CTX" \
  -b "$BATCH" -ub "$UBATCH" \
  -fa on \
  --jinja \
  --mmap \
  -np 1 \
  --alias "$MODEL_ALIAS" \
  "${EXTRA[@]}" \
  >"$LOGFILE" 2>&1 &
echo $! >"$PIDFILE"
echo "started pid=$(cat "$PIDFILE") port=$PORT alias=$MODEL_ALIAS log=$LOGFILE"
