#!/usr/bin/env python3
"""One-shot 4080 OCuLink verify: short + mid-ctx prefill/decode on :8081."""
from __future__ import annotations

import json
import subprocess
import time
import urllib.request

BASE = "http://127.0.0.1:8081"
OUT = "$HOME/hybrid-results/4080-oculink-2026-09-12.json"


def http(path: str, obj=None, timeout: float = 300):
    req = urllib.request.Request(
        BASE + path,
        data=None if obj is None else json.dumps(obj).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="GET" if obj is None else "POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def nvidia() -> str:
    return subprocess.check_output(
        [
            "nvidia-smi",
            "--query-gpu=name,memory.used,memory.total,utilization.gpu,"
            "pcie.link.gen.current,pcie.link.width.current,temperature.gpu,power.draw",
            "--format=csv,noheader,nounits",
        ],
        text=True,
    ).strip()


def tokenize(text: str) -> list:
    data = http("/tokenize", {"content": text})
    toks = data.get("tokens") or data.get("ids") or []
    return toks if isinstance(toks, list) else []


def make_prompt(n_target: int) -> tuple[str, int]:
    unit = "测试数据0123456789。"
    ids = tokenize(unit)
    if not ids:
        raise SystemExit("tokenize failed")
    need = (n_target + len(ids) - 1) // len(ids)
    text = unit * need
    ids = tokenize(text)
    while len(ids) > n_target + 32 and need > 1:
        need -= 1
        text = unit * need
        ids = tokenize(text)
    return text, len(ids)


def completion(prompt: str, n_predict: int, timeout: float = 300) -> dict:
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
        timeout=timeout,
    )
    wall = time.time() - t0
    t = data.get("timings") or {}
    return {
        "wall_s": round(wall, 3),
        "prompt_n": t.get("prompt_n"),
        "prompt_ms": t.get("prompt_ms"),
        "prompt_per_second": t.get("prompt_per_second"),
        "predicted_n": t.get("predicted_n"),
        "predicted_ms": t.get("predicted_ms"),
        "predicted_per_second": t.get("predicted_per_second"),
        "predicted_per_token_ms": t.get("predicted_per_token_ms"),
        "stop": data.get("stop"),
    }


def main() -> None:
    health = http("/health")
    models = http("/v1/models")
    mid = (models.get("data") or [{}])[0]
    print("HEALTH", health)
    print("NVIDIA_IDLE", nvidia())
    print("MODEL", mid.get("id"), "n_ctx", (mid.get("meta") or {}).get("n_ctx"))

    print("WARMUP", completion("OK. ", 16, timeout=60))

    rows = []
    for label, n_prompt, n_pred in (
        ("short-512", 512, 64),
        ("mid-8192", 8192, 128),
        ("mid-8192-b", 8192, 128),
    ):
        text, got = make_prompt(n_prompt)
        print(f"BUILD {label} tokens={got}", flush=True)
        rec = completion(text, n_pred, timeout=300)
        rec["label"] = label
        rec["built_tokens"] = got
        rec["nvidia"] = nvidia()
        rows.append(rec)
        print("RUN", json.dumps(rec, ensure_ascii=False), flush=True)

    out = {
        "when": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "health": health,
        "model": mid,
        "nvidia_idle": nvidia(),
        "rows": rows,
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
