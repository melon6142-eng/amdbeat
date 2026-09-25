#!/usr/bin/env bash
# GLM-5.3-Flash MTP vs DFlash2 comparison on EVO.
# Does NOT edit evo-serve-glm53-dflash.sh. Caller must hold ~/.gpu-owner.
set -euo pipefail

OUT="${OUT:-$HOME/logs/glm-mtp-compare-$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
BIN="${BIN:-$HOME/src/llama-dflash2-vcruz/build-hip-dflash/bin/llama-server}"
# Default model: UD-IQ2_XXS (MTP tensors). AJ used for DFlash baseline.
MODEL_UD="${MODEL_UD:-$HOME/models/gguf/GLM-5.3-Flash-UD-IQ2_XXS/GLM-5.3-Flash-UD-IQ2_XXS-00001-of-00004.gguf}"
MODEL_AJ="${MODEL_AJ:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
DRAFT="${DRAFT:-$HOME/models/gguf/GLM-5.3-Flash-DFlash2/GLM-5.3-Flash-DFlash2-BF16.gguf}"
PORT="${PORT:-8095}"
NPRED="${NPRED:-256}"
CTX="${CTX:-16384}"
export LD_LIBRARY_PATH="$(dirname "$BIN"):/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST="${GGML_CUDA_REGISTER_HOST:-1}"
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true

CHAT='Write a one-sentence greeting, then explain in 3 short paragraphs what speculative decoding is.'
CODE=$'```python\ndef fib(n):\n'
AGENT_DIR="${AGENT_DIR:-$HOME/bench/ds-agent-prompts/cli-text}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S CST')] $*"; }
kill_port() { fuser -k "${1}/tcp" 2>/dev/null || true; sleep 2; }

wait_health() {
  local port=$1 spid=$2 d=$3
  for i in $(seq 1 240); do
    if curl -sf "http://127.0.0.1:${port}/health" | grep -q ok; then return 0; fi
    if ! kill -0 "$spid" 2>/dev/null; then
      log "server died"; tail -100 "$d/server.log" || true; return 1
    fi
    sleep 2
  done
  log "health timeout"; tail -80 "$d/server.log" || true; return 1
}

run_server() {
  local name=$1; shift
  local model=$1; shift
  local d="$OUT/$name"; mkdir -p "$d"
  kill_port "$PORT"
  log "[$name] start model=$(basename "$model") extras: $*"
  "$BIN" -m "$model" --host 127.0.0.1 --port "$PORT" --alias "glm-$name" \
    --device ROCm0 --gpu-layers all --flash-attn on --fit off \
    --load-mode mmap+mlock --ctx-size "$CTX" --batch-size 512 --ubatch-size 256 \
    --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
    --reasoning off --jinja --no-webui \
    "$@" >"$d/server.log" 2>&1 &
  echo $! >"$d/server.pid"
  wait_health "$PORT" "$(cat "$d/server.pid")" "$d"
}

do_completion() {
  local tag=$1 prompt=$2
  local pfile="$OUT/${tag}.prompt.txt"
  printf '%s' "$prompt" >"$pfile"
  python3 - "$PORT" "$tag" "$pfile" "$NPRED" "$OUT" <<'PY'
import json, sys, urllib.request, hashlib
port, tag, pfile, npred, out = sys.argv[1:6]
prompt = open(pfile, encoding="utf-8").read()
body = json.dumps({"prompt": prompt, "n_predict": int(npred), "temperature": 0}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/completion", data=body,
    headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=900) as r:
    data = r.read()
open(f"{out}/{tag}.json", "wb").write(data)
j = json.loads(data)
t = j.get("timings", {})
content = j.get("content") or ""
open(f"{out}/{tag}.txt", "w", encoding="utf-8").write(content)
open(f"{out}/{tag}.timings.json", "w").write(json.dumps(t, indent=2))
dn = t.get("draft_n")
da = t.get("draft_n_accepted")
acc = ""
if dn is not None and da is not None and dn:
    acc = f"{da}/{dn}={100.0*da/dn:.2f}%"
print(f"{tag}: tok/s={t.get('predicted_per_second',0):.2f} "
      f"pred_n={t.get('predicted_n')} draft_n={dn} accept={acc} "
      f"sha1={hashlib.sha1(content.encode()).hexdigest()[:12]}")
print(f"  content[:100]={content[:100]!r}")
PY
}

compare_baseline() {
  local tag=$1 baseline_tag=$2
  python3 - "$OUT" "$tag" "$baseline_tag" <<'PY'
import sys, hashlib
from pathlib import Path
out, tag, base = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
a = (out/f"{tag}.txt").read_text(encoding="utf-8") if (out/f"{tag}.txt").exists() else None
b = (out/f"{base}.txt").read_text(encoding="utf-8") if (out/f"{base}.txt").exists() else None
if a is None or b is None:
    print(f"{tag} vs {base}: MISSING"); sys.exit(0)
match = "Y" if a == b else "N"
print(f"{tag} vs {base}: match={match} len={len(a)}/{len(b)}")
open(out/f"{tag}.vs_{base}.match","w").write(match+"\n")
PY
}

