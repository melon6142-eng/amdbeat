#!/usr/bin/env python3
"""Doc A: cold TTFT on the short prompt, then decode-only tok/s at filled depths."""
from __future__ import annotations

import argparse
import json
import time
import urllib.request

PROMPT = "Write a one-sentence definition of a hash table."
UNIT = "The quick brown fox jumps over the lazy dog. "


def post_json(url: str, path: str, payload: dict, timeout: int) -> dict:
    req = urllib.request.Request(
        f"{url}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def tokenize_n(url: str, text: str) -> int:
    try:
        obj = post_json(url, "/tokenize", {"content": text}, timeout=120)
    except Exception:
        return max(1, len(text.split()))
    if isinstance(obj, dict):
        toks = obj.get("tokens") or obj.get("ids") or []
        if isinstance(toks, list):
            return len(toks)
    return max(1, len(text.split()))


def first_piece(delta: dict) -> str:
    return (
        delta.get("content")
        or delta.get("reasoning")
        or delta.get("reasoning_content")
        or ""
    )


def cold_chat(url: str, model: str, max_tokens: int) -> dict:
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
    timings = {}
    usage = {}
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
            piece = first_piece(delta)
            if piece and t_first is None:
                t_first = time.perf_counter()
            n_chars += len(piece)
            if obj.get("timings"):
                timings = obj["timings"]
            if obj.get("usage"):
                usage = obj["usage"]
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
        "label": "cold_ttft",
        "ttft_ms": round((t_first - t0) * 1000.0, 1),
        "tok_s": round(tok_s, 2),
        "predicted_n": pred_n,
        "prompt_n": timings.get("prompt_n") or usage.get("prompt_tokens"),
        "prompt_ms": timings.get("prompt_ms"),
        "predicted_ms": pred_ms,
        "predicted_per_second": timings.get("predicted_per_second"),
        "prompt_per_second": timings.get("prompt_per_second"),
        "wall_s": round(t1 - t0, 3),
        "chars": n_chars,
        "prompt": PROMPT,
    }


def build_filled_prompt(url: str, target: int) -> str:
    qn = tokenize_n(url, "\n" + PROMPT)
    un = tokenize_n(url, UNIT)
    un = max(1, un)
    need = max(0, target - qn)
    reps = need // un
    extra = need % un
    text = UNIT * reps + ("x " * extra) + "\n" + PROMPT
    return text


def depth_completion(url: str, model: str, filled: int, max_tokens: int) -> dict:
    prompt = build_filled_prompt(url, filled)
    payload = {
        "model": model,
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": 0,
        "seed": 42,
        "stream": False,
    }
    t0 = time.perf_counter()
    obj = post_json(url, "/v1/completions", payload, timeout=1800)
    wall = time.perf_counter() - t0
    timings = obj.get("timings") or {}
    usage = obj.get("usage") or {}
    pred_n = timings.get("predicted_n") or usage.get("completion_tokens") or 0
    pred_ms = timings.get("predicted_ms")
    if pred_ms and pred_n:
        tok_s = (pred_n / pred_ms) * 1000.0
    else:
        tok_s = timings.get("predicted_per_second") or 0.0
    return {
        "label": f"depth_{filled}",
        "filled_target": filled,
        "tok_s": round(float(tok_s), 2),
        "predicted_n": pred_n,
        "prompt_n": timings.get("prompt_n") or usage.get("prompt_tokens"),
        "prompt_ms": timings.get("prompt_ms"),
        "predicted_ms": pred_ms,
        "predicted_per_second": timings.get("predicted_per_second"),
        "prompt_per_second": timings.get("prompt_per_second"),
        "wall_s": round(wall, 3),
        "note": "decode=predicted_*; fill/prefill=prompt_* excluded",
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--model", required=True)
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--depths", default="32768,65536")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    rec: dict = {"model": args.model, "prompt": PROMPT}
    rec["cold"] = cold_chat(args.url, args.model, args.max_tokens)
    print(json.dumps(rec["cold"]))
    depths = []
    rec["depths"] = {}
    for part in args.depths.split(","):
        part = part.strip()
        if not part:
            continue
        n = int(part)
        try:
            d = depth_completion(args.url, args.model, n, args.max_tokens)
            rec["depths"][str(n)] = d
            print(json.dumps(d))
        except Exception as e:
            rec["depths"][str(n)] = {"error": str(e)[-240:]}
            print(json.dumps(rec["depths"][str(n)]))
        depths.append(n)
    rec["depth_list"] = depths
    with open(args.out, "w") as f:
        json.dump(rec, f, indent=2)


if __name__ == "__main__":
    main()
