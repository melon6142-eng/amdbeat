#!/usr/bin/env bash
set -euo pipefail
STAMP=$(date +%Y%m%d_%H%M%S)
LOGDIR=~/logs/glm-batchverify-sweep-${STAMP}
mkdir -p "$LOGDIR"
PREV=~/logs/glm-batchverify-sweep-20260924_222101
CHAT_PROMPT=$(cat "$PREV/baseline-nmax3-chat.prompt.txt")
CODE_PROMPT=$(cat "$PREV/baseline-nmax3-code.prompt.txt")
echo "LOGDIR=$LOGDIR" | tee /tmp/bv-sweep-logdir.txt

gpu_check() {
  echo "=== GPU CHECK $(date '+%Y-%m-%d %H:%M:%S %Z') ==="
  rocm-smi --showuse --showmeminfo vram 2>/dev/null | head -20 || true
  ss -ltnp 2>/dev/null | grep -E ':8080|:8088|:8000' || true
  pgrep -af 'llama-server|vllm' | grep -v grep || echo 'no llama/vllm'
}

wait_health() {
  local port=$1 max=${2:-300}
  for i in $(seq 1 $max); do
    if curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      echo "health ok port=$port after ${i}s"
      return 0
    fi
    sleep 1
  done
  echo "HEALTH FAIL port=$port"
  return 1
}

stop_port() {
  local port=$1
  local pids
  pids=$(ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}' | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
  if [ -n "$pids" ]; then
    echo "killing port $port pids: $pids"
    kill $pids 2>/dev/null || true
    sleep 3
    kill -9 $pids 2>/dev/null || true
  fi
  pkill -f "llama-server.*--port ${port}" 2>/dev/null || true
  sleep 2
}

run_one() {
  local port=$1 tag=$2 kind=$3
  local prompt n_predict=256
  if [ "$kind" = chat ]; then prompt="$CHAT_PROMPT"; else prompt="$CODE_PROMPT"; fi
  local out="$LOGDIR/${tag}-${kind}"
  printf '%s' "$prompt" > "${out}.prompt.txt"
  python3 - "$port" "$prompt" "$n_predict" "${out}.json" "${out}.txt" "${out}.timings.json" <<'PY'
import json,sys,urllib.request
port,prompt,npred,jpath,tpath,timpath = sys.argv[1:7]
body=json.dumps({
  "prompt": prompt,
  "n_predict": int(npred),
  "temperature": 0.0,
  "stream": False,
}).encode()
req=urllib.request.Request(f"http://127.0.0.1:{port}/completion", data=body,
  headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req, timeout=600) as r:
  data=json.load(r)
with open(jpath,"w") as f: json.dump(data,f,indent=2,ensure_ascii=False)
content=data.get("content","")
with open(tpath,"w") as f: f.write(content)
tim=data.get("timings",{})
with open(timpath,"w") as f: json.dump(tim,f,indent=2)
dn=tim.get("draft_n") or 0
da=tim.get("draft_n_accepted") or 0
acc=(100.0*da/dn) if dn else 0.0
print(f"OK tag_port={port} pred_tps={tim.get('predicted_per_second')} acc={acc:.4f}% draft={da}/{dn} pred_n={tim.get('predicted_n')}")
PY
}

compare_to_baseline() {
  local tag=$1 kind=$2
  local base="$LOGDIR/baseline-nmax3-${kind}.txt"
  local cur="$LOGDIR/${tag}-${kind}.txt"
  if [ ! -f "$base" ]; then echo NO_BASE; return; fi
  if cmp -s "$base" "$cur"; then echo Y; else echo N; fi
}

gpu_check | tee "$LOGDIR/gpu-pre.txt"
stop_port 8080
stop_port 8088
gpu_check | tee -a "$LOGDIR/gpu-pre.txt"

echo "starting baseline :8080"
nohup env SPEC_DRAFT_N_MAX=3 ~/bin/evo-serve-glm53-dflash.sh > "$LOGDIR/server-baseline-n3.log" 2>&1 &
echo $! > "$LOGDIR/server-baseline-n3.pid"
wait_health 8080 360
run_one 8080 baseline-nmax3 chat
run_one 8080 baseline-nmax3 code
stop_port 8080
sleep 5
gpu_check | tee "$LOGDIR/gpu-after-baseline.txt"

for NMAX in 3 5 7 8; do
  gpu_check | tee "$LOGDIR/gpu-pre-bv-n${NMAX}.txt"
  if ss -ltnp 2>/dev/null | grep -qE ':8080|:8000'; then
    echo ABORT unexpected server; exit 2
  fi
  echo "starting batchverify n_max=$NMAX on :8088"
  if [ "$NMAX" = 8 ]; then
    export GGML_MMVQ_MMID_MAX=16
  else
    unset GGML_MMVQ_MMID_MAX || true
  fi
  if [ -n "${GGML_MMVQ_MMID_MAX-}" ]; then
    nohup env SPEC_DRAFT_N_MAX=$NMAX GGML_MMVQ_MMID_MAX=$GGML_MMVQ_MMID_MAX \
      ~/bin/evo-serve-glm53-batchverify.sh > "$LOGDIR/server-bv-n${NMAX}.log" 2>&1 &
  else
    nohup env SPEC_DRAFT_N_MAX=$NMAX \
      ~/bin/evo-serve-glm53-batchverify.sh > "$LOGDIR/server-bv-n${NMAX}.log" 2>&1 &
  fi
  echo $! > "$LOGDIR/server-bv-n${NMAX}.pid"
  if ! wait_health 8088 360; then
    echo "FAIL start n=$NMAX" | tee "$LOGDIR/bv-nmax${NMAX}-fail.txt"
    tail -80 "$LOGDIR/server-bv-n${NMAX}.log" > "$LOGDIR/server-bv-n${NMAX}.tail.txt" || true
    stop_port 8088
    continue
  fi
  TAG="bv-nmax${NMAX}"
  run_one 8088 "$TAG" chat || echo "chat fail n=$NMAX" | tee "$LOGDIR/${TAG}-chat.fail"
  run_one 8088 "$TAG" code || echo "code fail n=$NMAX" | tee "$LOGDIR/${TAG}-code.fail"
  for kind in chat code; do
    if [ -f "$LOGDIR/${TAG}-${kind}.txt" ]; then
      compare_to_baseline "$TAG" "$kind" > "$LOGDIR/${TAG}-${kind}.match"
    fi
  done
  stop_port 8088
  sleep 5
done

python3 - "$LOGDIR" <<'PY'
import json,os,sys,glob
logdir=sys.argv[1]
rows=[]
for path in sorted(glob.glob(logdir+"/*.timings.json")):
  tag=os.path.basename(path).replace(".timings.json","")
  with open(path) as f: tim=json.load(f)
  dn=tim.get("draft_n") or 0
  da=tim.get("draft_n_accepted") or 0
  acc=(100.0*da/dn) if dn else None
  match_p=path.replace(".timings.json",".match")
  match=open(match_p).read().strip() if os.path.exists(match_p) else ("—" if tag.startswith("baseline") else "?")
  rows.append({
    "tag": tag,
    "pred_tps": tim.get("predicted_per_second"),
    "draft_n": dn,
    "draft_n_accepted": da,
    "acc_pct": acc,
    "pred_n": tim.get("predicted_n"),
    "match_baseline": match,
  })
with open(logdir+"/summary.json","w") as f: json.dump(rows,f,indent=2)
print(json.dumps(rows,indent=2))
PY

echo SWEEP_DONE
date
