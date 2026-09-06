#!/usr/bin/env bash
# Overnight DeepSeek IQ2 sweep on EVO host:
# wait for the 81G GGUF, then find the best all-at-once parallel setting
# (Vulkan1 AMD + Vulkan0 4080 + RPC0 Mac Metal).
set -uo pipefail

MIX="${MIX_VULKAN:-$HOME/opt/unsloth-llama-b10698-mix-vulkan}"
BIN="${LLAMA_SERVER:-$MIX/llama-server}"
MODEL="${DS_GGUF:-$HOME/models/gguf/DeepSeek-V4-Flash-IQ2XXS/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf}"
NEED=86720111488
RPC="${RPC:-<host>:50052}"
PORT="${PORT:-8080}"
OUT="${OUT:-$HOME/logs/overnight-ds-parallel}"
CTX="${CTX:-4096}"
LOAD_SECS="${LOAD_SECS:-900}"
HEALTH_HANG_SECS="${HEALTH_HANG_SECS:-480}"
mkdir -p "$OUT/runs" "$HOME/logs"

STATUS="$OUT/STATUS.txt"
SUMMARY="$OUT/SUMMARY.md"
export LD_LIBRARY_PATH="$MIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GGML_RPC_NO_RDMA=1
unset VK_ICD_FILENAMES

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$OUT/supervisor.log"; }
size_now() { stat -c%s "$MODEL" 2>/dev/null || echo 0; }

write_status() {
  cat >"$STATUS" <<EOF
time=$(date '+%F %T')
phase=$1
detail=$2
file_bytes=$(size_now)
need=$NEED
wget=$(pgrep -c -f 'wget.*DeepSeek-V4-Flash-IQ2' || true)
mihomo=$(pgrep -c -f '$HOME/bin/mihomo' || true)
llama=$(pgrep -c -x llama-server || true)
rpc_ok=$(nc -z -w 2 <host> 50052 && echo yes || echo no)
EOF
}

ensure_mihomo() {
  if ! pgrep -f '$HOME/bin/mihomo -d' >/dev/null; then
    log "mihomo down — restart"
    nohup "$HOME/bin/mihomo" -d "$HOME/clash-kr" >>"$HOME/clash-kr/mihomo.log" 2>&1 &
    sleep 2
  fi
}

switch_yhc() {
  local node="$1"
  curl -fsS -X PUT -H 'Authorization: Bearer set-your-secret' \
    -H 'Content-Type: application/json' \
    --data "{\"name\":\"$node\"}" \
    'http://127.0.0.1:9090/proxies/%E8%90%A4%E7%81%AB%E8%99%AByinghuochong.app' >/dev/null || true
  log "yhc node -> $node"
}

ensure_wget() {
  if pgrep -f 'wget.*DeepSeek-V4-Flash-IQ2' >/dev/null; then
    return 0
  fi
  log "wget down — resume"
  nohup "$HOME/bin/dl-deepseek-iq2-kr.sh" >>"$HOME/logs/dl-deepseek-iq2-mirror.nohup" 2>&1 &
}

