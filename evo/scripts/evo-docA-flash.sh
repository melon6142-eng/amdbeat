#!/usr/bin/env bash
# Doc A: EVO Qwen3.8-Flash-Next only. Three engines. No Halogen. No Spark.
set -euo pipefail
OUT="${OUT:-$HOME/logs/docA-flash}"
HIT="$HOME/scripts/evo-docA-depth.py"
PORT="${PORT:-8080}"
CTX="${CTX:-131072}"
TEMP="${TEMP:-0}"
GEN="${GEN:-128}"
DEPTHS="${DEPTHS:-32768,65536}"
MODEL="${FLASH_GGUF:-$HOME/models/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf}"
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

stop_port() {
  fuser -k "${PORT}/tcp" 2>/dev/null || true
  sleep 2
}

measure() {
  local name="$1" alias="$2"
  python3 "$HIT" --url "http://127.0.0.1:${PORT}" --model "$alias" \
    --max-tokens "$GEN" --depths "$DEPTHS" --out "$OUT/${name}.json"
}

echo "=== E1 rocmfpx Vulkan MTP on ==="
PORT="$PORT" CTX="$CTX" PARALLEL=1 TEMP="$TEMP" \
  bash "$HOME/scripts/evo-serve-flash-amd.sh"
wait_health
measure e1-rocmfpx qwen38-flash-next-amd
stop_port

echo "=== E2 HIP / ROCm default ==="
HIP_BIN="${HIP_BIN:-$HOME/opt/unsloth-llama-b10698-mix-rocm-gfx1151/llama-server}"
HIP_LOG="$HOME/logs/serve-flash-hip-probe.log"
{
  echo "HIP probe $(date -u +%Y%m%dT%H%M%SZ)"
  "$HIP_BIN" --list-devices || true
} | tee "$OUT/e2-hip-devices.txt"
# 88G weights vs ~29 GiB HIP free: attempt a tiny-ctx load to capture the error.
stop_port
nohup "$HIP_BIN" -m "$MODEL" \
  --host 127.0.0.1 --port "$PORT" --alias qwen38-flash-hip \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap --ctx-size 1024 --parallel 1 \
  --batch-size 512 --ubatch-size 256 \
  --jinja --no-webui \
  --temp 0 \
  >"$HIP_LOG" 2>&1 &
HIP_PID=$!
echo "HIP_PID=$HIP_PID log=$HIP_LOG"
hip_ok=0
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    hip_ok=1
    break
  fi
  if ! kill -0 "$HIP_PID" 2>/dev/null; then
    break
  fi
  sleep 5
done
if [[ "$hip_ok" -eq 1 ]]; then
  echo "HIP unexpected health ok — measuring @0 only (ctx 1024 cannot do 32k/64k)"
  python3 "$HIT" --url "http://127.0.0.1:${PORT}" --model qwen38-flash-hip \
    --max-tokens "$GEN" --depths "" --out "$OUT/e2-hip.json" || true
else
  echo "HIP did not become healthy"
  tail -n 40 "$HIP_LOG" | tee "$OUT/e2-hip-tail.txt"
  python3 - <<PY
import json
from pathlib import Path
Path("$OUT/e2-hip.json").write_text(json.dumps({
  "blocker": "HIP ROCm0 ~29 GiB free, Flash GGUF 87.1 GiB",
  "devices": Path("$OUT/e2-hip-devices.txt").read_text()[-500:],
}, indent=2))
print("E2_BLOCKER")
PY
fi
if [[ -n "${HIP_PID:-}" ]]; then
  kill "$HIP_PID" 2>/dev/null || true
fi
stop_port

echo "=== E3 strix-llama.cpp Vulkan (halo-box) MTP on ==="
PORT="$PORT" CTX="$CTX" PARALLEL=1 TEMP="$TEMP" \
  LLAMA_SERVER="$HOME/src/strix-llama.cpp/build-vulkan/bin/llama-server" \
  bash "$HOME/scripts/evo-serve-flash-amd.sh"
wait_health
measure e3-strix qwen38-flash-next-amd
stop_port

python3 - "$OUT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
print("DOCA_TABLE")
def row(name, engine, quant, mtp):
    p = root / f"{name}.json"
    if not p.exists():
        print(f"{engine}|{quant}|{mtp}|||||{name} missing|missing")
        return
    rec = json.loads(p.read_text())
    if rec.get("blocker"):
        print(f"{engine}|{quant}|{mtp}|||||HIP not allocatable|{rec['blocker']}")
        return
    cold = rec.get("cold") or {}
    d = rec.get("depths") or {}
    def ts(key):
        x = d.get(key) or {}
        if x.get("error"):
            return "ERR"
        return x.get("tok_s", "")
    notes = (
        f"ttft_prompt_n={cold.get('prompt_n')} "
        f"tok0_n={cold.get('predicted_n')} "
        f"d32_pn={(d.get('32768') or {}).get('prompt_n')} "
        f"d64_pn={(d.get('65536') or {}).get('prompt_n')}"
    )
    print(
        f"{engine}|{quant}|{mtp}|"
        f"{cold.get('ttft_ms','')}|"
        f"{cold.get('tok_s','')}|"
        f"{ts('32768')}|"
        f"{ts('65536')}|"
        f"{notes}|"
        f"{(d.get('32768') or {}).get('error','') or (d.get('65536') or {}).get('error','') or 'none'}"
    )
row("e1-rocmfpx", "rocmfpx Vulkan 5e085d1", "ROCmFP4-FAST-v2-ple16", "on")
row("e2-hip", "unsloth-b10698 HIP ROCm0", "ROCmFP4-FAST-v2-ple16", "off")
row("e3-strix", "strix-llama Vulkan 69946438", "ROCmFP4-FAST-v2-ple16", "on")
print("DOCA_OK")
PY
