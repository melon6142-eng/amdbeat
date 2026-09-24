#!/usr/bin/env bash
# Baseline vs DFlash2 speculative decode for GLM AJ-IQ2_XXS.
# GPU must be free (no ds4). Stops nothing itself — caller stops :8080.
set -euo pipefail
OUT="${OUT:-$HOME/logs/glm-dflash-bench-$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
BIN="${BIN:-$HOME/src/llama-dflash2-vcruz/build-hip-dflash/bin/llama-server}"
MODEL="${MODEL:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
DRAFT="${DRAFT:-$HOME/models/gguf/GLM-5.3-Flash-DFlash2/GLM-5.3-Flash-DFlash2-BF16.gguf}"
PORT_BASE="${PORT_BASE:-8093}"
NPRED="${NPRED:-256}"
export LD_LIBRARY_PATH="$(dirname "$BIN"):/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST=1
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true

if pgrep -x ds4-server >/dev/null 2>&1; then echo "ABORT: ds4 running"; pgrep -af ds4; exit 2; fi
if [ ! -f "$DRAFT" ]; then echo "ABORT: missing draft $DRAFT"; exit 2; fi

CHAT='Write a one-sentence greeting, then explain in 3 short paragraphs what speculative decoding is.'
CODE=$'```python\ndef fib(n):\n'
AGENT_FILE="${AGENT_FILE:-$HOME/bench/ds-agent-prompts/cli-text/01_code_edit_python.txt}"
AGENT=$(cat "$AGENT_FILE")

run_server() {
  local name=$1; shift
  local port=$1; shift
  local d="$OUT/$name"; mkdir -p "$d"
  echo "[$name] start $(date -Is) extras: $*"
  "$BIN" -m "$MODEL" --host 127.0.0.1 --port "$port" --alias "glm-$name" \
    --device ROCm0 --gpu-layers all --flash-attn on --fit off \
    --load-mode mmap+mlock --ctx-size 16384 --batch-size 512 --ubatch-size 256 \
    --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
    --reasoning off --jinja --no-webui \
    "$@" >"$d/server.log" 2>&1 &
  echo $! >"$d/server.pid"
  local spid=$!
  for i in $(seq 1 180); do
    curl -sf "http://127.0.0.1:$port/health" >/dev/null && break
    if ! kill -0 $spid 2>/dev/null; then echo "server died"; tail -80 "$d/server.log"; return 1; fi
    sleep 2
  done
  echo $spid
}

kill_port() {
  local port=$1
  fuser -k ${port}/tcp 2>/dev/null || true
  sleep 2
}

do_completion() {
  local port=$1 tag=$2 prompt=$3 npred=$4
  local pfile="$OUT/${tag}.prompt.txt"
  printf '%s' "$prompt" > "$pfile"
  python3 - "$port" "$tag" "$pfile" "$npred" "$OUT" <<'PY'
import json, sys, urllib.request
port, tag, pfile, npred, out = sys.argv[1:6]
prompt = open(pfile, encoding="utf-8").read()
body = json.dumps({"prompt": prompt, "n_predict": int(npred), "temperature": 0}).encode()
req = urllib.request.Request(f"http://127.0.0.1:{port}/completion", data=body,
                             headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req, timeout=900) as r:
    data = r.read()
open(f"{out}/{tag}.json","wb").write(data)
j = json.loads(data)
t = j.get("timings", {})
print(f"{tag}: pred_tps={t.get('predicted_per_second',0):.2f} prompt_tps={t.get('prompt_per_second',0):.2f} "
      f"pred_n={t.get('predicted_n')} prompt_n={t.get('prompt_n')} "
      f"draft_n={t.get('draft_n', t.get('n_draft', 'n/a'))} "
      f"accept={t.get('draft_acceptance', t.get('n_accepted', 'n/a'))}")
content = (j.get("content") or "")[:120].replace("\n"," ")
print(f"  content[:120]={content!r}")
print("  timing_keys=", sorted(t.keys()))
for k in ("draft_n","n_draft","draft_acceptance","n_accepted","tokens_evaluated","tokens_predicted"):
    if k in j: print(f"  root.{k}={j[k]}")
PY
}

summarize_server_spec() {
  local log=$1
  grep -iE 'accept|draft|specul|tokens/s|predicted|dflash' "$log" | tail -60 || true
}

# --- baseline ---
kill_port $PORT_BASE
spid=$(run_server baseline $PORT_BASE)
do_completion $PORT_BASE baseline-chat "$CHAT" $NPRED
do_completion $PORT_BASE baseline-code "$CODE" $NPRED
do_completion $PORT_BASE baseline-agent "$AGENT" $NPRED
kill_port $PORT_BASE

# --- dflash nmax variants ---
for NMAX in 3 5 7; do
  kill_port $PORT_BASE
  name="dflash-n${NMAX}"
  spid=$(run_server "$name" $PORT_BASE \
    -md "$DRAFT" --spec-type draft-dflash --spec-draft-n-max "$NMAX" \
    --spec-draft-ngl 999)
  do_completion $PORT_BASE "${name}-chat" "$CHAT" $NPRED
  do_completion $PORT_BASE "${name}-code" "$CODE" $NPRED
  do_completion $PORT_BASE "${name}-agent" "$AGENT" $NPRED
  summarize_server_spec "$OUT/$name/server.log" | tee "$OUT/$name/spec-summary.txt"
  kill_port $PORT_BASE
done

python3 - "$OUT" <<'PY'
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
rows = []
for p in sorted(out.glob("*.json")):
    j = json.load(open(p))
    t = j.get("timings", {})
    rows.append((p.stem,
                 t.get("predicted_per_second"),
                 t.get("prompt_per_second"),
                 t.get("predicted_n"),
                 t.get("prompt_n"),
                 t.get("draft_n", t.get("n_draft")),
                 t.get("draft_acceptance", t.get("n_accepted")),
                 (j.get("content") or "")[:60].replace("\n"," ")))
print("=== TABLE ===")
print(f"{'tag':30} {'pred_tps':>10} {'prompt_tps':>11} {'pred_n':>7} {'prompt_n':>8} {'draft':>8} {'accept':>8}")
for r in rows:
    print(f"{r[0]:30} {r[1] or 0:10.2f} {r[2] or 0:11.2f} {r[3] or 0:7} {r[4] or 0:8} {str(r[5]):>8} {str(r[6]):>8}  | {r[7]!r}")
print("OUT", out)
PY
echo "done $OUT"