rotate_if_slow() {
  local s1 s2 rate
  s1=$(size_now)
  sleep 20
  s2=$(size_now)
  rate=$(( (s2 - s1) / 20 ))
  log "download rate ${rate} B/s size=$s2"
  if [[ "$rate" -lt 400000 ]]; then
    local nodes=(
      "美国5-原生:yhc222.com"
      "美国4-2-备用"
      "美国10-原生Gemini优化"
      "美国2-官网:yhc222.com"
      "美国1-有问题发邮件:kefu@yhc66.me"
      "台湾7-原生Gemini优化"
    )
    local idx=$(( RANDOM % ${#nodes[@]} ))
    switch_yhc "${nodes[$idx]}"
    pkill -f 'wget.*DeepSeek-V4-Flash-IQ2' || true
    sleep 1
    ensure_wget
  fi
}

wait_download() {
  write_status download "waiting for $NEED bytes"
  local last_rotate=0
  while true; do
    local sz
    sz=$(size_now)
    if [[ "$sz" -eq "$NEED" ]]; then
      log "download complete $sz"
      pkill -f 'wget.*DeepSeek-V4-Flash-IQ2' || true
      write_status download_done "$sz"
      return 0
    fi
    ensure_mihomo
    ensure_wget
    write_status download "$sz / $NEED"
    local now
    now=$(date +%s)
    if (( now - last_rotate >= 180 )); then
      rotate_if_slow
      last_rotate=$now
    else
      sleep 20
    fi
  done
}

wait_rpc() {
  write_status wait_rpc "nc $RPC"
  local i
  for i in $(seq 1 180); do
    if nc -z -w 2 <host> 50052; then
      log "rpc up $RPC"
      return 0
    fi
    write_status wait_rpc "try $i"
    sleep 10
  done
  log "rpc never came up — cluster runs will fail"
  return 1
}

stop_llama() {
  pkill -x llama-server || true
  sleep 2
  pkill -9 -x llama-server || true
  sleep 1
}

log_has() {
  local pat="$1" f="$2"
  grep -Eiq "$pat" "$f" 2>/dev/null
}

start_llama() {
  local name="$1" devices="$2" ts="$3"
  shift 3
  local extra=("$@")
  local slog="$OUT/runs/${name}.server.log"
  stop_llama
  : >"$slog"
  local rpc_args=()
  if [[ "$devices" == *RPC0* ]]; then
    rpc_args=(--rpc "$RPC")
  fi
  nohup "$BIN" -m "$MODEL" \
    --host 0.0.0.0 --port "$PORT" --alias "ds-${name}" \
    "${rpc_args[@]}" \
    --device "$devices" --split-mode layer --tensor-split "$ts" \
    --gpu-layers all --flash-attn on --fit off \
    --no-host --load-mode mmap \
    --ctx-size "$CTX" --batch-size 512 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --threads 32 --threads-batch 32 \
    --jinja --no-webui --metrics --parallel 1 \
    --temp 0.7 --top-p 0.8 --top-k 20 \
    "${extra[@]}" \
    >"$slog" 2>&1 &
  echo $!
}

wait_health() {
  local name="$1" slog="$2"
  local t0 now elapsed last_progress
  t0=$(date +%s)
  last_progress=$t0
  while true; do
    now=$(date +%s)
    elapsed=$(( now - t0 ))
    if [[ "$elapsed" -ge "$LOAD_SECS" ]]; then
      echo "timeout_load"
      return 1
    fi
    if log_has 'out of memory|failed to allocate|invalid data ptr|failed to allocate compute|GGML_ASSERT' "$slog"; then
      echo "oom_or_crash"
      return 1
    fi
    if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/health" 2>/dev/null | grep -Eq '"ok"|status.: .ok'; then
      echo "ok"
      return 0
    fi
    if [[ -f "$slog" ]]; then
      local mtime
      mtime=$(stat -c %Y "$slog")
      if (( now - mtime < 20 )); then
        last_progress=$now
      fi
    fi
    if log_has 'threadpool' "$slog" && (( now - last_progress > HEALTH_HANG_SECS )); then
      echo "hang_after_threadpool"
      return 1
    fi
    write_status "load:$name" "${elapsed}s"
    sleep 5
  done
}

bench_once() {
  local name="$1"
  python3 - "$name" "$PORT" "$OUT" <<'PY'
import json, sys, time, urllib.request
name, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
prompt = (
    "Write a careful 8-bullet summary of mixture-of-experts routing, "
    "then list three practical risks when splitting a 80GB GGUF across "
    "an eGPU, an iGPU with GTT, and a remote Metal RPC worker. "
    "Keep the answer concrete."
)
body = json.dumps({
    "model": f"ds-{name}",
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": 128,
    "temperature": 0.2,
    "stream": False,
}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/chat/completions",
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode())
    wall = time.time() - t0
except Exception as e:
    json.dump({"ok": False, "error": str(e)}, open(f"{out}/runs/{name}.last.json", "w"))
    print("bench_fail")
    raise SystemExit(1)
timings = data.get("timings") or {}
usage = data.get("usage") or {}
row = {
    "ok": True,
    "wall_s": wall,
    "prompt_n": timings.get("prompt_n"),
    "prompt_ms": timings.get("prompt_ms"),
    "prompt_per_second": timings.get("prompt_per_second"),
    "predicted_n": timings.get("predicted_n"),
    "predicted_ms": timings.get("predicted_ms"),
    "predicted_per_second": timings.get("predicted_per_second"),
    "usage": usage,
}
json.dump(row, open(f"{out}/runs/{name}.last.json", "w"), indent=2)
print(f"prompt={row['prompt_per_second']} gen={row['predicted_per_second']}")
PY
}

nvidia_mem() {
  nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "na"
}

run_config() {
  local name="$1" devices="$2" ts="$3"
  shift 3
  local extra=("$@")
  local result="$OUT/runs/${name}.json"
  if [[ -f "$result" ]] && grep -q '"status": "ok"' "$result"; then
    log "skip $name (already ok)"
    return 0
  fi
  log "START $name devices=$devices ts=$ts extra=${extra[*]-}"
  write_status "run:$name" "$devices $ts"
  local slog="$OUT/runs/${name}.server.log"
  local pid
  pid=$(start_llama "$name" "$devices" "$ts" "${extra[@]+"${extra[@]}"}")
  local health
  health=$(wait_health "$name" "$slog" || true)
  local mem
  mem=$(nvidia_mem)
  if [[ "$health" != "ok" ]]; then
    log "FAIL $name health=$health mem=$mem"
    python3 - "$result" "$name" "$devices" "$ts" "$health" "$mem" "$slog" <<'PY'
import json,sys,re
result,name,devices,ts,health,mem,slog=sys.argv[1:]
tail=""
try:
    tail=open(slog,errors="replace").read()[-4000:]
except Exception:
    pass
json.dump({"name":name,"devices":devices,"ts":ts,"status":health or "fail","nvidia":mem,"log_tail":tail}, open(result,"w"), indent=2)
PY
    stop_llama
    return 1
  fi
  # warmup + 3 timed
  local i gens=()
  for i in 1 2 3 4; do
    if ! bench_once "$name"; then
      log "FAIL $name bench"
      python3 - "$result" "$name" "$devices" "$ts" "$mem" <<'PY'
import json,sys
result,name,devices,ts,mem=sys.argv[1:]
json.dump({"name":name,"devices":devices,"ts":ts,"status":"bench_fail","nvidia":mem}, open(result,"w"), indent=2)
PY
      stop_llama
      return 1
    fi
    [[ "$i" -eq 1 ]] && continue
    gens+=("$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("predicted_per_second") or 0)' "$OUT/runs/${name}.last.json")")
  done
  python3 - "$result" "$name" "$devices" "$ts" "$mem" "$OUT/runs/${name}.last.json" "${gens[@]}" <<'PY'
import json,sys,statistics
result,name,devices,ts,mem,last = sys.argv[1:7]
gens=[float(x) for x in sys.argv[7:]]
lastj=json.load(open(last))
row={
  "name": name,
  "devices": devices,
  "ts": ts,
  "status": "ok",
  "nvidia": mem,
  "prompt_per_second": lastj.get("prompt_per_second"),
  "gen_tps": gens,
  "gen_tps_mean": statistics.mean(gens) if gens else None,
  "gen_tps_stdev": statistics.pstdev(gens) if len(gens)>1 else 0,
  "last": lastj,
}
json.dump(row, open(result,"w"), indent=2)
print("OK", name, "mean", row["gen_tps_mean"], "prefill", row["prompt_per_second"])
PY
  log "OK $name mean_gen=$(python3 -c 'import json; print(json.load(open("'"$result"'")).get("gen_tps_mean"))')"
  stop_llama
}

summarize() {
  python3 - "$OUT" <<'PY'
import json, pathlib, datetime
out = pathlib.Path(__import__("sys").argv[1])
rows=[]
for p in sorted((out/"runs").glob("*.json")):
    if p.name.endswith(".last.json"):
        continue
    try:
        d=json.loads(p.read_text())
    except Exception:
        continue
    rows.append(d)
ok=[r for r in rows if r.get("status")=="ok" and r.get("gen_tps_mean")]
ok.sort(key=lambda r: r["gen_tps_mean"], reverse=True)
lines=["# DeepSeek IQ2 overnight parallel sweep", "", f"generated {datetime.datetime.now().isoformat(timespec='seconds')}", ""]
if ok:
    w=ok[0]
    lines += [
        f"**winner:** `{w['name']}`  devices=`{w['devices']}`  ts=`{w['ts']}`",
        f"**gen:** {w['gen_tps_mean']:.3f} t/s   **prefill:** {w.get('prompt_per_second')}",
        f"**4080:** {w.get('nvidia')}",
        "",
        "Winner is highest mean decode t/s among configs that loaded and finished 3 gens.",
        "",
    ]
else:
    lines += ["No successful parallel run.", ""]
lines += ["| name | devices | ts | status | gen t/s | prefill t/s | 4080 |", "|---|---|---|---|---|---|---|"]
def key(r):
    return (-(r.get("gen_tps_mean") or -1), r.get("name"))
for r in sorted(rows, key=key):
    lines.append(
        f"| {r.get('name')} | {r.get('devices')} | {r.get('ts')} | {r.get('status')} | "
        f"{r.get('gen_tps_mean') if r.get('gen_tps_mean') is not None else ''} | "
        f"{r.get('prompt_per_second') if r.get('prompt_per_second') is not None else ''} | {r.get('nvidia','')} |"
    )
(out/"SUMMARY.md").write_text("\n".join(lines)+"\n")
(out/"results.json").write_text(json.dumps({"winner": ok[0] if ok else None, "rows": rows}, indent=2))
print("\n".join(lines[:20]))
PY
}

main() {
  log "overnight sweep start"
  [[ -x "$BIN" ]] || { log "missing $BIN"; exit 1; }
  wait_download
  wait_rpc || log "continuing; RPC-less configs still run"
  # Baselines first so we have a ceiling even if cluster hangs.
  run_config amd_only "Vulkan1" "100" --ubatch-size 128 || true
  run_config amd_4080_84_16 "Vulkan1,Vulkan0" "84,16" --ubatch-size 128 || true
  run_config amd_4080_82_18 "Vulkan1,Vulkan0" "82,18" --ubatch-size 128 || true
  # All-at-once cluster. 4080 first budget ~13-15 GiB, leftover to Mac.
  run_config c_74_14_12 "Vulkan1,Vulkan0,RPC0" "74,14,12" --ubatch-size 128 || true
  run_config c_72_16_12 "Vulkan1,Vulkan0,RPC0" "72,16,12" --ubatch-size 128 || true
  run_config c_72_13_15 "Vulkan1,Vulkan0,RPC0" "72,13,15" --ubatch-size 128 || true
  run_config c_70_18_12 "Vulkan1,Vulkan0,RPC0" "70,18,12" --ubatch-size 128 || true
  run_config c_68_16_16 "Vulkan1,Vulkan0,RPC0" "68,16,16" --ubatch-size 128 || true
  run_config c_66_18_16 "Vulkan1,Vulkan0,RPC0" "66,18,16" --ubatch-size 128 || true
  run_config c_75_13_12 "Vulkan1,Vulkan0,RPC0" "75,13,12" --ubatch-size 128 || true
  # Device-order / overflow-first variants on the safer 4080 budget.
  run_config c_ord_mac_74_12_14 "Vulkan1,RPC0,Vulkan0" "74,12,14" --ubatch-size 128 || true
  # Ubatch on the current best cluster (re-run two extra if a cluster already ok).
  local best
  best=$(python3 - "$OUT" <<'PY'
import json, pathlib, sys
out=pathlib.Path(sys.argv[1])
best=None
for p in (out/"runs").glob("c_*.json"):
    if p.name.endswith(".last.json"): continue
    d=json.loads(p.read_text())
    if d.get("status")=="ok" and d.get("gen_tps_mean"):
        if not best or d["gen_tps_mean"]>best["gen_tps_mean"]:
            best=d
print(f"{best['name']}|{best['devices']}|{best['ts']}" if best else "")
PY
)
  if [[ -n "$best" ]]; then
    IFS='|' read -r bname bdev bts <<<"$best"
    run_config "${bname}_ub64" "$bdev" "$bts" --ubatch-size 64 || true
    run_config "${bname}_ub256" "$bdev" "$bts" --ubatch-size 256 || true
    run_config "${bname}_faoff" "$bdev" "$bts" --ubatch-size 128 --flash-attn off || true
  fi
  summarize
  write_status done "see $SUMMARY"
  log "overnight sweep done"
}

main "$@"
