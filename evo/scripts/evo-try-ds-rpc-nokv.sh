#!/usr/bin/env bash
# One-shot: DeepSeek 3-way with KV pinned on EVO (--no-kv-offload).
# Tests whether the overnight RPC hang was KV-clear on Metal.
set -euo pipefail
MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${DS_GGUF:-$HOME/models/gguf/DeepSeek-V4-Flash-IQ2XXS/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf}"
LOG="${HOME}/logs/try-ds-rpc-nokv.log"
OUT="${HOME}/logs/try-ds-rpc-nokv.json"
PORT="${PORT:-8090}"
TS="${TS:-72,16,12}"
RPC="${RPC:-<host>:50052}"
LOAD_SECS="${LOAD_SECS:-720}"
mkdir -p "$(dirname "$LOG")"
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GGML_RPC_NO_RDMA=1
unset VK_ICD_FILENAMES

nc -z -w 3 <host> 50052 || { echo "rpc down"; exit 1; }
fuser -k "${PORT}/tcp" 2>/dev/null || true
pkill -x llama-server || true
sleep 2
: >"$LOG"

nohup "$BIN" -m "$MODEL" \
  --host 127.0.0.1 --port "$PORT" --alias ds-rpc-nokv \
  --rpc "$RPC" \
  --device Vulkan1,Vulkan0,RPC0 --split-mode layer --tensor-split "$TS" \
  --gpu-layers all --flash-attn on --fit off \
  --no-host --load-mode mmap --no-kv-offload \
  --ctx-size 4096 --batch-size 512 --ubatch-size 128 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --threads 32 --threads-batch 32 \
  --jinja --no-webui --metrics --parallel 1 \
  >"$LOG" 2>&1 &
echo "pid=$! log=$LOG"

python3 - "$PORT" "$LOG" "$OUT" "$LOAD_SECS" "$TS" <<'PY'
import json, os, time, urllib.request, subprocess, sys
port, log, out, load_secs, ts = sys.argv[1:]
load_secs = int(load_secs)
t0 = time.time()
status = "timeout"
while time.time() - t0 < load_secs:
    try:
        text = open(log, errors="replace").read()
    except FileNotFoundError:
        text = ""
    if any(s in text.lower() for s in ("out of memory", "failed to allocate", "invalid data ptr", "ggml_assert")):
        status = "oom_or_crash"
        break
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as r:
            body = r.read().decode()
        if "ok" in body:
            status = "ok"
            break
    except Exception:
        pass
    time.sleep(4)
else:
    if "threadpool" in open(log, errors="replace").read():
        status = "hang_after_threadpool"

row = {"status": status, "ts": ts, "no_kv_offload": True, "elapsed_s": round(time.time()-t0, 1)}
if status == "ok":
    body = json.dumps({
        "model": "ds-rpc-nokv",
        "messages": [{"role": "user", "content": "Reply with exactly: rpc-nokv-ok"}],
        "max_tokens": 32,
        "temperature": 0,
    }).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=body, headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        t1 = time.time()
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode())
        row["bench"] = data.get("timings") or {}
        row["wall_s"] = round(time.time()-t1, 2)
        row["text"] = ((data.get("choices") or [{}])[0].get("message") or {}).get("content", "")[:200]
    except Exception as e:
        row["status"] = "bench_fail"
        row["error"] = str(e)
try:
    row["log_tail"] = open(log, errors="replace").read()[-2500:]
except Exception:
    pass
json.dump(row, open(out, "w"), indent=2)
print(json.dumps({k: row[k] for k in row if k != "log_tail"}, indent=2))
if row.get("log_tail"):
    print("===== log tail =====")
    print(row["log_tail"][-1200:])
PY

fuser -k "${PORT}/tcp" 2>/dev/null || true
pkill -x llama-server || true
sleep 1
echo "wrote $OUT"
