#!/usr/bin/env python3
"""Real-input DeepSeek serve bench: exact token lengths, no prompt cache."""
from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"
OUT = sys.argv[2] if len(sys.argv) > 2 else "$HOME/hybrid-results/ds-q3-amd-realctx.json"
LENGTHS = [int(x) for x in (sys.argv[3].split(",") if len(sys.argv) > 3 else "512,8192")]
N_PRED = int(sys.argv[4] if len(sys.argv) > 4 else "64")


def http(path, obj=None, timeout=18000):
    req = urllib.request.Request(
        BASE + path,
        data=None if obj is None else json.dumps(obj).encode(),
        headers={"Content-Type": "application/json"},
        method="GET" if obj is None else "POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def nvidia():
    try:
        return subprocess.check_output(
            ["nvidia-smi", "--query-gpu=memory.used,utilization.gpu,power.draw", "--format=csv,noheader,nounits"],
            text=True,
        ).strip()
    except Exception as e:
        return str(e)


def tokenize(text: str) -> list:
    data = http("/tokenize", {"content": text})
    toks = data.get("tokens") or data.get("ids") or []
    return toks if isinstance(toks, list) else []


def make_prompt(n_target: int) -> tuple[str, int]:
    unit = "The laboratory checklist item number 0123456789 is ready. "
    ids = tokenize(unit)
    if not ids:
        raise SystemExit("tokenize failed")
    need = max(1, (n_target + len(ids) - 1) // len(ids))
    text = unit * need
    ids = tokenize(text)
    while len(ids) > n_target + 48 and need > 1:
        need -= 1
        text = unit * need
        ids = tokenize(text)
    return text + "\nSummarize in one short sentence.", len(tokenize(text + "\nSummarize in one short sentence."))


def completion(prompt: str, n_predict: int) -> dict:
    t0 = time.time()
    data = http(
        "/completion",
        {
            "prompt": prompt,
            "n_predict": n_predict,
            "temperature": 0,
            "cache_prompt": False,
            "repeat_penalty": 1.0,
        },
        timeout=18000,
    )
    t = data.get("timings") or {}
    content = data.get("content") or ""
    return {
        "wall_s": round(time.time() - t0, 3),
        "prompt_n": t.get("prompt_n"),
        "prompt_ms": t.get("prompt_ms"),
        "prompt_per_second": t.get("prompt_per_second"),
        "predicted_n": t.get("predicted_n"),
        "predicted_ms": t.get("predicted_ms"),
        "predicted_per_second": t.get("predicted_per_second"),
        "empty": not bool(content.strip()),
        "content_head": content[:160],
        "stop": data.get("stop"),
        "nvidia": nvidia(),
    }


def main() -> None:
    health = http("/health")
    models = http("/v1/models")
    print("HEALTH", health, flush=True)
    print("NVIDIA", nvidia(), flush=True)
    rows = []
    print("WARMUP", completion("OK. ", 8), flush=True)
    for n in LENGTHS:
        text, got = make_prompt(n)
        print(f"BUILD n={n} got={got}", flush=True)
        rec = completion(text, N_PRED)
        rec["label"] = f"in{n}"
        rec["built_tokens"] = got
        rows.append(rec)
        print("RUN", json.dumps(rec, ensure_ascii=False), flush=True)
        if rec.get("empty") or not rec.get("predicted_n"):
            print("STOP empty/failed generation", flush=True)
            break
    out = {
        "when": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "base": BASE,
        "n_pred": N_PRED,
        "health": health,
        "model": (models.get("data") or [None])[0],
        "rows": rows,
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print("WROTE", OUT, flush=True)


if __name__ == "__main__":
    main()
