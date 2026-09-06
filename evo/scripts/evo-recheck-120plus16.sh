#!/usr/bin/env bash
# Recheck earlier failures with the real cap: AMD ~120G + 4080 ~16G ≈ 130G
# one process. 4080 stays ≤14G. Mac is overflow only, not for an 81G file.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="$MIX/llama-server"
DS="$HOME/models/gguf/DeepSeek-V4-Flash-IQ2XXS/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf"
GLM="$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf"
OUT="$HOME/logs/recheck-120plus16"
RPC="${RPC:-<host>:50052}"
mkdir -p "$OUT"
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GGML_RPC_NO_RDMA=1
unset VK_ICD_FILENAMES

stop_all() {
  fuser -k 8080/tcp 8081/tcp 8090/tcp 2>/dev/null || true
  pkill -x llama-server || true
  sleep 2
}

wait_health() {
  local port="$1" log="$2" secs="${3:-480}"
  python3 - "$port" "$log" "$secs" <<'PY'
import sys, time, urllib.request
port, log, secs = sys.argv[1], sys.argv[2], int(sys.argv[3])
t0 = time.time()
while time.time() - t0 < secs:
    try:
        text = open(log, errors="replace").read()
    except FileNotFoundError:
        text = ""
    low = text.lower()
    if any(s in low for s in ("out of memory", "failed to allocate", "unable to allocate", "erroroutofdevicememory", "failed to load model")):
        print("oom")
        sys.exit(2)
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as r:
            if b"ok" in r.read():
                print("ok")
                sys.exit(0)
    except Exception:
        pass
    time.sleep(4)
print("hang" if "threadpool" in open(log, errors="replace").read() else "timeout")
sys.exit(1)
PY
}

bench() {
  local port="$1" model="$2"
  python3 - "$port" "$model" <<'PY'
import json, sys, time, urllib.request
port, model = sys.argv[1], sys.argv[2]
body = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": "Say ok in one word, then one short sentence."}],
    "max_tokens": 64,
    "temperature": 0,
}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/chat/completions",
    data=body, headers={"Content-Type": "application/json"}, method="POST",
)
t0 = time.time()
with urllib.request.urlopen(req, timeout=180) as resp:
    data = json.loads(resp.read().decode())
t = data.get("timings") or {}
print(json.dumps({
    "wall_s": round(time.time()-t0, 2),
    "prompt_tps": t.get("prompt_per_second"),
    "gen_tps": t.get("predicted_per_second"),
    "pred_n": t.get("predicted_n"),
}))
PY
}

nvidia() { nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits | head -1; }

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$OUT/supervisor.log"; }

run_ds() {
  local name="$1" devices="$2" ts="$3"
  shift 3
  local extra=("$@")
  local slog="$OUT/${name}.log"
  local result="$OUT/${name}.json"
  stop_all
  : >"$slog"
  log "START $name dev=$devices ts=$ts extra=${extra[*]-}"
  local rpc_args=()
  if [[ "$devices" == *RPC0* ]]; then
    rpc_args=(--rpc "$RPC")
  fi
  nohup "$BIN" -m "$DS" --host 127.0.0.1 --port 8090 --alias "$name" \
    "${rpc_args[@]}" \
    --device "$devices" --split-mode layer --tensor-split "$ts" \
    --gpu-layers all --flash-attn on --fit off \
    --no-host --load-mode mmap \
    --ctx-size 4096 --batch-size 512 --ubatch-size 128 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --threads 32 --threads-batch 32 \
    --jinja --no-webui --metrics --parallel 1 \
    "${extra[@]}" \
    >"$slog" 2>&1 &
  local health
  health=$(wait_health 8090 "$slog" 420 || true)
  local mem
  mem=$(nvidia)
  if [[ "$health" != "ok" ]]; then
    log "FAIL $name $health mem=$mem"
    python3 -c 'import json,sys; json.dump({"name":sys.argv[1],"status":sys.argv[2],"nvidia":sys.argv[3],"devices":sys.argv[4],"ts":sys.argv[5]}, open(sys.argv[6],"w"), indent=2)' \
      "$name" "$health" "$mem" "$devices" "$ts" "$result"
    stop_all
    return 1
  fi
  # warmup + one timed
  bench 8090 "$name" >/dev/null || true
  local b
  b=$(bench 8090 "$name")
  log "OK $name $b mem=$mem"
  python3 -c 'import json,sys; json.dump({"name":sys.argv[1],"status":"ok","nvidia":sys.argv[2],"devices":sys.argv[3],"ts":sys.argv[4],"bench":json.loads(sys.argv[5])}, open(sys.argv[6],"w"), indent=2)' \
    "$name" "$mem" "$devices" "$ts" "$b" "$result"
  stop_all
}