summarize() {
  python3 - "$OUT" <<'PY'
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
print("=== TABLE ===")
print(f"{'tag':40} {'tok/s':>8} {'accept':>18} {'pred_n':>7}")
for p in sorted(out.glob("*.json")):
    if p.name.endswith(".timings.json"): continue
    j = json.load(open(p))
    t = j.get("timings", {})
    dn, da = t.get("draft_n"), t.get("draft_n_accepted")
    acc = f"{da}/{dn}" if dn is not None else "-"
    if dn and da is not None:
        acc += f" ({100*da/dn:.1f}%)"
    print(f"{p.stem:40} {t.get('predicted_per_second') or 0:8.2f} {acc:>18} {t.get('predicted_n') or 0:7}")
print("OUT", out)
PY
}

# --- configs: list of (name, model, args...) ---
# Priority: MTP n1-3 chat/code, DFlash2 on UD, DFlash2 AJ baseline, then agent/ngram

need_ud=0
need_aj=0
[[ -f "$MODEL_UD" ]] || { log "WARN: UD model missing: $MODEL_UD"; need_ud=1; }
[[ -f "$MODEL_AJ" ]] || { log "ABORT: AJ model missing"; exit 2; }
[[ -f "$DRAFT" ]] || { log "ABORT: draft missing"; exit 2; }
[[ -x "$BIN" ]] || { log "ABORT: bin missing $BIN"; exit 2; }

# 1) Baseline: DFlash2 n3 on AJ (reference)
run_server "baseline-aj-dflash-n3" "$MODEL_AJ" \
  -md "$DRAFT" --spec-type draft-dflash --spec-draft-n-max 3 --spec-draft-ngl 999
do_completion "baseline-aj-dflash-n3-chat" "$CHAT"
do_completion "baseline-aj-dflash-n3-code" "$CODE"
kill_port "$PORT"

if [[ $need_ud -eq 0 ]]; then
  # 2) MTP n_max 1/2/3 on UD
  for N in 1 2 3; do
    run_server "ud-mtp-n${N}" "$MODEL_UD" \
      --spec-type draft-mtp --spec-draft-n-max "$N"
    do_completion "ud-mtp-n${N}-chat" "$CHAT"
    do_completion "ud-mtp-n${N}-code" "$CODE"
    compare_baseline "ud-mtp-n${N}-chat" "baseline-aj-dflash-n3-chat"
    compare_baseline "ud-mtp-n${N}-code" "baseline-aj-dflash-n3-code"
    kill_port "$PORT"
  done

  # 3) DFlash2 n3 on UD
  run_server "ud-dflash-n3" "$MODEL_UD" \
    -md "$DRAFT" --spec-type draft-dflash --spec-draft-n-max 3 --spec-draft-ngl 999
  do_completion "ud-dflash-n3-chat" "$CHAT"
  do_completion "ud-dflash-n3-code" "$CODE"
  compare_baseline "ud-dflash-n3-chat" "baseline-aj-dflash-n3-chat"
  compare_baseline "ud-dflash-n3-code" "baseline-aj-dflash-n3-code"
  kill_port "$PORT"

  # 4) Agent prompts on best MTP so far (n=2 default; caller can re-run) + ngram combo
  if [[ "${RUN_AGENT:-1}" == "1" ]]; then
    BEST_N="${BEST_MTP_N:-2}"
    run_server "ud-mtp-n${BEST_N}-agent" "$MODEL_UD" \
      --spec-type draft-mtp --spec-draft-n-max "$BEST_N"
    for af in "$AGENT_DIR"/01_code_edit_python.txt "$AGENT_DIR"/04_tool_call_plaintext_fallback.txt "$AGENT_DIR"/05_explain_rocm_dspark.txt; do
      [[ -f "$af" ]] || continue
      tag="ud-mtp-n${BEST_N}-agent-$(basename "$af" .txt)"
      do_completion "$tag" "$(cat "$af")"
    done
    kill_port "$PORT"
  fi

  if [[ "${RUN_NGRAM:-1}" == "1" ]]; then
    # MTP + ngram-mod combo (supported as comma-separated --spec-type)
    run_server "ud-mtp-n2-ngram" "$MODEL_UD" \
      --spec-type draft-mtp,ngram-mod --spec-draft-n-max 2 \
      --spec-ngram-mod-n-match 6 --spec-ngram-mod-n-min 12 --spec-ngram-mod-n-max 16
    do_completion "ud-mtp-n2-ngram-chat" "$CHAT"
    do_completion "ud-mtp-n2-ngram-code" "$CODE"
    kill_port "$PORT"

    # ngram-mod alone (sanity)
    run_server "ud-ngram-only" "$MODEL_UD" \
      --spec-type ngram-mod \
      --spec-ngram-mod-n-match 6 --spec-ngram-mod-n-min 12 --spec-ngram-mod-n-max 16
    do_completion "ud-ngram-only-chat" "$CHAT"
    do_completion "ud-ngram-only-code" "$CODE"
    kill_port "$PORT"
  fi
else
  log "SKIP all UD configs — model not ready"
fi

summarize
log "done OUT=$OUT"
echo "$OUT" > "$OUT/OUT_PATH.txt"
