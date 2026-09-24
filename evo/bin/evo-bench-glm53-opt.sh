#!/usr/bin/env bash
# Short/code decode + 8k prefill bench for opt build. GPU must be free.
set -euo pipefail
BIN="${BIN:-$HOME/src/llama-iq2-opt/build-hip-opt/bin/llama-server}"
MODEL="${MODEL:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
PORT="${PORT:-8092}"
OUT="${OUT:-$HOME/logs/iq2-opt-bench-$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
if pgrep -f 'ds4-server' >/dev/null; then echo "ABORT: ds4-server running"; exit 2; fi
export LD_LIBRARY_PATH="$(dirname "$BIN"):/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST=1
"$BIN" -m "$MODEL" --host 127.0.0.1 --port "$PORT" --alias glm53-iq2-opt \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap+mlock --ctx-size 16384 --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui >"$OUT/server.log" 2>&1 &
SPID=$!; echo $SPID >"$OUT/server.pid"
cleanup(){ kill $SPID 2>/dev/null || true; wait $SPID 2>/dev/null || true; }; trap cleanup EXIT
for i in $(seq 1 120); do curl -sf http://127.0.0.1:$PORT/health >/dev/null && break; sleep 2; done
# short code decode
curl -sf http://127.0.0.1:$PORT/completion -H 'Content-Type: application/json' \
  -d '{"prompt":"```python\ndef fib(n):\n","n_predict":128,"temperature":0}' | tee "$OUT/decode-code.json"
# 8k prefill: use a long prompt file if present, else synthesize
python3 - <<'PY' >"$OUT/prompt8k.txt"
print(("The quick brown fox jumps over the lazy dog. ")*400)
PY
# Use llama-bench if available from the same build
LB="$(dirname "$BIN")/llama-bench"
if [ -x "$LB" ]; then
  "$LB" -m "$MODEL" -ngl 999 -fa 1 -p 8192 -n 64 -r 3 | tee "$OUT/llama-bench.txt"
else
  echo "llama-bench not built; completion-only timings in JSON" | tee "$OUT/llama-bench.txt"
fi
echo "done $OUT"
