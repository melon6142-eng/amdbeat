#!/usr/bin/env python3
"""Compare top-logprobs between a reference and candidate OpenAI-compatible endpoint.

Design notes / limitations
--------------------------
1. True KL(P_ref || P_cand) needs the full next-token distribution. OpenAI-style
   APIs only return top-k logprobs (often k<=20). We therefore report:
   - top1 agreement
   - top-k set overlap
   - partial KL over the union of returned tokens, with mass outside top-k
     treated as a single residual bucket (biased low/high depending on k).
2. Chat templates may differ across engines (vLLM / SGLang / llama.cpp /
   ExLlamaV3). Prefer /v1/completions with a raw prompt when both servers
   support it; this script uses chat completions for maximum compatibility.
3. Speculative decoding (MTP/DFlash/EAGLE) can change which tokens are proposed
   but should not change verified logits if rejection sampling is correct.
   Still: disable speculative decoding for KL runs when possible.
4. Temperature must be 0 for greedy agreement; for distributional KL use the
   same temperature on both and compare logprobs of the *same* prefix tokens
   (teacher-forced). This script does teacher-forced single-step probes by
   requesting max_tokens small and reading returned token logprobs.
5. EXL3 native KL (exllamav3 measure_model vs BF16 activations) is preferred
   when weights are local; see turboderp EXL3 tooling:
   https://github.com/turboderp-org/exllamav3
   This HTTP approach is for cross-lab serving comparisons when only APIs exist.

Deps: pyyaml, httpx|requests.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from bench_client import chat_once, load_yaml  # noqa: E402


def extract_top(logprobs_obj: dict | None) -> list[dict]:
    if not logprobs_obj:
        return []
    content = logprobs_obj.get("content") or []
    if not content:
        return []
    # first generated token's top_logprobs
    first = content[0]
    tops = first.get("top_logprobs") or []
    if tops:
        return [{"token": t.get("token"), "logprob": float(t.get("logprob"))} for t in tops]
    # fallback: just the chosen token
    return [{"token": first.get("token"), "logprob": float(first.get("logprob", float("-inf")))}]


def softmax_from_logprobs(items: list[dict]) -> dict[str, float]:
    if not items:
        return {}
    m = max(x["logprob"] for x in items)
    exps = [(x["token"], math.exp(x["logprob"] - m)) for x in items]
    z = sum(v for _, v in exps) or 1.0
    return {t: v / z for t, v in exps}


def partial_kl(p: dict[str, float], q: dict[str, float], residual: float = 1e-9) -> float:
    """KL over shared support; missing mass -> residual bucket."""
    keys = set(p) | set(q)
    # renormalize with residual for missing
    def full(d: dict[str, float]) -> dict[str, float]:
        s = sum(d.values())
        out = {k: d.get(k, 0.0) for k in keys}
        miss = max(0.0, 1.0 - s)
        out["__residual__"] = miss + residual
        z = sum(out.values())
        return {k: v / z for k, v in out.items()}

    P, Q = full(p), full(q)
    kl = 0.0
    for k, pv in P.items():
        qv = max(Q.get(k, residual), residual)
        if pv > 0:
            kl += pv * math.log(pv / qv)
    return kl


def compare_prompts(ref_ep: dict, cand_ep: dict, prompts: list[dict], k: int, timeout: float) -> dict:
    rows = []
    for item in prompts:
        messages = [{"role": "user", "content": item["prompt"]}]
        ref = chat_once(
            ref_ep["base_url"],
            ref_ep["model"],
            messages,
            max_tokens=8,
            temperature=0.0,
            top_p=1.0,
            api_key=ref_ep.get("api_key"),
            timeout=timeout,
            logprobs=k,
        )
        cand = chat_once(
            cand_ep["base_url"],
            cand_ep["model"],
            messages,
            max_tokens=8,
            temperature=0.0,
            top_p=1.0,
            api_key=cand_ep.get("api_key"),
            timeout=timeout,
            logprobs=k,
        )
        rt = extract_top(ref.get("logprobs"))
        ct = extract_top(cand.get("logprobs"))
        p = softmax_from_logprobs(rt)
        q = softmax_from_logprobs(ct)
        top1_ref = rt[0]["token"] if rt else None
        top1_cand = ct[0]["token"] if ct else None
        set_ref = {x["token"] for x in rt}
        set_cand = {x["token"] for x in ct}
        overlap = len(set_ref & set_cand) / max(1, len(set_ref | set_cand))
        rows.append(
            {
                "id": item.get("id"),
                "top1_agree": top1_ref == top1_cand,
                "top1_ref": top1_ref,
                "top1_cand": top1_cand,
                "topk_jaccard": overlap,
                "partial_kl": partial_kl(p, q) if p and q else None,
                "ref_has_logprobs": bool(rt),
                "cand_has_logprobs": bool(ct),
            }
        )
    agrees = [r["top1_agree"] for r in rows if r["ref_has_logprobs"] and r["cand_has_logprobs"]]
    kls = [r["partial_kl"] for r in rows if r.get("partial_kl") is not None]
    return {
        "n": len(rows),
        "top1_agreement": (sum(agrees) / len(agrees)) if agrees else None,
        "mean_partial_kl": (sum(kls) / len(kls)) if kls else None,
        "rows": rows,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoints", default=str(ROOT / "configs" / "endpoints.example.yaml"))
    ap.add_argument("--ref", default="mock")
    ap.add_argument("--cand", default="mock")
    ap.add_argument("--cand-model", default=None, help="override candidate model id (e.g. mock-quant)")
    ap.add_argument("--prompts", default=str(ROOT / "prompts" / "fixed_prompts.jsonl"))
    ap.add_argument("--k", type=int, default=5)
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    endpoints = load_yaml(Path(args.endpoints)).get("endpoints") or {}
    ref_ep = dict(endpoints[args.ref])
    cand_ep = dict(endpoints[args.cand])
    if args.cand_model:
        cand_ep["model"] = args.cand_model

    prompts = []
    with Path(args.prompts).open() as f:
        for line in f:
            if not line.strip():
                continue
            item = json.loads(line)
            if item.get("suite") == "kl":
                prompts.append(item)

    report = compare_prompts(ref_ep, cand_ep, prompts, args.k, args.timeout)
    report["meta"] = {
        "ref": {"base_url": ref_ep.get("base_url"), "model": ref_ep.get("model")},
        "cand": {"base_url": cand_ep.get("base_url"), "model": cand_ep.get("model")},
        "k": args.k,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "limitations": "partial KL over top-k only; see module docstring",
    }
    out = Path(args.out) if args.out else ROOT / "results" / "kl_compare_dryrun.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {out}")
    print(
        json.dumps(
            {
                "top1_agreement": report["top1_agreement"],
                "mean_partial_kl": report["mean_partial_kl"],
                "n": report["n"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
