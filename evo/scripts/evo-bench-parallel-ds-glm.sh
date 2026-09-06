#!/usr/bin/env bash
# Hit DeepSeek :8080 and GLM :8081 at the same time, then each alone.
set -euo pipefail
OUT="${OUT:-$HOME/logs/parallel-ds-glm.json}"
python3 - "$OUT" <<'PY'
import json, time, urllib.request, concurrent.futures, sys

out = sys.argv[1]
prompt = "In 4 short bullets, say what an eGPU PCIe hop costs during MoE decode."

def chat(port, model, n=64):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": n,
        "temperature": 0.2,
    }).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=body, headers={"Content-Type": "application/json"}, method="POST",
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode())
    t = data.get("timings") or {}
    return {
        "wall_s": round(time.time()-t0, 3),
        "prompt_per_second": t.get("prompt_per_second"),
        "predicted_per_second": t.get("predicted_per_second"),
        "predicted_n": t.get("predicted_n"),
        "text": ((data.get("choices") or [{}])[0].get("message") or {}).get("content", "")[:160],
    }

def one(name, port, model):
    try:
        return name, chat(port, model)
    except Exception as e:
        return name, {"error": str(e)}

# warmup each
for name, port, model in (("ds", 8080, "deepseek4-iq2-amd"), ("glm", 8081, "glm53-flash-aj-iq2-4080")):
    try:
        chat(port, model, n=16)
    except Exception as e:
        print(name, "warmup_fail", e)

solo = {}
for name, port, model in (("ds", 8080, "deepseek4-iq2-amd"), ("glm", 8081, "glm53-flash-aj-iq2-4080")):
    k, v = one(name, port, model)
    solo[k] = v
    print("solo", k, v)

t0 = time.time()
together = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
    futs = [
        ex.submit(one, "ds", 8080, "deepseek4-iq2-amd"),
        ex.submit(one, "glm", 8081, "glm53-flash-aj-iq2-4080"),
    ]
    for fut in concurrent.futures.as_completed(futs):
        k, v = fut.result()
        together[k] = v
        print("together", k, v)
row = {"solo": solo, "together": together, "together_wall_s": round(time.time()-t0, 3)}
json.dump(row, open(out, "w"), indent=2)
print("wrote", out)
print(json.dumps(row, indent=2))
PY
