#!/usr/bin/env python3
"""Compare top-logprobs between a reference and candidate OpenAI-compatible endpoint.

Design notes / limitations
--------------------------
1. True KL(P_ref || P_cand) needs the full next-token distribution. OpenAI-style
   APIs only return top-k logprobs (often k<=20). We therefore report:
   - top-1 agreement
   - top-k set Jaccard overlap
   - **partial KL (top-k + tail bucket)** — a *lower bound* on full-vocab KL
     (see ``partial_kl_topk_tail``). Full-vocab KL must come from
     ``llama-perplexity --kl-divergence`` (or equivalent), not from this script.
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

Partial KL method (lower-bound approximation)
---------------------------------------------
Returned top-k logprobs are converted with ``exp(logprob)`` and are **not**
renormalized over the top-k alone (renormalization drops out-of-top-k mass and
distorts KL).

Let I = intersection of the two top-k token sets. Each side keeps its raw
probability on tokens in I; all remaining probability (true tail + tokens only
on that side's top-k) is collapsed into a single ``__tail__`` residual bucket:
``p_tail = max(0, 1 - sum_{t in I} p_raw[t])`` (same for q).

KL is then computed on the coarse support ``I ∪ {__tail__}``. By the KL
coarsening / data-processing inequality, merging events can only *decrease*
KL, so this value is a **lower bound** on the KL that would be obtained from
the finer top-k∪tail partition, and likewise a lower bound on full-vocab KL
when the true distributions put mass on finer distinctions. Tokens present in
one top-k but not the other are absorbed into that side's tail bucket rather
than given an ad-hoc floor.

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

TAIL_KEY = "__tail__"
_KL_EPS = 1e-12


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


def raw_probs_from_logprobs(items: list[dict]) -> dict[str, float]:
    """Convert logprobs to raw probabilities without renormalizing over top-k.

    OpenAI-style top_logprobs are absolute log-probabilities under the model
    distribution, so ``exp(logprob)`` already lies in (0, 1] and the leftover
    mass belongs in the explicit tail bucket — do **not** softmax/renorm here.
    """
    out: dict[str, float] = {}
    for x in items:
        tok = x.get("token")
        if tok is None:
            continue
        lp = float(x["logprob"])
        # clamp extreme negatives for numerical safety; keep mass honest
        out[str(tok)] = math.exp(lp) if lp > -700 else 0.0
    return out


def softmax_from_logprobs(items: list[dict]) -> dict[str, float]:
    """Deprecated helper kept for callers/tests that expect a renormed map.

    Prefer ``raw_probs_from_logprobs`` + ``partial_kl_topk_tail``.
    """
    if not items:
        return {}
    m = max(x["logprob"] for x in items)
    exps = [(x["token"], math.exp(x["logprob"] - m)) for x in items]
    z = sum(v for _, v in exps) or 1.0
    return {t: v / z for t, v in exps}


def partial_kl_topk_tail(
    p_raw: dict[str, float],
    q_raw: dict[str, float],
    eps: float = _KL_EPS,
) -> dict[str, Any]:
    """Lower-bound partial KL(P||Q) over intersection(top-k) + tail bucket.

    See module docstring for the coarsening argument. Returns a dict with
    ``kl``, ``p_tail``, ``q_tail``, ``intersection_size``, and ``method``.
    """
    if not p_raw and not q_raw:
        return {
            "kl": None,
            "p_tail": None,
            "q_tail": None,
            "intersection_size": 0,
            "method": "topk_intersection_plus_tail_lower_bound",
        }

    keys_p = set(p_raw)
    keys_q = set(q_raw)
    intersection = keys_p & keys_q

    p_shared = sum(p_raw[t] for t in intersection)
    q_shared = sum(q_raw[t] for t in intersection)
    p_tail = max(0.0, 1.0 - p_shared)
    q_tail = max(0.0, 1.0 - q_shared)

    kl = 0.0
    for t in intersection:
        pt = p_raw[t]
        qt = max(q_raw[t], eps)
        if pt > 0.0:
            kl += pt * math.log(pt / qt)

    if p_tail > 0.0:
        kl += p_tail * math.log(p_tail / max(q_tail, eps))

    return {
        "kl": kl,
        "p_tail": p_tail,
        "q_tail": q_tail,
        "intersection_size": len(intersection),
        "method": "topk_intersection_plus_tail_lower_bound",
    }


def partial_kl(p: dict[str, float], q: dict[str, float], residual: float = 1e-9) -> float:
    """Backward-compatible wrapper; prefers raw maps + tail lower-bound.

    ``residual`` is accepted for CLI/test compatibility but ignored; the tail
    bucket is derived from ``1 - sum(shared)``.
    """
    del residual  # unused; kept for signature compatibility
    result = partial_kl_topk_tail(p, q)
    val = result["kl"]
    return float(val) if val is not None else float("nan")


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
        p = raw_probs_from_logprobs(rt)
        q = raw_probs_from_logprobs(ct)
        top1_ref = rt[0]["token"] if rt else None
        top1_cand = ct[0]["token"] if ct else None
        set_ref = {x["token"] for x in rt}
        set_cand = {x["token"] for x in ct}
        overlap = len(set_ref & set_cand) / max(1, len(set_ref | set_cand))
        kl_info = partial_kl_topk_tail(p, q) if (p or q) else {
            "kl": None,
            "p_tail": None,
            "q_tail": None,
            "intersection_size": 0,
            "method": "topk_intersection_plus_tail_lower_bound",
        }
        rows.append(
            {
                "id": item.get("id"),
                "top1_agree": top1_ref == top1_cand,
                "top1_ref": top1_ref,
                "top1_cand": top1_cand,
                "topk_jaccard": overlap,
                "partial_kl": kl_info["kl"],
                "partial_kl_method": kl_info["method"],
                "p_tail": kl_info["p_tail"],
                "q_tail": kl_info["q_tail"],
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
        "partial_kl_note": (
            "partial KL (top-k + tail bucket) is a lower-bound approximation; "
            "full-vocab KL requires llama-perplexity --kl-divergence"
        ),
        "rows": rows,
    }


def main() -> None:
    ap = argparse.ArgumentParser(
        description=(
            "Partial KL (top-k + tail bucket, lower bound) and top-1 agreement "
            "between two OpenAI-compatible endpoints. Full-vocab KL: use "
            "llama-perplexity --kl-divergence."
        )
    )
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
        "limitations": (
            "partial KL (top-k + tail bucket) is a lower-bound approximation via "
            "intersection coarsening; full-vocab KL must come from "
            "llama-perplexity --kl-divergence"
        ),
        "method": "topk_intersection_plus_tail_lower_bound",
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
                "partial_kl_note": report["partial_kl_note"],
                "n": report["n"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
