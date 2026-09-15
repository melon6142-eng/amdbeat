#!/usr/bin/env bash
# Yukon cuda.fast analog on EVO. Does not submit. Does not download.
# Same single-stream paired formula:
#   composite = (ref_prefill / cand_prefill)^0.25 * (ref_decode / cand_decode)^0.75
#   increase% = (composite - 1) * 100
# Official Yukon is ds4 CUDA + UD-Q4_K_XL on Spark. This is llama.cpp Vulkan
# on the GGUFs already on this box. Serial and candidate never overlap.
set -euo pipefail

MODEL="${1:-flash}"
PAIRS="${PAIRS:-2}"
GEN="${GEN:-128}"
CTX="${CTX:-16384}"
PORT="${PORT:-8080}"
OUT_DIR="${OUT_DIR:-$HOME/logs/yukon-analog}"
HIT="$HOME/scripts/yukon-analog-hit.py"
mkdir -p "$OUT_DIR"

case "$MODEL" in
  flash)
    SERVE="$HOME/scripts/evo-serve-flash-amd.sh"
    ALIAS=qwen38-flash-next-amd
    ;;
  deepseek)
    SERVE="$HOME/scripts/evo-serve-deepseek-amd.sh"
    ALIAS=deepseek4-iq2-amd
    ;;
  *)
    echo "usage: $0 flash|deepseek" >&2
    exit 2
    ;;
esac

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
  tail -n 40 "$HOME/logs/serve-"*.log 2>/dev/null | tail -n 40 >&2 || true
  return 1
}

run_leg() {
  local name="$1"
  shift
  echo "=== leg $name ==="
  env PORT="$PORT" CTX="$CTX" PARALLEL=1 TEMP=0 "$@" bash "$SERVE"
  wait_health
  python3 "$HIT" --url "http://127.0.0.1:${PORT}" --model "$ALIAS" \
    --pairs "$PAIRS" --max-tokens "$GEN" --out "$OUT_DIR/${MODEL}-${name}.json"
}

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
case "$MODEL" in
  flash)
    run_leg serial DRAFT=/dev/null
    sleep 15
    run_leg mtp
    python3 - "$OUT_DIR/${MODEL}-serial.json" "$OUT_DIR/${MODEL}-mtp.json" "$OUT_DIR/${MODEL}-${STAMP}-score.json" <<'PY'
import json, math, sys
serial, cand, out = sys.argv[1], sys.argv[2], sys.argv[3]
S, C = json.load(open(serial)), json.load(open(cand))
def agg(d, key):
    return sum(x[key] for x in d["pairs"])
pre_g = agg(S, "prefill_s_per_tok") / agg(C, "prefill_s_per_tok")
dec_g = agg(S, "decode_s_per_tok") / agg(C, "decode_s_per_tok")
pre_g = min(5.0, max(0.95, pre_g))
dec_g = min(5.0, max(0.95, dec_g))
comp = (pre_g ** 0.25) * (dec_g ** 0.75)
score = {
    "formula": "prefill_gain^0.25 * decode_gain^0.75",
    "official": False,
    "track": "evo-vulkan-analog",
    "prefill_gain": round(pre_g, 4),
    "decode_gain": round(dec_g, 4),
    "composite": round(comp, 4),
    "increase_pct": round((comp - 1.0) * 100, 1),
    "serial_prefill_tps": round(1.0 / (agg(S, "prefill_s_per_tok") / len(S["pairs"])), 1),
    "serial_decode_tps": round(1.0 / (agg(S, "decode_s_per_tok") / len(S["pairs"])), 1),
    "cand_prefill_tps": round(1.0 / (agg(C, "prefill_s_per_tok") / len(C["pairs"])), 1),
    "cand_decode_tps": round(1.0 / (agg(C, "decode_s_per_tok") / len(C["pairs"])), 1),
    "serial": S,
    "candidate": C,
}
json.dump(score, open(out, "w"), indent=2)
print(json.dumps({k: score[k] for k in (
    "increase_pct", "composite", "prefill_gain", "decode_gain",
    "serial_decode_tps", "cand_decode_tps", "serial_prefill_tps", "cand_prefill_tps"
)}, indent=2))
print("wrote", out)
PY
    ;;
  deepseek)
    run_leg serial
    echo "DeepSeek serve script has no MTP draft; serial-only analog written."
    ;;
esac
echo YUKON_ANALOG_OK
