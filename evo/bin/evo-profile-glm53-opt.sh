#!/usr/bin/env bash
# Decode-timeline profile via rocprofv3 wrapping llama-cli (opt HIP build).
# GPU must be free (aborts if ds4-server / foreign llama-server present).
set -euo pipefail

ROOT="$HOME/src/llama-iq2-opt/build-hip-opt"
BIN="${BIN:-$ROOT/bin/llama-cli}"
MODEL="${MODEL:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
OUTDIR="${OUTDIR:-$HOME/logs/iq2-opt-profile-$(date +%Y%m%d_%H%M%S)}"
DECODE_TOKENS="${DECODE_TOKENS:-24}"
PROMPT="${PROMPT:-Write a short Python fibonacci function.}"

mkdir -p "$OUTDIR"
export LD_LIBRARY_PATH="$ROOT/bin:/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST=1
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true

# Abort if another agent owns the GPU
if pgrep -af 'ds4-server' >/dev/null; then
  echo "ABORT: ds4-server running" >&2
  pgrep -af 'ds4-server' >&2 || true
  exit 2
fi
# Allow our own llama-cli only; block other llama-server
if pgrep -af 'llama-server' >/dev/null; then
  echo "ABORT: llama-server running" >&2
  pgrep -af 'llama-server' >&2 || true
  exit 2
fi

{
  echo "date: $(date -Is)"
  echo "bin: $BIN"
  echo "model: $MODEL"
  echo "decode_tokens: $DECODE_TOKENS"
  grep GGML_HIP_GRAPHS "$ROOT/CMakeCache.txt" 2>/dev/null || grep GGML_HIP_GRAPHS "$ROOT/CMakeCache.txt"
  echo "GGML_CUDA_REGISTER_HOST=$GGML_CUDA_REGISTER_HOST"
  echo "GGML_IQ2_ROWS=${GGML_IQ2_ROWS:-8(default)}"
  echo "GGML_IQ2S_ROWS=${GGML_IQ2S_ROWS:-4(default)}"
  echo "GGML_Q2K_ROWS=${GGML_Q2K_ROWS:-8(default)}"
} | tee "$OUTDIR/meta.txt"

# Warmup WITHOUT rocprof (loads weights; not timed in kernel trace)
echo "[1/3] warmup load+8 tokens (no rocprof)"
"$BIN" -m "$MODEL" -ngl 999 -fa on --no-display-prompt \
  -p "Hi" -n 8 -t 32 --temp 0 \
  >"$OUTDIR/warmup.txt" 2>"$OUTDIR/warmup.err" || { echo warmup failed; tail -40 "$OUTDIR/warmup.err"; exit 1; }

# Profiled decode: still cold-start process but model pages should be warm in host RAM / GTT
echo "[2/3] rocprofv3 kernel+hip+stats over -n $DECODE_TOKENS"
# Note: process restart reloads; REGISTER_HOST mmap should be fast after warmup OS cache.
rocprofv3 --kernel-trace --hip-trace --stats --summary \
  -d "$OUTDIR/rocprof" -o glm_decode -f csv json \
  -- "$BIN" -m "$MODEL" -ngl 999 -fa on --no-display-prompt \
     -p "$PROMPT" -n "$DECODE_TOKENS" -t 32 --temp 0 \
  >"$OUTDIR/cli.out" 2>"$OUTDIR/cli.err" || true

# CPU util on a non-profiled short decode (separate process)
echo "[3/3] CPU util sample (pidstat on short decode)"
"$BIN" -m "$MODEL" -ngl 999 -fa on --no-display-prompt \
  -p "Count to three." -n 16 -t 32 --temp 0 \
  >"$OUTDIR/cpu_decode.out" 2>"$OUTDIR/cpu_decode.err" &
CPID=$!
pidstat -p "$CPID" 1 20 >"$OUTDIR/pidstat.txt" 2>&1 || true
wait "$CPID" || true

# Summarize
python3 "$HOME/src/llama-iq2-opt/scripts/analyze_rocprof_decode.py" \
  --tokens "$DECODE_TOKENS" \
  $(find "$OUTDIR/rocprof" -name '*kernel*csv' -o -name '*stats*csv' 2>/dev/null | head -1) \
  | tee "$OUTDIR/summary.txt" || true

# Gap heuristic from HIP API trace if present
python3 - <<'PY' "$OUTDIR" | tee -a "$OUTDIR/summary.txt"
import sys, pathlib, csv, collections
outdir = pathlib.Path(sys.argv[1])
hip = list(outdir.glob('rocprof/**/*hip*csv')) + list(outdir.glob('rocprof/**/*HIP*csv'))
print('hip csvs', [str(p) for p in hip[:5]])
# Look for Synchronize / StreamWait
for p in hip[:3]:
    try:
        with p.open() as f:
            rows=list(csv.DictReader(f))
    except Exception as e:
        print('skip', p, e); continue
    counts=collections.Counter()
    for r in rows:
        name=None
        for k,v in r.items():
            if k and 'name' in k.lower():
                name=v; break
        if not name: continue
        if any(s in name for s in ('Synchronize','StreamWait','Memcpy','LaunchKernel','ExtModuleLaunchKernel','GraphLaunch')):
            counts[name]+=1
    print(p.name, 'interesting HIP calls:', counts.most_common(20))
PY

echo "DONE $OUTDIR"
