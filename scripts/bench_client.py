#!/usr/bin/env python3
"""OpenAI-compatible endpoint bench: speed + eval subset + scorecard.

Deps: pyyaml, httpx (or requests). Stdlib for the rest.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    yaml = None  # type: ignore

try:
    import httpx
except ImportError:
    httpx = None  # type: ignore

try:
    import requests
except ImportError:
    requests = None  # type: ignore

ROOT = Path(__file__).resolve().parents[1]


def load_yaml(path: Path) -> dict:
    if yaml is None:
        raise SystemExit("pyyaml required: pip install pyyaml")
    with path.open() as f:
        return yaml.safe_load(f) or {}


def http_post_json(url: str, payload: dict, headers: dict, timeout: float, stream: bool = False):
    if httpx is not None:
        client = httpx.Client(timeout=timeout)
        if stream:
            return client.stream("POST", url, json=payload, headers=headers)
        r = client.post(url, json=payload, headers=headers)
        r.raise_for_status()
        return r.json()
    if requests is None:
        raise SystemExit("need httpx or requests")
    if stream:
        return requests.post(url, json=payload, headers=headers, timeout=timeout, stream=True)
    r = requests.post(url, json=payload, headers=headers, timeout=timeout)
    r.raise_for_status()
    return r.json()


def stream_chat(
    base_url: str,
    model: str,
    messages: list[dict],
    *,
    max_tokens: int,
    temperature: float,
    top_p: float,
    api_key: str | None,
    timeout: float,
    logprobs: int | None = None,
) -> dict[str, Any]:
    url = base_url.rstrip("/") + "/chat/completions"
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "top_p": top_p,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    if logprobs:
        payload["logprobs"] = True
        payload["top_logprobs"] = logprobs

    t0 = time.perf_counter()
    ttft = None
    text_parts: list[str] = []
    usage = None
    finish = None

    if httpx is not None:
        with httpx.Client(timeout=timeout) as client:
            with client.stream("POST", url, json=payload, headers=headers) as resp:
                resp.raise_for_status()
                for line in resp.iter_lines():
                    if not line:
                        continue
                    if isinstance(line, bytes):
                        line = line.decode()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    obj = json.loads(data)
                    if obj.get("usage"):
                        usage = obj["usage"]
                    choices = obj.get("choices") or []
                    if not choices:
                        continue
                    delta = choices[0].get("delta") or {}
                    content = delta.get("content")
                    if content is not None:
                        if ttft is None:
                            ttft = time.perf_counter() - t0
                        text_parts.append(content)
                    if choices[0].get("finish_reason"):
                        finish = choices[0]["finish_reason"]
    else:
        assert requests is not None
        with requests.post(url, json=payload, headers=headers, timeout=timeout, stream=True) as resp:
            resp.raise_for_status()
            for line in resp.iter_lines(decode_unicode=True):
                if not line:
                    continue
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                obj = json.loads(data)
                if obj.get("usage"):
                    usage = obj["usage"]
                choices = obj.get("choices") or []
                if not choices:
                    continue
                delta = choices[0].get("delta") or {}
                content = delta.get("content")
                if content is not None:
                    if ttft is None:
                        ttft = time.perf_counter() - t0
                    text_parts.append(content)
                if choices[0].get("finish_reason"):
                    finish = choices[0]["finish_reason"]

    t1 = time.perf_counter()
    text = "".join(text_parts)
    prompt_tokens = (usage or {}).get("prompt_tokens")
    completion_tokens = (usage or {}).get("completion_tokens")
    if completion_tokens is None:
        completion_tokens = max(1, len(text.split()))
    if prompt_tokens is None:
        prompt_tokens = max(1, sum(len(str(m.get("content", ""))) for m in messages) // 4)

    total_s = t1 - t0
    gen_s = max(1e-6, total_s - (ttft or 0.0))
    prefill_tps = (prompt_tokens / ttft) if ttft and ttft > 0 else None
    decode_tps = completion_tokens / gen_s if gen_s > 0 else None

    return {
        "text": text,
        "ttft_s": ttft,
        "total_s": total_s,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "prefill_tok_s": prefill_tps,
        "decode_tok_s": decode_tps,
        "finish_reason": finish,
        "usage": usage,
    }


def chat_once(
    base_url: str,
    model: str,
    messages: list[dict],
    *,
    max_tokens: int,
    temperature: float,
    top_p: float,
    api_key: str | None,
    timeout: float,
    logprobs: int | None = None,
) -> dict[str, Any]:
    url = base_url.rstrip("/") + "/chat/completions"
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "top_p": top_p,
        "stream": False,
    }
    if logprobs:
        payload["logprobs"] = True
        payload["top_logprobs"] = logprobs

    t0 = time.perf_counter()
    data = http_post_json(url, payload, headers, timeout, stream=False)
    t1 = time.perf_counter()
    choice = (data.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    text = message.get("content") or ""
    usage = data.get("usage") or {}
    return {
        "text": text,
        "total_s": t1 - t0,
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "logprobs": choice.get("logprobs"),
        "raw": data,
    }


def filler_prompt(depth_tokens: int) -> str:
    unit = "The quick brown fox jumps over the lazy dog. "
    # ~10 tokens per unit at ~4 chars/token rough; use explicit repeat count
    need = max(1, depth_tokens // 10)
    return unit * need


def run_speed(ep: dict, cfg: dict, dry_run: bool) -> list[dict]:
    speed = cfg.get("speed") or {}
    depths = speed.get("depths") or [0]
    decode_tokens = int(speed.get("decode_tokens") or 64)
    concurrencies = speed.get("concurrency") or [1]
    warmup = int(speed.get("warmup") or 0)
    repeats = int(speed.get("repeats") or 1)
    temp = float(cfg.get("temperature", 0.0))
    top_p = float(cfg.get("top_p", 1.0))
    timeout = float(cfg.get("timeout_s", 120))

    results = []
    for depth in depths:
        prompt = "Say OK." if depth == 0 else filler_prompt(int(depth)) + "\nSay OK."
        messages = [{"role": "user", "content": prompt}]
        for c in concurrencies:
            # warmup
            for _ in range(warmup):
                if dry_run:
                    stream_chat(
                        ep["base_url"],
                        ep["model"],
                        messages,
                        max_tokens=8,
                        temperature=temp,
                        top_p=top_p,
                        api_key=ep.get("api_key"),
                        timeout=timeout,
                    )
                else:
                    stream_chat(
                        ep["base_url"],
                        ep["model"],
                        messages,
                        max_tokens=8,
                        temperature=temp,
                        top_p=top_p,
                        api_key=ep.get("api_key"),
                        timeout=timeout,
                    )

            runs = []

            def one(_i: int) -> dict:
                return stream_chat(
                    ep["base_url"],
                    ep["model"],
                    messages,
                    max_tokens=decode_tokens,
                    temperature=temp,
                    top_p=top_p,
                    api_key=ep.get("api_key"),
                    timeout=timeout,
                )

            for r in range(repeats):
                if int(c) <= 1:
                    runs.append(one(r))
                else:
                    with ThreadPoolExecutor(max_workers=int(c)) as pool:
                        futs = [pool.submit(one, i) for i in range(int(c))]
                        for f in as_completed(futs):
                            runs.append(f.result())

            def mean_of(key: str):
                vals = [x[key] for x in runs if x.get(key) is not None]
                return statistics.mean(vals) if vals else None

            results.append(
                {
                    "depth_tokens_requested": depth,
                    "concurrency": c,
                    "n_runs": len(runs),
                    "ttft_s_mean": mean_of("ttft_s"),
                    "prefill_tok_s_mean": mean_of("prefill_tok_s"),
                    "decode_tok_s_mean": mean_of("decode_tok_s"),
                    "prompt_tokens_mean": mean_of("prompt_tokens"),
                    "completion_tokens_mean": mean_of("completion_tokens"),
                }
            )
    return results


def check_gsm(text: str, answer: str) -> bool:
    # last integer-like token
    import re

    nums = re.findall(r"-?\d+(?:\.\d+)?", text.replace(",", ""))
    if not nums:
        return False
    return nums[-1].lstrip("0") == answer.lstrip("0") or nums[-1] == answer


def check_ifeval_bullets(text: str) -> bool:
    lines = [ln for ln in text.strip().splitlines() if ln.strip()]
    if len(lines) != 3:
        return False
    return all(ln.startswith("- ") for ln in lines)


# WARNING: Executing model-generated code is unsafe outside a sandbox.
# The HumanEval path runs untrusted code in a subprocess with a timeout and
# no network intent, but it is NOT a security boundary. Prefer an OS sandbox
# (containers, seccomp, gVisor) before scoring untrusted model output.
HUMANEVAL_EXEC_WARNING = (
    "WARNING: Executing model-generated code is unsafe outside a sandbox. "
    "HumanEval pass@1 runs candidate code via subprocess with a timeout; "
    "treat this as a convenience harness, not isolation."
)


def extract_python_code(text: str) -> str:
    """Pull the first fenced python block, else the largest def-containing chunk."""
    import re

    fenced = re.findall(r"```(?:python)?\s*([\s\S]*?)```", text, flags=re.IGNORECASE)
    for block in fenced:
        if "def " in block:
            return block.strip()
    if "def " in text:
        # drop leading prose before first def
        idx = text.find("def ")
        return text[idx:].strip()
    return text.strip()


def run_humaneval_test(
    code: str,
    test: str,
    entry_point: str,
    *,
    timeout_s: float = 10.0,
) -> dict:
    """Execute HumanEval-style ``test`` + ``check(entry_point)`` in a subprocess.

    Returns ``{"passed": bool, "error": str|None}``.
    """
    import os
    import subprocess
    import tempfile

    print(HUMANEVAL_EXEC_WARNING, file=sys.stderr)

    harness = (
        "# autogenerated humaneval harness\n"
        + code
        + "\n\n"
        + test
        + "\n\n"
        + f"check({entry_point})\n"
    )
    with tempfile.TemporaryDirectory(prefix="amdbeat-he-") as tmp:
        tmp_path = Path(tmp)
        script = tmp_path / "candidate.py"
        script.write_text(harness)
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "PYTHONPATH": "",
            "HOME": str(tmp_path),
            "TMPDIR": str(tmp_path),
            # Discourage accidental network use by libs that honor these:
            "NO_PROXY": "*",
            "no_proxy": "*",
            "HTTP_PROXY": "",
            "HTTPS_PROXY": "",
            "http_proxy": "",
            "https_proxy": "",
        }
        try:
            proc = subprocess.run(
                [sys.executable, str(script)],
                cwd=str(tmp_path),
                env=env,
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
        except subprocess.TimeoutExpired:
            return {"passed": False, "error": f"timeout after {timeout_s}s"}
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or f"exit {proc.returncode}").strip()
            return {"passed": False, "error": err[:500]}
        return {"passed": True, "error": None}


def score_humaneval(item: dict, model_text: str, *, timeout_s: float = 10.0):
    """Return True/False on pass, or None when the prompt lacks executable tests.

    If ``test`` / ``entry_point`` are missing, the metric is **not available**
    (do not fake signature-only checks).
    """
    test = item.get("test")
    entry = item.get("entry_point")
    if not test or not entry:
        return None, "not_available_missing_test"
    code = extract_python_code(model_text)
    result = run_humaneval_test(code, str(test), str(entry), timeout_s=timeout_s)
    return result["passed"], result.get("error")


def run_eval(ep: dict, cfg: dict) -> list[dict]:
    ev = cfg.get("eval") or {}
    prompts_path = ROOT / ev.get("prompts_file", "prompts/fixed_prompts.jsonl")
    suites = set(ev.get("suites") or [])
    temp = float(cfg.get("temperature", 0.0))
    top_p = float(cfg.get("top_p", 1.0))
    timeout = float(cfg.get("timeout_s", 120))
    kl_cfg = cfg.get("kl") or {}
    logprobs_k = int(kl_cfg.get("logprobs") or 0)

    rows = []
    with prompts_path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            item = json.loads(line)
            suite = item.get("suite")
            if suites and suite not in suites:
                continue
            messages = [{"role": "user", "content": item["prompt"]}]
            want_lp = logprobs_k if suite == "kl" else None
            out = chat_once(
                ep["base_url"],
                ep["model"],
                messages,
                max_tokens=int(item.get("max_tokens") or 64),
                temperature=temp,
                top_p=top_p,
                api_key=ep.get("api_key"),
                timeout=timeout,
                logprobs=want_lp,
            )
            ok = None
            detail = None
            if suite == "gsm8k_subset" and item.get("answer") is not None:
                ok = check_gsm(out["text"], str(item["answer"]))
            elif suite == "ifeval_subset":
                ok = check_ifeval_bullets(out["text"])
            elif suite == "humaneval_subset":
                ok, detail = score_humaneval(item, out["text"])
            row = {
                "id": item.get("id"),
                "suite": suite,
                "ok": ok,
                "text": out["text"][:500],
                "has_logprobs": bool(out.get("logprobs")),
                "latency_s": out.get("total_s"),
            }
            if suite == "humaneval_subset":
                row["humaneval_detail"] = detail
                if ok is None:
                    row["metric"] = "not_available"
            rows.append(row)
    return rows


def scorecard_md(meta: dict, speed: list[dict], eval_rows: list[dict]) -> str:
    lines = []
    lines.append(f"# Scorecard: {meta.get('endpoint_name')} / {meta.get('model')}")
    lines.append("")
    lines.append(f"- generated_at (UTC): `{meta.get('generated_at')}`")
    lines.append(f"- base_url: `{meta.get('base_url')}`")
    lines.append(f"- seed: `{meta.get('seed')}`")
    lines.append(f"- dry_run: `{meta.get('dry_run')}`")
    lines.append("")
    lines.append("## Speed")
    lines.append("")
    lines.append("| depth | c | TTFT s | prefill tok/s | decode tok/s | prompt toks |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    for s in speed:
        lines.append(
            "| {depth} | {c} | {ttft} | {pref} | {dec} | {pt} |".format(
                depth=s["depth_tokens_requested"],
                c=s["concurrency"],
                ttft=_fmt(s.get("ttft_s_mean")),
                pref=_fmt(s.get("prefill_tok_s_mean")),
                dec=_fmt(s.get("decode_tok_s_mean")),
                pt=_fmt(s.get("prompt_tokens_mean")),
            )
        )
    lines.append("")
    lines.append("## Eval subset")
    lines.append("")
    by = {}
    for r in eval_rows:
        by.setdefault(r["suite"], []).append(r)
    lines.append("| suite | n | pass | pass_rate |")
    lines.append("|---|---:|---:|---:|")
    for suite, items in by.items():
        if suite == "humaneval_subset" and any(i.get("metric") == "not_available" for i in items):
            if all(i.get("ok") is None for i in items):
                lines.append(f"| {suite} | {len(items)} | n/a | not available |")
                continue
        judged = [i for i in items if i.get("ok") is not None]
        n = len(judged) if judged else len(items)
        p = sum(1 for i in judged if i["ok"]) if judged else 0
        rate = (p / n) if n else float("nan")
        lines.append(f"| {suite} | {n} | {p if judged else 'n/a'} | {_fmt(rate) if judged else 'n/a'} |")
    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- Quality vs BF16 (KL / top-token agreement) requires a reference endpoint; see `scripts/kl_compare.py`.")
    lines.append("- Memory (weights GB, KV capacity) must be filled from server logs / `nvidia-smi` — not auto-measured here.")
    lines.append("- Pin engine image digest, weight revision, and sampling flags before publishing comparisons.")
    lines.append("")
    return "\n".join(lines)


def _fmt(v) -> str:
    if v is None or (isinstance(v, float) and (math.isnan(v) or math.isinf(v))):
        return "-"
    if isinstance(v, float):
        return f"{v:.3f}"
    return str(v)


def main() -> None:
    ap = argparse.ArgumentParser(description="AMDBeat bench client")
    ap.add_argument("--endpoints", default=str(ROOT / "configs" / "endpoints.example.yaml"))
    ap.add_argument("--bench", default=str(ROOT / "configs" / "bench.yaml"))
    ap.add_argument("--endpoint", default="mock", help="key under endpoints:")
    ap.add_argument("--dry-run", action="store_true", help="run against configured endpoint (mock recommended)")
    ap.add_argument("--skip-speed", action="store_true")
    ap.add_argument("--skip-eval", action="store_true")
    ap.add_argument("--out-name", default=None)
    args = ap.parse_args()

    endpoints = load_yaml(Path(args.endpoints)).get("endpoints") or {}
    if args.endpoint not in endpoints:
        raise SystemExit(f"unknown endpoint {args.endpoint!r}; have {list(endpoints)}")
    ep = endpoints[args.endpoint]
    cfg = load_yaml(Path(args.bench))

    # Safety: refuse private lab IPs unless --dry-run was NOT the only guard —
    # we never call Sparks from default configs; still warn if URL looks like LAN.
    base = ep.get("base_url", "")
    if any(x in base for x in ("192.168.", "10.")) and not args.dry_run:
        # require explicit acknowledgment via env or dry-run for LAN
        print(
            "Refusing private/LAN endpoint without --dry-run flag as acknowledgment. "
            "For real lab GPU runs, set QUANT_LAB_ALLOW_LAN=1 after approval.",
            file=sys.stderr,
        )
        import os

        if os.environ.get("QUANT_LAB_ALLOW_LAN") != "1":
            raise SystemExit(2)

    meta = {
        "endpoint_name": args.endpoint,
        "model": ep.get("model"),
        "base_url": ep.get("base_url"),
        "seed": cfg.get("seed"),
        "dry_run": bool(args.dry_run),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    speed: list[dict] = []
    eval_rows: list[dict] = []
    if not args.skip_speed:
        speed = run_speed(ep, cfg, dry_run=args.dry_run)
    if not args.skip_eval:
        eval_rows = run_eval(ep, cfg)

    out_dir = ROOT / (cfg.get("output_dir") or "results")
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = args.out_name or f"{args.endpoint}_{stamp}"
    payload = {"meta": meta, "speed": speed, "eval": eval_rows}
    json_path = out_dir / f"{name}.json"
    md_path = out_dir / f"{name}_scorecard.md"
    json_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    md_path.write_text(scorecard_md(meta, speed, eval_rows))
    print(f"wrote {json_path}")
    print(f"wrote {md_path}")
    print(scorecard_md(meta, speed, eval_rows))


if __name__ == "__main__":
    main()
