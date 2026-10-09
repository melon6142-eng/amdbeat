import json, sys, time, urllib.request, os, uuid, glob
port, model, target_chars = sys.argv[1], sys.argv[2], int(sys.argv[3])
buf = ""
for f in sorted(glob.glob(os.path.expanduser("~/src/strata-0140/serve/*.py")) + glob.glob(os.path.expanduser("~/src/strata-0140/tools/*.py"))):
    buf += f"\n# ===== {os.path.basename(f)} =====\n" + open(f, errors="ignore").read()
    if len(buf) >= target_chars: break
buf = buf[:target_chars]
prompt = f"[session {uuid.uuid4().hex}]\nBelow is a large Python codebase. Summarize the architecture in 5 bullet points and name the file that defines the HTTP server.\n\n```python\n{buf}\n```\n"
body = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": 256, "temperature": 0,
        "stream": True, "stream_options": {"include_usage": True}}
req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
t0 = time.time(); tf = None; usage = None; n = 0; text = ""
with urllib.request.urlopen(req, timeout=3600) as r:
    for line in r:
        line = line.decode().strip()
        if not line.startswith("data:"): continue
        d = line[5:].strip()
        if d == "[DONE]": break
        j = json.loads(d)
        if j.get("usage"): usage = j["usage"]
        for c in j.get("choices", []):
            de = c.get("delta", {})
            t = de.get("content") or de.get("reasoning_content") or ""
            if t:
                if tf is None: tf = time.time()
                n += 1; text += t
t1 = time.time()
pt = usage["prompt_tokens"]; ct = usage["completion_tokens"]
print(json.dumps(dict(pt=pt, ct=ct, ttft=round(tf - t0, 1), prefill=round(pt / (tf - t0), 1), decode=round((ct - 1) / (t1 - tf), 1), total=round(t1 - t0, 1))))
print("SAMPLE:", text[:300].replace("\n", " "))
