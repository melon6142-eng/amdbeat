#!/usr/bin/env bash
# Capture identity + in-load nvidia-smi for a sale proof. Does not stop :8080/:8081.
set -euo pipefail
OUT="${OUT:-$HOME/hybrid-results/4080-sale-2026-09-12}"
mkdir -p "$OUT"

nvidia-smi -L >"$OUT/01-L.txt"
nvidia-smi -q >"$OUT/02-query-idle.txt"
nvidia-smi --query-gpu=name,uuid,serial,vbios_version,pci.bus_id,pcie.link.gen.max,pcie.link.gen.current,pcie.link.width.max,pcie.link.width.current,memory.total,memory.used,clocks.gr,clocks.mem,clocks.max.gr,clocks.max.mem,power.limit,power.draw,temperature.gpu,fan.speed,utilization.gpu,pstate \
  --format=csv >"$OUT/03-query-csv-idle.csv"

# Hold the 4080 at load while we snapshot.
python3 - <<'PY' &
import json, urllib.request
body = json.dumps({
    "prompt": "测试数据0123456789。" * 400,
    "n_predict": 256,
    "temperature": 0,
    "cache_prompt": False,
}).encode()
req = urllib.request.Request(
    "http://127.0.0.1:8081/completion",
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=90).read()
except Exception as e:
    print(e)
PY
LOAD_PID=$!
sleep 3
nvidia-smi >"$OUT/04-smi-load.txt"
nvidia-smi -q >"$OUT/05-query-load.txt"
nvidia-smi --query-gpu=name,uuid,serial,vbios_version,pci.bus_id,pcie.link.gen.max,pcie.link.gen.current,pcie.link.width.max,pcie.link.width.current,memory.total,memory.used,clocks.gr,clocks.mem,clocks.max.gr,clocks.max.mem,power.limit,power.draw,temperature.gpu,fan.speed,utilization.gpu,pstate \
  --format=csv >"$OUT/06-query-csv-load.csv"
wait "$LOAD_PID" || true
date '+%Y-%m-%d %H:%M:%S %z' >"$OUT/WHEN.txt"
echo "WROTE $OUT"
ls -l "$OUT"
