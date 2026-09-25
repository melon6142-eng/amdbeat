#!/usr/bin/env bash
# Priority MTP comparison for hop-grok4.7-2. Start only after 06:30 CST + free lock.
set -euo pipefail

START_AFTER="${START_AFTER:-0630}"  # HHMM CST
DEADLINE="${DEADLINE:-0740}"        # stop new configs after this
OWNER_LINE_PREFIX="hop-grok4.7-2 glm-mtp"
LOCK="$HOME/.gpu-owner"
OUT_ROOT="$HOME/logs"
STAMP=$(date +%Y%m%d_%H%M%S)
OUT="$OUT_ROOT/glm-mtp-compare-$STAMP"
mkdir -p "$OUT"
LOG="$OUT/orchestrator.log"
exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S CST')] $*"; }

hhmm() { date +%H%M; }

wait_until_start() {
  while true; do
    now=$(hhmm)
    # base-10 to avoid bash octal (0630)
    if (( 10#$now >= 10#$START_AFTER )); then
      break
    fi
    log "waiting for $START_AFTER CST (now $now); lock=$(cat "$LOCK" 2>/dev/null || echo NO_LOCK)"
    sleep 60
  done
}

acquire_lock() {
  # Wait until lock free (other agents) or abort near deadline
  while [ -e "$LOCK" ]; do
    log "lock busy: $(cat "$LOCK"); waiting"
    if past_deadline; then log "ABORT: lock still held at deadline"; exit 3; fi
    sleep 30
  done
  if ss -ltnp 2>/dev/null | grep -qE ':8088'; then
    log "WARN: :8088 still listening (batchverify?); waiting up to deadline"
    while ss -ltnp 2>/dev/null | grep -qE ':8088'; do
      if past_deadline; then log "ABORT: :8088 still up"; exit 3; fi
      sleep 30
    done
  fi
  if pgrep -x ds4-server >/dev/null 2>&1; then
    log "ABORT: ds4-server running"; exit 2
  fi
  # Final idle check
  rocm-smi --showuse 2>/dev/null | tee -a "$LOG" || true
  echo "6142" | sudo -S podman ps --format "{{.Names}} {{.Status}}" 2>/dev/null | tee -a "$LOG" || true
  ss -ltnp 2>/dev/null | grep -E "llama|8080|8088" | tee -a "$LOG" || true
  echo "$OWNER_LINE_PREFIX $(date "+%H:%M CST")" > "$LOCK"
  log "acquired lock: $(cat "$LOCK")"
}

release_lock() {
  if [ -f "$LOCK" ] && grep -q "hop-grok4.7-2 glm-mtp" "$LOCK"; then
    rm -f "$LOCK"
    log "released lock"
  else
    log "lock not ours or missing: $(cat "$LOCK" 2>/dev/null || echo none)"
  fi
}

kill_port() { fuser -k "${1}/tcp" 2>/dev/null || true; sleep 2; }

# Prefer vcruz (hostreg + proven HIP); eauchs as alt via BIN_MTP
BIN="${BIN:-$HOME/src/llama-dflash2-vcruz/build-hip-dflash/bin/llama-server}"
BIN_MTP="${BIN_MTP:-$HOME/src/llama-glm5next-mtp-eauchs/build-hip-mtp/bin/llama-server}"
# Use vcruz for MTP too (has graph_mtp); fall back to eauchs if requested USE_EAUCHS=1
if [ "${USE_EAUCHS:-0}" = "1" ] && [ -x "$BIN_MTP" ]; then
  BIN="$BIN_MTP"
fi
MODEL_UD="${MODEL_UD:-$HOME/models/gguf/GLM-5.3-Flash-UD-IQ2_XXS/GLM-5.3-Flash-UD-IQ2_XXS-00001-of-00004.gguf}"
MODEL_AJ="${MODEL_AJ:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
DRAFT="${DRAFT:-$HOME/models/gguf/GLM-5.3-Flash-DFlash2/GLM-5.3-Flash-DFlash2-BF16.gguf}"
PORT="${PORT:-8095}"
NPRED="${NPRED:-256}"
CTX="${CTX:-16384}"
export LD_LIBRARY_PATH="$(dirname "$BIN"):/opt/rocm-7.2.1/lib:${LD_LIBRARY_PATH:-}"
export GGML_CUDA_REGISTER_HOST=1
unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true

CHAT='Write a one-sentence greeting, then explain in 3 short paragraphs what speculative decoding is.'
CODE=$'```python\ndef fib(n):\n'

past_deadline() { (( 10#$(hhmm) >= 10#$DEADLINE )); }

wait_health() {
  local spid=$1 d=$2
  for i in $(seq 1 240); do
    if curl -sf "http://127.0.0.1:${PORT}/health" 2>/dev/null | grep -q ok; then return 0; fi
    if ! kill -0 "$spid" 2>/dev/null; then log "server died"; tail -80 "$d/server.log"; return 1; fi
    sleep 2
  done
  log "health timeout"; return 1
}

run_server() {
  local name=$1; shift
  local model=$1; shift
  local d="$OUT/$name"; mkdir -p "$d"
  kill_port "$PORT"
  log "[$name] start bin=$(basename "$(dirname "$BIN")")/$(basename "$BIN") model=$(basename "$model") $*"
  "$BIN" -m "$model" --host 127.0.0.1 --port "$PORT" --alias "glm-$name" \
    --device ROCm0 --gpu-layers all --flash-attn on --fit off \
    --load-mode mmap+mlock --ctx-size "$CTX" --batch-size 512 --ubatch-size 256 \
    --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
    --reasoning off --jinja --no-webui \
    "$@" >"$d/server.log" 2>&1 &
  echo $! >"$d/server.pid"
  wait_health "$(cat "$d/server.pid")" "$d"
}

do_completion() {
  local tag=$1 prompt=$2
  printf '%s' "$prompt" >"$OUT/${tag}.prompt.txt"
  python3 - "$PORT" "$tag" "$NPRED" "$OUT" <<'PY'
import json,sys,urllib.request,hashlib
port,tag,npred,out=sys.argv[1:5]
prompt=open(f"{out}/{tag}.prompt.txt",encoding="utf-8").read()
body=json.dumps({"prompt":prompt,"n_predict":int(npred),"temperature":0}).encode()
req=urllib.request.Request(f"http://127.0.0.1:{port}/completion",data=body,headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req,timeout=900) as r: data=r.read()
open(f"{out}/{tag}.json","wb").write(data)
j=json.loads(data); t=j.get("timings",{}); content=j.get("content") or ""
open(f"{out}/{tag}.txt","w",encoding="utf-8").write(content)
open(f"{out}/{tag}.timings.json","w").write(json.dumps(t,indent=2))
dn,da=t.get("draft_n"),t.get("draft_n_accepted")
acc=f"{da}/{dn}={100*da/dn:.2f}%" if dn else "-"
print(f"{tag}: tok/s={t.get('predicted_per_second',0):.2f} accept={acc} sha={hashlib.sha1(content.encode()).hexdigest()[:12]}")
PY
}

cmp_base() {
  local tag=$1 base=$2
  python3 - <<PY
from pathlib import Path
out=Path("$OUT")
a=(out/"$tag.txt").read_text(encoding="utf-8") if (out/"$tag.txt").exists() else None
b=(out/"$base.txt").read_text(encoding="utf-8") if (out/"$base.txt").exists() else None
m="MISSING" if a is None or b is None else ("Y" if a==b else "N")
print(f"$tag vs $base: {m}")
(out/f"$tag.vs_baseline.match").write_text(m+"\n")
PY
}

restore_8080() {
  local best_cfg="$1"  # path to a small cfg file or literal
  log "restoring :8080 with config: $best_cfg"
  # stop test port
  kill_port "$PORT"
  # stop current 8080
  kill_port 8080
  sleep 2
  case "$best_cfg" in
    mtp-*)
      N=${best_cfg#mtp-n}
      nohup env SPEC_DRAFT_N_MAX="$N" SPEC_TYPE=draft-mtp \
        MODEL="$MODEL_UD" BIN="$BIN" \
        "$HOME/bin/evo-serve-glm53-mtp.sh" >"$OUT/serve-8080.nohup" 2>&1 &
      echo $! >"$OUT/serve-8080.pid"
      ;;
    dflash-ud-n3)
      nohup env MODEL="$MODEL_UD" SPEC_DRAFT_N_MAX=3 \
        BIN="$BIN" DRAFT="$DRAFT" \
        bash -c 'exec "$BIN" -m "$MODEL" -md "$DRAFT" --spec-type draft-dflash --spec-draft-n-max 3 --spec-draft-ngl 999 --host 0.0.0.0 --port 8080 --alias glm53-ud-dflash --device ROCm0 --gpu-layers all --flash-attn on --fit off --load-mode mmap+mlock --ctx-size 36864 --batch-size 512 --ubatch-size 256 --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 --reasoning off --jinja --no-webui' \
        >"$OUT/serve-8080.nohup" 2>&1 &
      echo $! >"$OUT/serve-8080.pid"
      ;;
    *)
      # default: original dflash AJ n3 via original launcher (do not edit it)
      nohup "$HOME/bin/evo-serve-glm53-dflash.sh" >"$OUT/serve-8080.nohup" 2>&1 &
      echo $! >"$OUT/serve-8080.pid"
      ;;
  esac
  for i in $(seq 1 180); do
    if curl -sf http://127.0.0.1:8080/health 2>/dev/null | grep -q ok; then
      log ":8080 health ok"
      curl -s http://127.0.0.1:8080/health; echo
      return 0
    fi
    sleep 2
  done
  log "FAIL :8080 health"
  tail -50 "$OUT/serve-8080.nohup" || true
  return 1
}

# ---- main ----
wait_until_start
acquire_lock
trap 'log "trap cleanup"; kill_port "$PORT" || true; release_lock' EXIT

# Stop :8080 for memory (will restore at end)
log "stopping :8080 for bench memory"
kill_port 8080

# Preflight
if [ ! -x "$BIN" ]; then log "ABORT no bin $BIN"; exit 2; fi
if [ ! -f "$MODEL_AJ" ]; then log "ABORT no AJ"; exit 2; fi
if [ ! -f "$DRAFT" ]; then log "ABORT no draft"; exit 2; fi
UD_OK=0
if [ -f "$MODEL_UD" ]; then
  # require all 4 shards present with expected sizes roughly
  n=$(ls "$HOME/models/gguf/GLM-5.3-Flash-UD-IQ2_XXS"/GLM-5.3-Flash-UD-IQ2_XXS-0000*-of-00004.gguf 2>/dev/null | wc -l)
  if [ "$n" -ge 4 ]; then UD_OK=1; else log "WARN UD shards=$n (need 4)"; fi
else
  log "WARN UD model missing"
fi
echo "BIN=$BIN" >"$OUT/env.txt"
echo "UD_OK=$UD_OK" >>"$OUT/env.txt"
log "BIN=$BIN UD_OK=$UD_OK"

BEST="baseline-aj"   # default restore
BEST_TPS=0

# 0b) If UD incomplete: exploratory MTP on AJ (may no-op if no NextN tensors)
if [ "$UD_OK" != "1" ] && ! past_deadline; then
  log "UD incomplete — trying draft-mtp on AJ as fallback"
  for N in 1 2 3; do
    past_deadline && break
    run_server "aj-mtp-n${N}" "$MODEL_AJ" --spec-type draft-mtp --spec-draft-n-max "$N" || { log "aj-mtp-n$N server failed"; continue; }
    do_completion "aj-mtp-n${N}-chat" "$CHAT" || true
    do_completion "aj-mtp-n${N}-code" "$CODE" || true
    kill_port "$PORT"
  done
fi

# 1) Baseline AJ DFlash n3
run_server baseline-aj-dflash-n3 "$MODEL_AJ" \
  -md "$DRAFT" --spec-type draft-dflash --spec-draft-n-max 3 --spec-draft-ngl 999
do_completion baseline-aj-dflash-n3-chat "$CHAT"
do_completion baseline-aj-dflash-n3-code "$CODE"
kill_port "$PORT"
# record baseline tps
BEST_TPS=$(python3 -c "import json;print(json.load(open('$OUT/baseline-aj-dflash-n3-code.json'))['timings']['predicted_per_second'])")
BEST="baseline-aj"
log "baseline code tok/s=$BEST_TPS"

if [ "$UD_OK" = "1" ] && ! past_deadline; then
  for N in 1 2 3; do
    past_deadline && { log "deadline hit before MTP n$N"; break; }
    run_server "ud-mtp-n${N}" "$MODEL_UD" --spec-type draft-mtp --spec-draft-n-max "$N"
    do_completion "ud-mtp-n${N}-chat" "$CHAT"
    do_completion "ud-mtp-n${N}-code" "$CODE"
    cmp_base "ud-mtp-n${N}-chat" baseline-aj-dflash-n3-chat
    cmp_base "ud-mtp-n${N}-code" baseline-aj-dflash-n3-code
    kill_port "$PORT"
    tps=$(python3 -c "import json;print(json.load(open('$OUT/ud-mtp-n${N}-code.json'))['timings']['predicted_per_second'])")
    # pick best by mean of chat+code if both ok
    chat=$(python3 -c "import json;print(json.load(open('$OUT/ud-mtp-n${N}-chat.json'))['timings']['predicted_per_second'])")
    mean=$(python3 -c "print(($chat+$tps)/2)")
    log "MTP n$N mean tok/s=$mean (chat=$chat code=$tps)"
    python3 -c "import sys; sys.exit(0 if float('$mean')>float('$BEST_TPS') else 1)" && {
      BEST="mtp-n$N"; BEST_TPS=$mean; log "new best $BEST mean=$BEST_TPS"
    } || true
  done
fi

if [ "$UD_OK" = "1" ] && ! past_deadline; then
  run_server ud-dflash-n3 "$MODEL_UD" \
    -md "$DRAFT" --spec-type draft-dflash --spec-draft-n-max 3 --spec-draft-ngl 999
  do_completion ud-dflash-n3-chat "$CHAT"
  do_completion ud-dflash-n3-code "$CODE"
  cmp_base ud-dflash-n3-chat baseline-aj-dflash-n3-chat
  cmp_base ud-dflash-n3-code baseline-aj-dflash-n3-code
  kill_port "$PORT"
  chat=$(python3 -c "import json;print(json.load(open('$OUT/ud-dflash-n3-chat.json'))['timings']['predicted_per_second'])")
  code=$(python3 -c "import json;print(json.load(open('$OUT/ud-dflash-n3-code.json'))['timings']['predicted_per_second'])")
  mean=$(python3 -c "print(($chat+$code)/2)")
  log "UD DFlash n3 mean=$mean"
  python3 -c "import sys; sys.exit(0 if float('$mean')>float('$BEST_TPS') else 1)" && {
    BEST="dflash-ud-n3"; BEST_TPS=$mean; log "new best $BEST"
  } || true
fi

# Optional agent + ngram if time remains
if [ "$UD_OK" = "1" ] && ! past_deadline; then
  BEST_N=2
  case "$BEST" in mtp-n*) BEST_N=${BEST#mtp-n};; esac
  for af in "$HOME/bench/ds-agent-prompts/cli-text/01_code_edit_python.txt"; do
    [ -f "$af" ] || continue
    past_deadline && break
    run_server "ud-mtp-agent" "$MODEL_UD" --spec-type draft-mtp --spec-draft-n-max "$BEST_N"
    do_completion "ud-mtp-n${BEST_N}-agent-01" "$(cat "$af")"
    kill_port "$PORT"
  done
fi

if [ "$UD_OK" = "1" ] && ! past_deadline; then
  run_server ud-mtp-ngram "$MODEL_UD" \
    --spec-type draft-mtp,ngram-mod --spec-draft-n-max 2 \
    --spec-ngram-mod-n-match 6 --spec-ngram-mod-n-min 12 --spec-ngram-mod-n-max 16
  do_completion ud-mtp-n2-ngram-chat "$CHAT"
  do_completion ud-mtp-n2-ngram-code "$CODE"
  kill_port "$PORT"
fi

# Summarize
python3 - "$OUT" <<'PY'
import json,sys
from pathlib import Path
out=Path(sys.argv[1])
print("=== RESULTS ===")
print(f"{'tag':42} {'tok/s':>8} {'accept':>20} {'pred_n':>7}")
for p in sorted(out.glob("*.json")):
  if p.name.endswith(".timings.json"): continue
  j=json.load(open(p)); t=j.get("timings",{})
  dn,da=t.get("draft_n"),t.get("draft_n_accepted")
  acc="-"
  if dn: acc=f"{da}/{dn} ({100*da/dn:.1f}%)"
  print(f"{p.stem:42} {t.get('predicted_per_second') or 0:8.2f} {acc:>20} {t.get('predicted_n') or 0:7}")
print("OUT", out)
PY

echo "$BEST" >"$OUT/BEST_CONFIG.txt"
echo "$BEST_TPS" >"$OUT/BEST_TPS.txt"
log "BEST=$BEST tps=$BEST_TPS"

# Restore :8080
# Correctness gate: if MTP best but outputs wildly broken, fall back
restore_8080 "$BEST" || restore_8080 baseline-aj

release_lock
trap - EXIT
log "DONE OUT=$OUT BEST=$BEST"
echo "$OUT"
