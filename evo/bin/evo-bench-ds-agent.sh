#!/usr/bin/env bash
# New agent-style long-generation bench for ds4-server /v1/chat/completions.
# Does NOT start/stop servers. GPU-free dry-run supported.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [PORT] [TAG] [OUTDIR]
       $(basename "$0") --dry-run [PORT] [TAG] [OUTDIR]
       $(basename "$0") --help

Env:
  PORT                 default 8091 (also positional #1)
  TAG                  run label (positional #2; default timestamp)
  OUTDIR               default ~/logs/ds-agent-bench
  PROMPT_DIR           default ~/bench/ds-agent-prompts
  N_REPS               default 3
  MODEL                override model field in each JSON body
  SERVER_LOG           optional path; copy matching 'decoding avg=' lines into outdir
  STREAM_FALLBACK      default 1: SSE stream primary (captures TTFT); 0 = non-stream only
  CURL_TIMEOUT_S       default 3600
  DRY_RUN              if 1, only print requests (also --dry-run)
EOF
}

DRY_RUN="${DRY_RUN:-0}"
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]}"

PORT="${1:-${PORT:-8091}}"
TAG="${2:-${TAG:-}}"
OUTDIR="${3:-${OUTDIR:-$HOME/logs/ds-agent-bench}}"
PROMPT_DIR="${PROMPT_DIR:-$HOME/bench/ds-agent-prompts}"
N_REPS="${N_REPS:-3}"
STREAM_FALLBACK="${STREAM_FALLBACK:-1}"
CURL_TIMEOUT_S="${CURL_TIMEOUT_S:-3600}"
BASE="http://127.0.0.1:${PORT}"

if [[ -z "$TAG" ]]; then
  TAG="$(date +%Y%m%d_%H%M%S)"
fi

mkdir -p "$OUTDIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
JSONL="$OUTDIR/bench-${TAG}-${STAMP}.jsonl"
SUMMARY="$OUTDIR/bench-${TAG}-${STAMP}.txt"
DRYLOG="$OUTDIR/dry-run-${TAG}-${STAMP}.txt"

