#!/usr/bin/env bash
# EVO phase-2 repro: Flash (rocmfpx) then 27B then DeepSeek. No download. No HIP.
# One GPU. Existing serve scripts only. CTX=16384 PARALLEL=1 TEMP=0.
set -euo pipefail
PORT="${PORT:-8080}"
CTX="${CTX:-16384}"
TEMP="${TEMP:-0}"
GEN="${GEN:-128}"
OUT="$HOME/logs/repro-phase2"
HIT="$HOME/scripts/evo-repro-hit.py"
mkdir -p "$OUT"

wait_health() {
  local deadline=$((SECONDS + 1200))
  while (( SECONDS < deadline )); do
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      echo "health ok"
      return 0
    fi
    sleep 5
  done
  echo "health timeout" >&2
  return 1
}

pair() {
  local name="$1" alias="$2"
  python3 "$HIT" --model "$alias" --max-tokens "$GEN" --label cold \
    --out "$OUT/${name}-cold.json"
  python3 "$HIT" --model "$alias" --max-tokens "$GEN" --label warm \
    --out "$OUT/${name}-warm.json"
}

echo "=== FLASH rocmfpx Vulkan PRIMARY ==="
PORT="$PORT" CTX="$CTX" PARALLEL=1 TEMP="$TEMP" \
  bash "$HOME/scripts/evo-serve-flash-amd.sh"
wait_health
pair flash qwen38-flash-next-amd

echo "=== QWEN38-27 Q4_K_M mix-vulkan ==="
PORT="$PORT" CTX="$CTX" PARALLEL=1 TEMP="$TEMP" \
  bash "$HOME/scripts/evo-serve-qwen27-4080-amd.sh"
wait_health
pair qwen27 qwen38-27b-q4-amd

echo "=== DEEPSEEK IQ2XXS mix-vulkan ==="
PORT="$PORT" CTX="$CTX" TEMP="$TEMP" \
  bash "$HOME/scripts/evo-serve-deepseek-amd.sh"
wait_health
pair deepseek deepseek4-iq2-amd

python3 - "$OUT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
print("PHASE2_TABLE")
for name, engine, quant in (
    ("flash", "llama.cpp-rocmfpx Vulkan", "ROCmFP4-FAST-v2-ple16"),
    ("qwen27", "unsloth-b10698 mix-vulkan", "Q4_K_M"),
    ("deepseek", "unsloth-b10698 mix-vulkan", "IQ2XXS"),
):
    cold = json.loads((root / f"{name}-cold.json").read_text())
    warm = json.loads((root / f"{name}-warm.json").read_text())
    print(
        f"{name}|{engine}|{quant}|"
        f"{cold['ttft_ms']}|{cold['tok_s']}|"
        f"warm_ttft={warm['ttft_ms']} warm_tok_s={warm['tok_s']} "
        f"cold_n={cold['predicted_n']} warm_n={warm['predicted_n']} "
        f"pp={cold.get('prompt_n')}"
    )
print("PHASE2_OK")
PY
