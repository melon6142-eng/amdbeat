#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PY="${ROOT}/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt
  PY="${ROOT}/.venv/bin/python"
fi

pkill -f "mock_openai_server.py --port 18765" 2>/dev/null || true
"$PY" scripts/mock_openai_server.py --port 18765 &
MOCK_PID=$!
cleanup() { kill "$MOCK_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 0.5

"$PY" scripts/bench_client.py --endpoint mock --dry-run --out-name dryrun_mock
"$PY" scripts/kl_compare.py --ref mock --cand mock --cand-model mock-quant --out results/kl_compare_dryrun.json
echo "dry-run OK"
