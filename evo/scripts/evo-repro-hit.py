#!/usr/bin/env python3
"""Stream one chat turn. Record wall TTFT and decode tok/s."""
from __future__ import annotations

import argparse
import json
import time
import urllib.request

PROMPT = "Write a one-sentence definition of a hash table."


def hit(url: str, model: str, max_tokens: int) -> dict:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": PROMPT}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "seed": 42,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    req = urllib.request.Request(
        f"{url}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.perf_counter()
    t_first = None
    usage = {}
    timings = {}
    n_chars = 0
    with urllib.request.urlopen(req, timeout=600) as resp:
        for raw in resp:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            obj = json.loads(data)
            delta = (obj.get("choices") or [{}])[0].get("delta") or {}
            piece = delta.get("content") or delta.get("reasoning") or ""
            if piece and t_first is None:
                t_first = time.perf_counter()
            n_chars += len(piece)
            if obj.get("usage"):
                usage = obj["usage"]
            if obj.get("timings"):
                timings = obj["timings"]
    t1 = time.perf_counter()
    if t_first is None:
        t_first = t1
    pred_n = timings.get("predicted_n") or usage.get("completion_tokens") or 0
    pred_ms = timings.get("predicted_ms")
    if pred_ms and pred_n:
        tok_s = (pred_n / pred_ms) * 1000.0
    elif pred_n and (t1 - t_first) > 0:
        tok_s = pred_n / (t1 - t_first)
    else:
        tok_s = 0.0
    return {
        "ttft_ms": round((t_first - t0) * 1000.0, 1),
        "tok_s": round(tok_s, 2),
        "predicted_n": pred_n,
        "prompt_n": timings.get("prompt_n") or usage.get("prompt_tokens"),
        "prompt_ms": timings.get("prompt_ms"),
        "predicted_ms": pred_ms,
        "prompt_per_second": timings.get("prompt_per_second"),
        "predicted_per_second": timings.get("predicted_per_second"),
        "wall_s": round(t1 - t0, 3),
        "chars": n_chars,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--model", required=True)
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--label", default="run")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    rec = hit(args.url, args.model, args.max_tokens)
    rec["label"] = args.label
    rec["model"] = args.model
    rec["prompt"] = PROMPT
    with open(args.out, "w") as f:
        json.dump(rec, f, indent=2)
    print(json.dumps(rec))


if __name__ == "__main__":
    main()
