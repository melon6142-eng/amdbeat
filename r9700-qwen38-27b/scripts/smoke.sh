#!/usr/bin/env bash
# One short completion against OpenAI-compatible endpoint. Read-only; no EVO_CONFIRM needed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

curl -sS --max-time 120 "http://${EVO_HOST}:${PORT}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${MODEL_ALIAS}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: ok\"}],\"max_tokens\":16,\"temperature\":0}" \
  | tee /tmp/qwen38-r9700-smoke.json
echo
