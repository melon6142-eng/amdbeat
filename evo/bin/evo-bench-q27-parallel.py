#!/usr/bin/env python3
"""One llama-server instance, N concurrent real requests. Measures goodput, not llama-bench."""
from __future__ import annotations

import json
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/q27-parallel.json"
CONC = [int(x) for x in (sys.argv[3].split(",") if len(sys.argv) > 3 else "1,3,6")]
N_IN = int(sys.argv[4] if len(sys.argv) > 4 else "8192")
N_OUT = int(sys.argv[5] if len(sys.argv) > 5 else "512")


def http(path, obj=None, timeout=3600):
    req = urllib.request.Request(
        BASE + path,
        data=None if obj is None else json.dumps(obj).encode(),
        headers={"Content-Type": "application/json"},
        method="GET" if obj is None else "POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def tokenize(text: str) -> list:
    data = http("/tokenize", {"content": text})
    toks = data.get("tokens") or data.get("ids") or []
    return toks if isinstance(toks, list) else []


def make_prompt(n_target: int, salt: int) -> tuple[str, int]:
    unit = f"Item {salt:04d} laboratory checklist 0123456789 is ready. "
    ids = tokenize(unit)
    if not ids:
        raise SystemExit("tokenize failed")
    need = max(1, (n_target + len(ids) - 1) // len(ids))
    text = unit * need + "\nReply with one short sentence."
    return text, len(tokenize(text))


def one_request(prompt: str, n_predict: int) -> dict:
    t0 = time.time()
    data = http(
        "/completion",
        {
            "prompt": prompt,
            "n_predict": n_predict,
            "temperature": 0,
            "cache_prompt": False,
            "repeat_penalty": 1.0,
            "ignore_eos": True,
        },
        timeout=3600,
    )
    wall = time.time() - t0
    t = data.get("timings") or {}
    content = data.get("content") or ""
    pred_n = t.get("predicted_n") or 0
    pred_ms = t.get("predicted_ms") or 0
    return {
        "wall_s": round(wall, 3),
        "prompt_n": t.get("prompt_n"),
        "prompt_ms": t.get("prompt_ms"),
        "prompt_per_second": t.get("prompt_per_second"),
        "predicted_n": pred_n,
        "predicted_ms": pred_ms,
        "predicted_per_second": t.get("predicted_per_second"),
        "empty": not bool(content.strip()),
        "ttft_proxy_s": round((t.get("prompt_ms") or 0) / 1000.0, 3),
        "inter_token_ms": (pred_ms / pred_n) if pred_n else None,
    }


def run_conc(n: int, prompts: list[str]) -> dict:
    t0 = time.time()
    rows = []
    with ThreadPoolExecutor(max_workers=n) as ex:
        futs = [ex.submit(one_request, prompts[i], N_OUT) for i in range(n)]
        for fut in as_completed(futs):
            rows.append(fut.result())
    wall = time.time() - t0
    ok = [r for r in rows if not r.get("empty") and r.get("predicted_n")]
    total_out = sum(r.get("predicted_n") or 0 for r in ok)
    return {
        "n": n,
        "wall_s": round(wall, 3),
        "ok": len(ok),
        "fail": n - len(ok),
        "total_out_tokens": total_out,
        "goodput_tok_s": round(total_out / wall, 3) if wall else 0,
        "ttft_s": [r.get("ttft_proxy_s") for r in rows],
        "gen_tok_s": [r.get("predicted_per_second") for r in rows],
        "rows": rows,
    }


def main() -> None:
    health = http("/health")
    models = http("/v1/models")
    print("HEALTH", health, flush=True)
    print("WARMUP", one_request("OK. ", 8), flush=True)
    blocks = []
    for n in CONC:
        prompts = []
        for i in range(n):
            text, got = make_prompt(N_IN, 1000 + n * 10 + i)
            print(f"BUILD conc={n} i={i} tokens={got}", flush=True)
            prompts.append(text)
        rec = run_conc(n, prompts)
        blocks.append(rec)
        print("RUN", json.dumps({k: rec[k] for k in rec if k != "rows"}, ensure_ascii=False), flush=True)
    out = {
        "when": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "base": BASE,
        "n_in": N_IN,
        "n_out": N_OUT,
        "health": health,
        "model": (models.get("data") or [None])[0],
        "blocks": blocks,
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print("WROTE", OUT, flush=True)


if __name__ == "__main__":
    main()
