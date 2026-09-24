#!/usr/bin/env bash
# Fixed methodology bench for GLM-5.3 on EVO via llama-server timings.
set -euo pipefail
OUTDIR="${OUTDIR:-$HOME/logs/bench-glm53-s/fast-20260924}"
TAG="${TAG:-run}"
PORT="${PORT:-8091}"
BASE="http://127.0.0.1:${PORT}"
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d_%H%M%S)
RESULT="$OUTDIR/bench-${TAG}-${STAMP}.jsonl"
SUMMARY="$OUTDIR/bench-${TAG}-${STAMP}.txt"

python3 - "$BASE" "$RESULT" "$SUMMARY" <<'PY'
import json, sys, time, urllib.request, random, string
base, result_path, summary_path = sys.argv[1:4]

def post(path, body, timeout=3600):
    data = json.dumps(body).encode()
    req = urllib.request.Request(base+path, data=data, headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())

def tokenize_len(text):
    # approximate via /tokenize if present
    try:
        d = post("/tokenize", {"content": text, "add_special": False})
        if isinstance(d, dict) and "tokens" in d:
            return len(d["tokens"])
        if isinstance(d, list):
            return len(d)
    except Exception:
        pass
    return None

def make_filler(target_tokens):
    # ~1 token ≈ 4 chars for English-ish; refine with tokenize
    unit = ("The quick brown fox jumps over the lazy dog. "
            "In a small village near the river, people built a wooden bridge. "
            "Numbers: 0123456789. Code: def f(x): return x*x+1\n")
    text = (unit * ((target_tokens * 5) // max(len(unit),1) + 2))
    # trim using tokenizer
    for _ in range(8):
        n = tokenize_len(text)
        if n is None:
            # fallback char estimate
            text = text[: target_tokens * 4]
            return text, None
        if abs(n - target_tokens) <= max(32, target_tokens*0.02):
            return text, n
        # scale
        factor = target_tokens / max(n,1)
        text = text[: max(16, int(len(text)*factor))]
        if factor > 1:
            text = text + unit * int((factor-1)*10 + 1)
    return text, tokenize_len(text)

def one(name, messages, max_tokens, temperature=0):
    t0 = time.time()
    body = {
        "model": "deepseek4-iq2-amd",
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "top_p": 1,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    try:
        d = post("/v1/chat/completions", body)
    except Exception as e:
        rec = {"name": name, "error": str(e), "wall_s": time.time()-t0}
        open(result_path,"a").write(json.dumps(rec)+"\n")
        print(name, "ERROR", e)
        return rec
    tim = d.get("timings") or {}
    content = (d.get("choices") or [{}])[0].get("message",{}).get("content","")
    rec = {
        "name": name,
        "wall_s": round(time.time()-t0,3),
        "timings": tim,
        "prompt_n": tim.get("prompt_n"),
        "prompt_per_second": tim.get("prompt_per_second"),
        "predicted_n": tim.get("predicted_n"),
        "predicted_per_second": tim.get("predicted_per_second"),
        "cache_n": tim.get("cache_n"),
        "draft_n": tim.get("draft_n"),
        "draft_n_accepted": tim.get("draft_n_accepted"),
        "content_head": (content or "")[:120],
    }
    open(result_path,"a").write(json.dumps(rec)+"\n")
    print(f"{name}: prefill={rec['prompt_per_second']} tok/s (n={rec['prompt_n']}, cache={rec['cache_n']})  decode={rec['predicted_per_second']} tok/s (n={rec['predicted_n']})")
    return rec

rows = []
# 1) short chat decode
rows.append(one("short_chat", [{"role":"user","content":"Write one cheerful sentence about coffee."}], 64))

# 2) code/repetitive prompt decode
code_prompt = """Continue this Python function with more similar lines (temperature 0, just keep the pattern):\n\ndef add1(x): return x + 1\ndef add2(x): return x + 2\ndef add3(x): return x + 3\ndef add4(x): return x + 4\ndef add5(x): return x + 5\n"""
rows.append(one("code_rep", [{"role":"user","content": code_prompt}], 128))

# 3) ~8k prefill
fill8, n8 = make_filler(7800)
msg8 = [{"role":"user","content": fill8 + "\n\nSummarize the above in one short sentence."}]
rows.append(one("prefill_8k", msg8, 32))

# 4) 2nd turn same 8k prefix (cache reuse)
msg8b = [{"role":"user","content": fill8 + "\n\nNow give a different one-word title."}]
rows.append(one("prefill_8k_cached", msg8b, 16))

# 5) ~32k prefill if ctx allows
fill32, n32 = make_filler(31000)
msg32 = [{"role":"user","content": fill32 + "\n\nOne-sentence summary:"}]
rows.append(one("prefill_32k", msg32, 32))

lines = ["BENCH SUMMARY", f"base={base}", f"result={result_path}"]
for r in rows:
    lines.append(f"{r.get('name')}: prefill_tps={r.get('prompt_per_second')} decode_tps={r.get('predicted_per_second')} prompt_n={r.get('prompt_n')} cache_n={r.get('cache_n')} pred_n={r.get('predicted_n')} err={r.get('error')}")
open(summary_path,"w").write("\n".join(lines)+"\n")
print("\n".join(lines))
PY
