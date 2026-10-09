import json, sys, time, urllib.request, statistics, os, uuid
port, model, tag = sys.argv[1], sys.argv[2], sys.argv[3]
runs = int(sys.argv[4]) if len(sys.argv) > 4 else 3
temp = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
src = open(os.path.expanduser("~/src/strata-0140/serve/server.py")).read()
SHORT = ("You are a senior Python engineer. Below is a small module. Review it and then write an improved version "
 "that adds an LRU cache with TTL expiry, thread safety, type hints, and unit tests using pytest. Explain briefly.\n\n```python\n"
 + src[20000:21600] + "\n```\n")
LONG = ("Here is a large part of a Python HTTP server implementation. Read it carefully, then list the 5 most serious "
 "bugs or risks you can find with line references, and propose a refactor plan for the request handling code.\n\n```python\n"
 + src[30000:61000] + "\n```\n")
def one(prompt, max_tokens):
    prompt = f"[session {uuid.uuid4().hex}]\n" + prompt
    body = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": max_tokens,
            "temperature": temp, "stream": True, "stream_options": {"include_usage": True}}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time(); tf = None; n = 0; usage = None
    with urllib.request.urlopen(req, timeout=1800) as r:
        for line in r:
            line = line.decode().strip()
            if not line.startswith("data:"): continue
            d = line[5:].strip()
            if d == "[DONE]": break
            j = json.loads(d)
            if j.get("usage"): usage = j["usage"]
            for c in j.get("choices", []):
                de = c.get("delta", {})
                if de.get("content") or de.get("reasoning_content") or de.get("reasoning"):
                    if tf is None: tf = time.time()
                    n += 1
    t1 = time.time()
    pt = usage.get("prompt_tokens") if usage else None
    ct = usage.get("completion_tokens") if usage else n
    ttft = tf - t0 if tf else t1 - t0
    dec = (ct - 1) / (t1 - tf) if ct and tf and t1 > tf else 0
    return dict(pt=pt, ct=ct, chunks=n, ttft=round(ttft, 2), prefill=round(pt / ttft, 1) if pt and ttft else None,
                decode=round(dec, 1), total=round(t1 - t0, 1))
one("hi", 8)
for name, p, mt in (("short", SHORT, 1024), ("8k", LONG, 1024)):
    res = []
    for i in range(runs):
        x = one(p, mt); res.append(x); print(tag, f"t{temp}", name, i, json.dumps(x), flush=True)
    print(tag, f"t{temp}", name, "MEDIAN", json.dumps({k: statistics.median([r[k] for r in res if r[k] is not None]) for k in ("pt","ct","ttft","prefill","decode")}), flush=True)