# 1) 81G fits in 120+16 — AMD+4080, 4080 ~11G (14%), no Mac
run_ds ds_amd4080_86_14 "Vulkan1,Vulkan0" "86,14" || true

# 2) Overnight RPC hang: Mac at 0% + KV local. 81G should not need overflow.
if nc -z -w 2 <host> 50052; then
  run_ds ds_rpc_86_14_0_nokv "Vulkan1,Vulkan0,RPC0" "86,14,0" --no-kv-offload || true
  # 3) RPC attached but no 4080/Mac weights — is the socket enough to hang?
  run_ds ds_rpc_100_0_nokv "Vulkan1,RPC0" "100,0" --no-kv-offload || true
else
  log "rpc down — skip 3-way rechecks"
fi

# 4) Dual OOM recheck: one model on AMD 120, the other on 4080 only (cpu-moe)
stop_all
log "START dual isolated"
nohup "$BIN" -m "$DS" --host 127.0.0.1 --port 8080 --alias deepseek4-iq2-amd \
  --device Vulkan1 --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap \
  --ctx-size 4096 --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 --jinja --no-webui --metrics --parallel 1 \
  >"$OUT/dual-ds.log" 2>&1 &
ds_h=$(wait_health 8080 "$OUT/dual-ds.log" 180 || true)
if [[ "$ds_h" == "ok" ]]; then
  nohup "$BIN" -m "$GLM" --host 127.0.0.1 --port 8081 --alias glm53-4080 \
    --device Vulkan0 --cpu-moe --gpu-layers all --flash-attn on --fit on \
    --no-host --load-mode mmap \
    --ctx-size 2048 --batch-size 256 --ubatch-size 64 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --threads 16 --threads-batch 16 \
    --reasoning off --reasoning-budget 0 \
    --jinja --no-webui --metrics --parallel 1 \
    >"$OUT/dual-glm.log" 2>&1 &
  glm_h=$(wait_health 8081 "$OUT/dual-glm.log" 180 || true)
else
  glm_h="skipped"
fi
ds_still=$(curl -fsS --max-time 2 http://127.0.0.1:8080/health 2>/dev/null || echo down)
mem=$(nvidia)
log "dual ds=$ds_h glm=$glm_h ds_still=$ds_still mem=$mem"
if [[ "$ds_h" == "ok" && "$glm_h" == "ok" ]]; then
  ds_b=$(bench 8080 deepseek4-iq2-amd || echo '{"error":1}')
  glm_b=$(bench 8081 glm53-4080 || echo '{"error":1}')
  python3 -c 'import json,sys; json.dump({"name":"dual_isolated","status":"ok","nvidia":sys.argv[1],"ds":json.loads(sys.argv[2]),"glm":json.loads(sys.argv[3])}, open(sys.argv[4],"w"), indent=2)' \
    "$mem" "$ds_b" "$glm_b" "$OUT/dual_isolated.json"
  log "OK dual ds=$ds_b glm=$glm_b"
else
  python3 -c 'import json,sys; json.dump({"name":"dual_isolated","status":"fail","ds":sys.argv[1],"glm":sys.argv[2],"ds_still":sys.argv[3],"nvidia":sys.argv[4]}, open(sys.argv[5],"w"), indent=2)' \
    "$ds_h" "$glm_h" "$ds_still" "$mem" "$OUT/dual_isolated.json"
fi
stop_all

python3 - "$OUT" <<'PY'
import json, pathlib, datetime
out = pathlib.Path(__import__("sys").argv[1])
rows = []
for p in sorted(out.glob("*.json")):
    try:
        rows.append(json.loads(p.read_text()))
    except Exception:
        pass
lines = ["# 120G+16G recheck", "", datetime.datetime.now().isoformat(timespec="seconds"), ""]
for r in rows:
    lines.append(f"- **{r.get('name')}**: {r.get('status')}  devices={r.get('devices')} ts={r.get('ts')} nvidia={r.get('nvidia')} bench={r.get('bench') or {'ds': r.get('ds'), 'glm': r.get('glm')}}")
(out / "SUMMARY.md").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
PY
log "recheck done"