shopt -s nullglob
PROMPTS=("$PROMPT_DIR"/[0-9]*.json)
if [[ ${#PROMPTS[@]} -eq 0 ]]; then
  echo "No prompt JSON files in $PROMPT_DIR" >&2
  exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  {
    echo "DRY-RUN evo-bench-ds-agent"
    echo "BASE=$BASE TAG=$TAG OUTDIR=$OUTDIR N_REPS=$N_REPS MODEL=${MODEL:-"(from file)"}"
    echo "STREAM_FALLBACK=$STREAM_FALLBACK PROMPT_DIR=$PROMPT_DIR"
    echo "PROMPTS=${#PROMPTS[@]}"
    echo
    for pf in "${PROMPTS[@]}"; do
      echo "======== $(basename "$pf") ========"
      python3 - "$pf" "${MODEL:-}" <<'PY'
import json, sys
p = sys.argv[1]
model = sys.argv[2]
with open(p, encoding="utf-8") as f:
    body = json.load(f)
if model:
    body["model"] = model
s = json.dumps(body, ensure_ascii=False, indent=2)
print(s[:4000])
if len(s) > 4000:
    print("... [truncated] ...")
msgs = body.get("messages") or []
chars = sum(len(m.get("content") or "") for m in msgs)
print("# meta: messages=%d content_chars=%d max_tokens=%s tools=%s stream=%s" % (
    len(msgs), chars, body.get("max_tokens"), "tools" in body, body.get("stream")))
PY
      echo
    done
  } | tee "$DRYLOG"
  echo "Wrote dry-run log: $DRYLOG"
  exit 0
fi

export BASE JSONL SUMMARY TAG N_REPS PROMPT_DIR
export MODEL_OVERRIDE="${MODEL:-}"
export STREAM_FALLBACK CURL_TIMEOUT_S
export SERVER_LOG="${SERVER_LOG:-}"

python3 <<'PY'
import json, os, sys, time, glob, urllib.request, re
from pathlib import Path

base = os.environ["BASE"]
jsonl = os.environ["JSONL"]
summary = os.environ["SUMMARY"]
tag = os.environ["TAG"]
n_reps = int(os.environ["N_REPS"])
prompt_dir = os.environ["PROMPT_DIR"]
model_override = os.environ.get("MODEL_OVERRIDE") or ""
use_stream = os.environ.get("STREAM_FALLBACK", "1") not in ("0", "false", "False")
timeout = int(os.environ.get("CURL_TIMEOUT_S", "3600"))
server_log = os.environ.get("SERVER_LOG") or ""

def extract_timings(d):
    tim = d.get("timings") if isinstance(d.get("timings"), dict) else {}
    for k in ("stats", "meta", "performance"):
        v = d.get(k)
        if isinstance(v, dict):
            for kk, vv in v.items():
                tim.setdefault(kk, vv)
    return tim

def decode_tps(tim, usage, wall, ttft):
    for key in ("predicted_per_second", "decode_per_second", "tokens_per_second", "generation_per_second"):
        if tim.get(key) is not None:
            try:
                return float(tim[key]), "timings." + key
            except Exception:
                pass
    ct = usage.get("completion_tokens")
    if ct is None and tim.get("predicted_n") is not None:
        ct = tim.get("predicted_n")
    if not ct or wall is None:
        return None, "unavailable"
    if ttft is not None and wall - ttft > 0.001:
        return float(ct) / (wall - ttft), "completion_tokens/(wall-ttft)"
    if wall > 0:
        return float(ct) / wall, "completion_tokens/wall"
    return None, "unavailable"

def post_nonstream(body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", data=data,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read().decode())
    return d, None, time.time() - t0

def post_stream(body):
    b = dict(body)
    b["stream"] = True
    b.setdefault("stream_options", {"include_usage": True})
    data = json.dumps(b).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", data=data,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    ttft = None
    text_parts = []
    usage = {}
    finish = None
    model = b.get("model")
    raw_keys = set()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        while True:
            line = r.readline()
            if not line:
                break
            line = line.decode("utf-8", "replace").strip()
            if not line or line.startswith(":") or not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                chunk = json.loads(payload)
            except Exception:
                continue
            raw_keys.update(chunk.keys())
            if ttft is None:
                ttft = time.time() - t0
            if isinstance(chunk.get("usage"), dict):
                usage = chunk["usage"]
            if chunk.get("model"):
                model = chunk["model"]
            for ch in chunk.get("choices") or []:
                delta = ch.get("delta") or {}
                if delta.get("content"):
                    text_parts.append(delta["content"])
                if ch.get("finish_reason"):
                    finish = ch["finish_reason"]
    wall = time.time() - t0
    d = {
        "model": model,
        "choices": [{"message": {"role": "assistant", "content": "".join(text_parts)},
                     "finish_reason": finish}],
        "usage": usage,
        "timings": {},
        "_stream_keys": sorted(raw_keys),
    }
    return d, ttft, wall

def one(name, body):
    body = dict(body)
    if model_override:
        body["model"] = model_override
    rec = {"tag": tag, "name": name, "model": body.get("model"), "prompt_file": name,
           "mode": "stream" if use_stream else "nonstream"}
    try:
        if use_stream:
            d, ttft, wall = post_stream(body)
        else:
            d, ttft, wall = post_nonstream(body)
        tim = extract_timings(d)
        usage = d.get("usage") or {}
        content = ((d.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
        tps, tps_src = decode_tps(tim, usage, wall, ttft)
        rec.update({
            "wall_s": round(wall, 3),
            "ttft_s": None if ttft is None else round(ttft, 4),
            "usage": usage,
            "timings": tim,
            "prompt_tokens": usage.get("prompt_tokens"),
            "completion_tokens": usage.get("completion_tokens"),
            "decode_tps": None if tps is None else round(tps, 3),
            "decode_tps_source": tps_src,
            "predicted_per_second": tim.get("predicted_per_second"),
            "prompt_per_second": tim.get("prompt_per_second"),
            "draft_n": tim.get("draft_n"),
            "draft_n_accepted": tim.get("draft_n_accepted"),
            "finish_reason": ((d.get("choices") or [{}])[0].get("finish_reason")),
            "content_head": content[:200],
            "content_len_chars": len(content),
            "raw_keys": d.get("_stream_keys") or sorted([k for k in d.keys() if not k.startswith("_")]),
        })
    except Exception as e:
        rec["error"] = str(e)
        rec["wall_s"] = None
    Path(jsonl).open("a").write(json.dumps(rec, ensure_ascii=False) + "\n")
    print("%s/%s: decode=%s (%s) n=%s ttft=%s wall=%ss err=%s" % (
        tag, name, rec.get("decode_tps"), rec.get("decode_tps_source"),
        rec.get("completion_tokens"), rec.get("ttft_s"), rec.get("wall_s"), rec.get("error")), flush=True)
    return rec

rows = []
files = sorted(glob.glob(os.path.join(prompt_dir, "[0-9]*.json")))
for pf in files:
    with open(pf, encoding="utf-8") as f:
        body = json.load(f)
    base_name = Path(pf).stem
    for i in range(1, n_reps + 1):
        rows.append(one("%s_r%d" % (base_name, i), body))

log_snip = None
if server_log and os.path.isfile(server_log):
    text = Path(server_log).read_text(errors="replace")
    lines = [ln for ln in text.splitlines() if re.search(r"decoding.*avg=", ln, re.I)]
    log_snip = str(Path(jsonl).with_suffix("")) + ".server-decoding.txt"
    Path(log_snip).write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")

by = {}
for r in rows:
    key = r["name"].rsplit("_r", 1)[0]
    by.setdefault(key, []).append(r)

def mean(xs):
    return sum(xs) / len(xs) if xs else None

lines = []
lines.append("BENCH SUMMARY tag=%s base=%s reps=%d mode=%s" % (tag, base, n_reps, "stream" if use_stream else "nonstream"))
lines.append("jsonl=%s" % jsonl)
if log_snip:
    nlines = len(Path(log_snip).read_text().splitlines()) if os.path.isfile(log_snip) else 0
    lines.append("server_decoding_snip=%s lines=%d" % (log_snip, nlines))
lines.append("%-36s %4s %8s %8s %6s %10s %-28s %s" % ("prompt", "n", "wall_s", "ttft_s", "tok", "decode_tps", "src", "err"))
lines.append("-" * 120)
for key, rs in by.items():
    ok = [r for r in rs if not r.get("error")]
    if not ok:
        lines.append("%-36s %4d ALL_ERR" % (key, len(rs)))
        continue
    mw = mean([r["wall_s"] for r in ok if r.get("wall_s") is not None])
    mt = mean([r["ttft_s"] for r in ok if r.get("ttft_s") is not None])
    tok = mean([r["completion_tokens"] for r in ok if r.get("completion_tokens") is not None])
    tp = mean([r["decode_tps"] for r in ok if r.get("decode_tps") is not None])
    src = ok[0].get("decode_tps_source")
    lines.append("%-36s %4d %8.3f %8s %6s %10s %-28s errs=%d" % (
        key, len(ok),
        mw if mw is not None else float("nan"),
        ("%.4f" % mt) if mt is not None else "-",
        ("%.1f" % tok) if tok is not None else "-",
        ("%.3f" % tp) if tp is not None else "-",
        str(src), len(rs) - len(ok)))

Path(summary).write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
PY
