#!/usr/bin/env python3
"""Hit a running llama-server with Yukon-shaped paired prompts. Timing only."""
from __future__ import annotations

import argparse
import json
import time
import urllib.request

PARA = (
    "Alpine meadow botany is a study of short growing seasons, thin soils, "
    "and plants that store energy in roots through a long winter. Leaves stay "
    "small, flowers open fast after snowmelt, and seed set must finish before "
    "the first frost returns. Survey plots record species, cover, and height "
    "along a fixed transect so later visits can be compared without guessing."
)
PROMPT = (" ".join([PARA] * 18)).strip()


def post(url: str, payload: dict) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.loads(r.read())


def one(url: str, model: str, max_tokens: int) -> dict:
    t0 = time.time()
    r = post(
        f"{url}/v1/chat/completions",
        {
            "model": model,
            "messages": [{"role": "user", "content": PROMPT}],
            "max_tokens": max_tokens,
            "temperature": 0,
            "seed": 42,
        },
    )
    wall = time.time() - t0
    t = r.get("timings") or {}
    usage = r.get("usage") or {}
    prompt_n = t.get("prompt_n") or usage.get("prompt_tokens") or 0
    pred_n = t.get("predicted_n") or usage.get("completion_tokens") or 0
    prompt_ms = t.get("prompt_ms") or 0
    pred_ms = t.get("predicted_ms") or 0
    if prompt_n <= 0 or pred_n <= 0:
        raise SystemExit(f"bad timings: {t} usage={usage}")
    rec = {
        "prompt_n": prompt_n,
        "predicted_n": pred_n,
        "prompt_ms": prompt_ms,
        "predicted_ms": pred_ms,
        "prompt_per_second": t.get("prompt_per_second"),
        "predicted_per_second": t.get("predicted_per_second"),
        "prefill_s_per_tok": (prompt_ms / 1000.0) / prompt_n,
        "decode_s_per_tok": (pred_ms / 1000.0) / pred_n,
        "wall_s": round(wall, 3),
        "draft_n": t.get("draft_n"),
        "draft_n_accepted": t.get("draft_n_accepted"),
    }
    print(
        f"  pp={rec['prompt_n']} {1/rec['prefill_s_per_tok']:.1f} t/s  "
        f"tg={rec['predicted_n']} {1/rec['decode_s_per_tok']:.1f} t/s  "
        f"wall={rec['wall_s']:.1f}s"
    )
    return rec


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--model", required=True)
    ap.add_argument("--pairs", type=int, default=2)
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    pairs = [one(args.url, args.model, args.max_tokens) for _ in range(args.pairs)]
    out = {
        "url": args.url,
        "model": args.model,
        "pairs": pairs,
        "prompt_chars": len(PROMPT),
    }
    with open(args.out, "w") as f:
        json.dump(out, f, indent=2)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
