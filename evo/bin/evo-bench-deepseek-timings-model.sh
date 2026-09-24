#!/usr/bin/env bash
# Copy of evo-bench-deepseek-timings.sh with MODEL env override (do not edit original).
set -euo pipefail
OUTDIR="${OUTDIR:-$HOME/logs/bench-ds-20260924}"
TAG="${TAG:-run}"
PORT="${PORT:-8091}"
MODEL_NAME="${MODEL_NAME:-deepseek4-iq2-amd}"
BASE="http://127.0.0.1:${PORT}"
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d_%H%M%S)
RESULT="$OUTDIR/bench-${TAG}-${STAMP}.jsonl"
SUMMARY="$OUTDIR/bench-${TAG}-${STAMP}.txt"

python3 - "$BASE" "$RESULT" "$SUMMARY" "$MODEL_NAME" <<'PY'
import json, sys, time, urllib.request
base, result_path, summary_path, model_name = sys.argv[1:5]

def post(path, body, timeout=3600):
    data = json.dumps(body).encode()
    req = urllib.request.Request(base+path, data=data, headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())

def tokenize_len(text):
    try:
        d = post("/tokenize", {"content": text, "add_special": False})
        if isinstance(d, dict) and "tokens" in d: return len(d["tokens"])
        if isinstance(d, list): return len(d)
    except Exception:
        pass
    return None

def make_filler(target_tokens):
    unit = ("The quick brown fox jumps over the lazy dog. "
            "In a small village near the river, people built a wooden bridge. "
            "Numbers: 0123456789. Code: def f(x): return x*x+1\n")
    text = (unit * ((target_tokens * 5) // max(len(unit),1) + 2))
    for _ in range(8):
        n = tokenize_len(text)
        if n is None:
            text = text[: target_tokens * 4]
            return text, None
        if abs(n - target_tokens) <= max(32, target_tokens*0.02):
            return text, n
        factor = target_tokens / max(n,1)
        text = text[: max(16, int(len(text)*factor))]
        if factor > 1:
            text = text + unit * int((factor-1)*10 + 1)
    return text, tokenize_len(text)

def one(name, messages, max_tokens, temperature=0):
    t0 = time.time()
    body = {
        "model": model_name,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "top_p": 1,
        "reasoning_effort": "none",
    }
    try:
        d = post("/v1/chat/completions", body)
    except Exception as e:
        rec = {"name": name, "error": str(e), "wall_s": time.time()-t0}
        open(result_path,"a").write(json.dumps(rec)+"\n")
        print(name, "ERROR", e)
        return rec
    # ds4 may not return llama.cpp-style timings; derive from usage when needed
    tim = d.get("timings") or {}
    usage = d.get("usage") or {}
    content = (d.get("choices") or [{}])[0].get("message",{}).get("content","")
    wall = time.time()-t0
    # if no timings, approximate from usage + wall (decode-heavy for short gens)
    if not tim and usage:
        pt = usage.get("prompt_tokens")
        ct = usage.get("completion_tokens")
        note = "no_server_timings; wall-derived approx"
        prompt_tps = predicted_tps = None
        if pt and wall > 0:
            if ct is not None and pt >= 1000 and (ct or 0) <= 64:
                prompt_tps = pt / wall
            elif ct and ct > 0 and (pt or 0) < 200:
                predicted_tps = ct / wall
        tim = {"prompt_n": pt, "predicted_n": ct, "prompt_per_second": prompt_tps, "predicted_per_second": predicted_tps, "note": note}
    rec = {
        "name": name,
        "wall_s": round(wall,3),
        "timings": tim,
        "usage": usage,
        "prompt_n": tim.get("prompt_n") or usage.get("prompt_tokens"),
        "prompt_per_second": tim.get("prompt_per_second"),
        "predicted_n": tim.get("predicted_n") or usage.get("completion_tokens"),
        "predicted_per_second": tim.get("predicted_per_second"),
        "cache_n": tim.get("cache_n"),
        "draft_n": tim.get("draft_n"),
        "draft_n_accepted": tim.get("draft_n_accepted"),
        "content_head": (content or "")[:120],
        "raw_keys": sorted(d.keys()),
    }
    open(result_path,"a").write(json.dumps(rec)+"\n")
    print(f"{name}: prefill={rec.get("prompt_per_second")} tok/s (n={rec.get("prompt_n")}, cache={rec.get("cache_n")})  decode={rec.get("predicted_per_second")} tok/s (n={rec.get("predicted_n")}) wall={rec.get("wall_s")}")
    return rec

rows = []
rows.append(one("short_chat", [{"role":"user","content":"Write one cheerful sentence about coffee."}], 64))
code_prompt = """Continue this Python function with more similar lines (temperature 0, just keep the pattern):\n\ndef add1(x): return x + 1\ndef add2(x): return x + 2\ndef add3(x): return x + 3\ndef add4(x): return x + 4\ndef add5(x): return x + 5\n"""
rows.append(one("code_rep", [{"role":"user","content": code_prompt}], 128))
fill8, n8 = make_filler(7800)
msg8 = [{"role":"user","content": fill8 + "\n\nSummarize the above in one short sentence."}]
rows.append(one("prefill_8k", msg8, 32))
msg8b = [{"role":"user","content": fill8 + "\n\nNow give a different one-word title."}]
rows.append(one("prefill_8k_cached", msg8b, 16))
fill32, n32 = make_filler(31000)
msg32 = [{"role":"user","content": fill32 + "\n\nOne-sentence summary:"}]
rows.append(one("prefill_32k", msg32, 32))
lines = ["BENCH SUMMARY", f"base={base}", f"model={model_name}", f"result={result_path}"]
for r in rows:
    lines.append(f"{r.get('name')}: prefill_tps={r.get('prompt_per_second')} decode_tps={r.get('predicted_per_second')} prompt_n={r.get('prompt_n')} cache_n={r.get('cache_n')} pred_n={r.get('predicted_n')} wall={r.get('wall_s')} err={r.get('error')}")
open(summary_path,"w").write("\n".join(lines)+"\n")
print("\n".join(lines))
PY
