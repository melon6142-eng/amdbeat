#!/usr/bin/env python3
"""Fold llama-bench jsonl into a Lab-Strix scorecard row."""
from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path


def rows(path: Path) -> list[dict]:
    out = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        out.append(json.loads(line))
    return out


def median_tps(items: list[dict], test: str) -> float | None:
    vals = [float(x["avg_ts"]) for x in items if x.get("n_prompt") is not None and test in (x.get("test") or "")]
    # llama-bench jsonl uses "pp512" / "tg128" in field name varies; fall back to n_gen
    if vals:
        return statistics.median(vals)
    pp = [float(x["avg_ts"]) for x in items if int(x.get("n_gen") or 0) == 0 or str(x.get("test", "")).startswith("pp")]
    tg = [float(x["avg_ts"]) for x in items if int(x.get("n_gen") or 0) > 0 and str(x.get("test", "")).startswith("tg")]
    if test == "pp" and pp:
        return statistics.median(pp)
    if test == "tg" and tg:
        return statistics.median(tg)
    return None


def summarize(path: Path) -> dict:
    data = rows(path)
    tests = {}
    for x in data:
        key = f"d{x.get('n_depth', 0)}:{x.get('test') or ('tg' if int(x.get('n_gen') or 0) else 'pp')}"
        tests.setdefault(key, []).append(float(x.get("avg_ts") or 0))
    med = {k: round(statistics.median(v), 2) for k, v in tests.items() if v}
    return {"file": path.name, "n": len(data), "median_tps": med}


def main() -> None:
    root = Path(__file__).resolve().parents[1] / "results"
    files = sorted(root.glob("*.jsonl"))
    if not files:
        print("no jsonl in", root)
        return
    for f in files:
        print(json.dumps(summarize(f)))


if __name__ == "__main__":
    main()
