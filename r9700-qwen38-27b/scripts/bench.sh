#!/usr/bin/env bash
# Wrap ../scripts/bench_client.py — run from box (or any host that can reach EVO).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

OUT_DIR="$SCRIPT_DIR/../results"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_JSON="$OUT_DIR/bench_${MODEL_ALIAS}_${STAMP}.json"

cd "$LAB_ROOT"
if [[ -f .venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

ARGS=(
  scripts/bench_client.py
  --endpoint "http://${EVO_HOST}:${PORT}/v1"
  --model "$MODEL_ALIAS"
  --out "$OUT_JSON"
)
if [[ -f configs/bench.yaml ]]; then
  ARGS+=(--config configs/bench.yaml)
fi

python "${ARGS[@]}"
echo "wrote $OUT_JSON"
echo "Fill results/scorecard_template.md with this run vs rival."
