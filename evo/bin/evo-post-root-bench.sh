#!/usr/bin/env bash
set -euo pipefail
LOGDIR=~/logs/bench-glm53-s/post-root-20260924
mkdir -p "$LOGDIR"
MODEL=$MODELS_DIR/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf
PORT=8090
HOSTREG_BIN=~/src/unsloth-llama-hostreg/build-hip-hostreg/bin/llama-server
HOSTREG_LIB=~/src/unsloth-llama-hostreg/build-hip-hostreg/bin
ROCM_BIN=~/opt/unsloth-llama-b10698-mix-rocm-gfx1151/llama-server
ROCM_LIB=~/opt/unsloth-llama-b10698-mix-rocm-gfx1151
VK_BIN=~/opt/unsloth-llama-b10698-mix-vulkan/llama-server
VK_LIB=~/opt/unsloth-llama-b10698-mix-vulkan
MASTER=$LOGDIR/master.log
exec > >(tee -a "$MASTER") 2>&1

python3 - << 'PY'
open("/tmp/glm-pf8k-content.txt","w").write("One word answer: done.\n"+" ".join(f"id{i:05d}" for i in range(7500)))
print("pf8k content ready")
PY

kill_servers() { pkill -9 -f "llama-server" 2>/dev/null || true; sleep 3; }

wait_ready() {
  local log=$1
  for i in $(seq 1 120); do
    if curl -sS -m 2 "http://127.0.0.1:${PORT}/health" 2>/dev/null | grep -q ok; then
      echo "READY after ${i}*3s"; return 0
    fi
    if ! pgrep -f "llama-server" >/dev/null; then
      echo "SERVER_DIED"; tr '\0' '\n' < "$log" | tail -50; return 1
    fi
    sleep 3
  done
  echo "TIMEOUT"; tr '\0' '\n' < "$log" | tail -50; return 1
}

bench_all() {
  local tag=$1
  python3 - "$PORT" "$LOGDIR" "$tag" << 'PY'
import json,sys,urllib.request,time
port,logdir,tag=sys.argv[1:4]
base=f"http://127.0.0.1:{port}"
def post(path,body,timeout=3600):
    req=urllib.request.Request(base+path,data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=timeout) as r:
        return json.loads(r.read().decode())
def run(name, messages, max_tokens):
    t0=time.time()
    try:
        d=post("/v1/chat/completions",{"model":"m","messages":messages,"max_tokens":max_tokens,"temperature":0})
    except Exception as e:
        rec={"tag":tag,"name":name,"error":str(e)}
        open(f"{logdir}/{tag}-{name}.json","w").write(json.dumps(rec,indent=2))
        print(f"{tag}/{name} ERROR {e}")
        return
    tim=d.get("timings") or {}
    rec={"tag":tag,"name":name,"wall_s":round(time.time()-t0,3),"timings":tim,"usage":d.get("usage")}
    open(f"{logdir}/{tag}-{name}.json","w").write(json.dumps(rec,indent=2))
    print(f"{tag}/{name} decode={tim.get('predicted_per_second')} prefill={tim.get('prompt_per_second')} pn={tim.get('prompt_n')} pred={tim.get('predicted_n')}")
run("short",[{"role":"user","content":"Reply with exactly: pong"}],64)
run("code",[{"role":"user","content":"Write a Python function fib(n) with memoization. Code only."}],128)
run("pf8k",[{"role":"user","content":open("/tmp/glm-pf8k-content.txt").read()}],8)
PY
}

run_cfg() {
  local tag=$1; shift
  echo "======== START $tag ========"
  kill_servers
  local log=$LOGDIR/serve-$tag.log
  nohup env "$@" > "$log" 2>&1 &
  echo "PID=$!"
  if wait_ready "$log"; then
    tr '\0' '\n' < "$log" | grep -iE "imported|mlock|listening|OOM|fail|DeviceLost|cudaMalloc|offload|layer" | head -40 | tee "$LOGDIR/load-$tag.txt" || true
    local pid=$(pgrep -n -f llama-server || true)
    if [[ -n "$pid" ]]; then grep -E "VmLck|VmRSS" /proc/$pid/status | tee -a "$LOGDIR/load-$tag.txt" || true; fi
    bench_all "$tag"
  else
    echo "$tag FAILED" | tee "$LOGDIR/FAIL-$tag.txt"
    tr '\0' '\n' < "$log" | grep -iE "OOM|fail|error|DeviceLost|malloc|abort" | head -40 | tee -a "$LOGDIR/FAIL-$tag.txt" || true
  fi
  kill_servers
}

# (a) hostreg + mmap+mlock
run_cfg a-hostreg-mlock \
  LD_LIBRARY_PATH="$HOSTREG_LIB:/opt/rocm-7.2.1/lib" GGML_CUDA_REGISTER_HOST=1 \
  "$HOSTREG_BIN" -m "$MODEL" --host 127.0.0.1 --port $PORT --alias m \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap+mlock --ctx-size 36864 --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui

# (b) Unsloth ROCm plain full
run_cfg b-rocm-full \
  LD_LIBRARY_PATH="$ROCM_LIB:/opt/rocm-7.2.1/lib" \
  "$ROCM_BIN" -m "$MODEL" --host 127.0.0.1 --port $PORT --alias m \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap --ctx-size 36864 --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui

# (c) Vulkan full
env LD_LIBRARY_PATH="$VK_LIB" "$VK_BIN" --list-devices 2>&1 | tee "$LOGDIR/vk-devices.txt" | head -20 || true
run_cfg c-vulkan-full \
  LD_LIBRARY_PATH="$VK_LIB" \
  "$VK_BIN" -m "$MODEL" --host 127.0.0.1 --port $PORT --alias m \
  --device Vulkan0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap --ctx-size 36864 --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui

# (d) UM + mlock
run_cfg d-um-mlock \
  LD_LIBRARY_PATH="$ROCM_LIB:/opt/rocm-7.2.1/lib" GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 \
  "$ROCM_BIN" -m "$MODEL" --host 127.0.0.1 --port $PORT --alias m \
  --device ROCm0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap+mlock --ctx-size 36864 --batch-size 512 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
  --reasoning off --jinja --no-webui

echo ALL_BENCH_DONE
python3 - << 'PY'
import json,glob,os
logdir=os.path.expanduser("~/logs/bench-glm53-s/post-root-20260924")
print("\n=== SUMMARY ===")
for f in sorted(glob.glob(logdir+"/*-*.json")):
  d=json.load(open(f))
  t=d.get("timings") or {}
  if d.get("error"):
    print(f"{d.get('tag')}/{d.get('name')}: ERR {d['error'][:100]}")
  else:
    print(f"{d.get('tag')}/{d.get('name')}: decode={t.get('predicted_per_second')} prefill={t.get('prompt_per_second')} pn={t.get('prompt_n')}")
PY
