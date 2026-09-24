#!/usr/bin/env bash
# A/B: baseline hostreg vs moe-fuse opt. GPU must be free.
set -euo pipefail
OUT="${OUT:-$HOME/logs/moe-fuse-bench-$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
MODEL="${MODEL:-$HOME/models/gguf/GLM-5.3-Flash-GGUF/AJ-IQ2_XXS/GLM-5.3-Flash-AJ-IQ2_XXS-00001-of-00002.gguf}"
BASE_BIN="$HOME/src/unsloth-llama-hostreg/build-hip-hostreg/bin/llama-server"
FUSE_BIN="$HOME/src/llama-iq2-opt/build-hip-opt/bin/llama-server"

if pgrep -af 'ds4-server' >/dev/null; then echo "ABORT ds4"; exit 2; fi

run_one() {
  local name=$1 bin=$2 port=$3
  local d="$OUT/$name"; mkdir -p "$d"
  export LD_LIBRARY_PATH="$(dirname "$bin"):/opt/rocm-7.2.1/lib"
  export GGML_CUDA_REGISTER_HOST=1
  unset GGML_CUDA_ENABLE_UNIFIED_MEMORY || true
  "$bin" -m "$MODEL" --host 127.0.0.1 --port "$port" --alias "glm-$name" \
    --device ROCm0 --gpu-layers all --flash-attn on --fit off \
    --load-mode mmap+mlock --ctx-size 16384 --batch-size 512 --ubatch-size 256 \
    --cache-type-k q8_0 --cache-type-v q8_0 --threads 32 --parallel 1 \
    --reasoning off --jinja --no-webui >"$d/server.log" 2>&1 &
  echo $! >"$d/server.pid"
  local spid=$!
  for i in $(seq 1 150); do curl -sf http://127.0.0.1:$port/health >/dev/null && break; sleep 2; done
  curl -sf http://127.0.0.1:$port/completion -H 'Content-Type: application/json' \
    -d '{"prompt":"Write a one-sentence greeting.","n_predict":128,"temperature":0}' >"$d/decode-chat.json"
  curl -sf http://127.0.0.1:$port/completion -H 'Content-Type: application/json' \
    -d '{"prompt":"```python\ndef fib(n):\n","n_predict":128,"temperature":0}' >"$d/decode-code.json"
  python3 - <<PY
import json,urllib.request
prompt=("The quick brown fox jumps over the lazy dog. ")*500
body=json.dumps({"prompt":prompt,"n_predict":16,"temperature":0}).encode()
req=urllib.request.Request("http://127.0.0.1:$port/completion",data=body,headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req,timeout=600) as r:
    open("$d/prefill-8k.json","wb").write(r.read())
PY
  python3 - <<PY
import json
from pathlib import Path
d=Path("$d")
for f in ["decode-chat","decode-code","prefill-8k"]:
  j=json.load(open(d/f"{f}.json")); t=j["timings"]; c=(j.get("content") or "")[:70].replace("\n"," ")
  print(f"$name {f}: pred={t['predicted_per_second']:.2f} prompt={t['prompt_per_second']:.2f} n={t['prompt_n']} | {c!r}")
PY
  kill $spid 2>/dev/null || true; wait $spid 2>/dev/null || true; sleep 2
}

run_one baseline "$BASE_BIN" 8093
run_one fused "$FUSE_BIN" 8092

python3 - <<PY
import json
from pathlib import Path
out=Path("$OUT")
def content(name,f):
  return json.load(open(out/name/f"{f}.json")).get("content","")
def tps(name,f):
  return json.load(open(out/name/f"{f}.json"))["timings"]["predicted_per_second"]
def ptps(name,f):
  return json.load(open(out/name/f"{f}.json"))["timings"]["prompt_per_second"]

for f in ["decode-chat","decode-code"]:
  b,o=content("baseline",f),content("fused",f)
  # token-level agreement on shared prefix length
  n=min(len(b),len(o),200)
  agree=sum(1 for i in range(n) if b[i]==o[i]) / max(n,1)
  print(f"correctness {f}: exact={b==o} prefix_char_agree={agree:.3f} lens={len(b)}/{len(o)}")
  if b!=o and n>0:
    for i,(x,y) in enumerate(zip(b,o)):
      if x!=y:
        print(f"  first diff @{i}: ...{b[max(0,i-15):i+25]!r} vs ...{o[max(0,i-15):i+25]!r}")
        break

print("SPEED baseline chat/code/prefill8k:", f"{tps('baseline','decode-chat'):.2f}/{tps('baseline','decode-code'):.2f}/{ptps('baseline','prefill-8k'):.2f}")
print("SPEED fused    chat/code/prefill8k:", f"{tps('fused','decode-chat'):.2f}/{tps('fused','decode-code'):.2f}/{ptps('fused','prefill-8k'):.2f}")
bc,fc=tps("baseline","decode-chat"),tps("fused","decode-chat")
bo,fo=tps("baseline","decode-code"),tps("fused","decode-code")
ok_text = "?" not in content("fused","decode-chat") and len(content("fused","decode-chat"))>10
faster = fc>bc*1.03 and fo>bo*1.03
winner = "fused" if (ok_text and faster) else "baseline"
open(out/"winner.txt","w").write(winner)
print("winner", winner, "ok_text", ok_text, "faster_3pct", faster)
print("OUT", out)
PY
