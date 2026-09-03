#!/usr/bin/env bash
# evo-4080-egpu-safe-ramp.sh
#
# Staged power-limit ramp for ZOTAC RTX 4080 eGPU (OCuLink) on EVO-X3.
# Goal: prove stable low power — NOT max performance.
#
# HARD RULES (enforced):
#   1) Never run full-load / 320W / stress / furmark / gpu-burn style benches.
#   2) Without confirmed PSU wattage (550 vs 800), refuse any -pl > 250.
#   3) Refuse any -pl > 250 unless PSU_WATTAGE is set and >= 750 (treat 800 as OK).
#   4) Default start is idle check only. Load steps require --step N explicitly.
#   5) Abort immediately on Xid / NVRM / disappear / user STOP file.
#
# Usage:
#   # physical checklist first (human): PSU label + 12VHPWR seat
#   ./evo-4080-egpu-safe-ramp.sh status
#   ./evo-4080-egpu-safe-ramp.sh record-psu --watts 550 --rail12-a 45.8   # example
#   ./evo-4080-egpu-safe-ramp.sh set-pl 150
#   ./evo-4080-egpu-safe-ramp.sh light-load --seconds 300   # only after set-pl 150
#   ./evo-4080-egpu-safe-ramp.sh set-pl 180
#   ... 200 → 220 → 250 ...
#   # NEVER: set-pl 320 / full / bench
#
set -euo pipefail

STATE_DIR="${STATE_DIR:-$HOME/.local/state/evo-4080-egpu}"
PSU_FILE="$STATE_DIR/psu.json"
STOP_FILE="$STATE_DIR/STOP"
LOG_DIR="${LOG_DIR:-$HOME/logs/evo-4080-egpu}"
mkdir -p "$STATE_DIR" "$LOG_DIR"

MAX_WITHOUT_PSU=250
ABS_HARD_CAP=250          # until PSU_WATTAGE confirmed >= 750
ABS_HARD_CAP_WITH_PSU=300 # seller-claim 800W path: allow up to 300; still never auto 320+
FORBIDDEN_PL=320          # full TGP / burn territory — refuse

die(){ echo "ERROR: $*" >&2; exit 1; }
need_cmd(){ command -v "$1" >/dev/null || die "missing $1"; }

ts(){ date -u +%Y%m%dT%H%M%SZ; }
log(){ echo "[$(date -Is)] $*"; }

check_stop(){
  if [[ -f $STOP_FILE ]]; then
    die "STOP file present: $STOP_FILE — clear it only after you inspect hardware"
  fi
}

psu_watts(){
  if [[ -f $PSU_FILE ]]; then
    python3 - "$PSU_FILE" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get("watts") or 0)
PY
  else
    echo 0
  fi
}

assert_pl_allowed(){
  local pl=$1
  local watts
  watts=$(psu_watts)
  [[ $pl =~ ^[0-9]+$ ]] || die "power limit must be integer watts"
  if (( pl >= FORBIDDEN_PL )); then
    die "refusing ${pl}W: >= ${FORBIDDEN_PL}W looks like full-TGP territory. This script never auto-runs 320W/full load."
  fi
  if (( watts < 750 )); then
    if (( pl > MAX_WITHOUT_PSU )); then
      die "PSU wattage not confirmed (need record-psu). Refusing -pl ${pl} (> ${MAX_WITHOUT_PSU}). Record label first."
    fi
    # even with unknown PSU, hard-cap at 250
    if (( pl > ABS_HARD_CAP )); then
      die "hard cap ${ABS_HARD_CAP}W until PSU confirmed"
    fi
  else
    if (( pl > ABS_HARD_CAP_WITH_PSU )); then
      die "even with ${watts}W PSU recorded, this script caps at ${ABS_HARD_CAP_WITH_PSU}W (no full-load path)"
    fi
  fi
}

gpu_present(){
  lspci -nn 2>/dev/null | grep -qi '10de:' && return 0
  return 1
}

cmd_status(){
  check_stop
  echo "=== host ==="
  hostname; uname -r; date -Is
  echo "=== PSU record ==="
  if [[ -f $PSU_FILE ]]; then cat "$PSU_FILE"; else echo "(none — record-psu REQUIRED before >250W)"; fi
  echo "=== PCIe NVIDIA ==="
  lspci -nn | grep -iE '10de|NVIDIA' || echo "NO NVIDIA DEVICE ON BUS"
  echo "=== nvidia-smi ==="
  if command -v nvidia-smi >/dev/null; then
    nvidia-smi 2>&1 | head -40 || true
  else
    echo "nvidia-smi missing"
  fi
  echo "=== recent kernel nvidia/pcie errors ==="
  if command -v journalctl >/dev/null; then
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'NVRM|Xid|nvidia|pcie.*(error|fault)|AER' | tail -30 || true
  else
    dmesg 2>/dev/null | grep -Ei 'NVRM|Xid|nvidia|pcie.*(error|fault)|AER' | tail -30 || true
  fi
  echo "=== empty OCuLink-ish bridges ==="
  for d in /sys/bus/pci/devices/0000:00:01.2 /sys/bus/pci/devices/0000:00:02.2 /sys/bus/pci/devices/0000:00:03.2; do
    [[ -d $d ]] || continue
    echo -n "$d speed=$(cat "$d/current_link_speed" 2>/dev/null) width=$(cat "$d/current_link_width" 2>/dev/null) children="
    shopt -s nullglob
    kids=("$d"/0000:*)
    echo "${#kids[@]}"
  done
}

cmd_record_psu(){
  local watts="" rail="" note=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --watts) watts=$2; shift 2;;
      --rail12-a) rail=$2; shift 2;;
      --note) note=$2; shift 2;;
      *) die "unknown arg $1";;
    esac
  done
  [[ -n $watts ]] || die "record-psu --watts <N> [--rail12-a <A>] [--note '...']"
  [[ $watts =~ ^[0-9]+$ ]] || die "watts must be int"
  python3 - "$PSU_FILE" "$watts" "$rail" "$note" <<'PY'
import json,sys,datetime
path,watts,rail,note=sys.argv[1],int(sys.argv[2]),sys.argv[3],sys.argv[4]
obj={
  "watts": watts,
  "rail12_a": float(rail) if rail else None,
  "note": note or None,
  "recorded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "source": "human label read — agent must not invent this",
}
json.dump(obj, open(path,"w"), indent=2)
print("wrote", path)
print(json.dumps(obj, indent=2))
PY
  if (( watts < 750 )); then
    echo "NOTE: recorded ${watts}W → script will still refuse -pl > ${MAX_WITHOUT_PSU}."
  else
    echo "NOTE: recorded ${watts}W → still capped at ${ABS_HARD_CAP_WITH_PSU}W; no full-load path."
  fi
}

cmd_set_pl(){
  check_stop
  local pl=${1:-}
  [[ -n $pl ]] || die "set-pl <watts>"
  assert_pl_allowed "$pl"
  gpu_present || die "no NVIDIA on PCIe — power eGPU / seat OCuLink+12VHPWR first, then status"
  need_cmd nvidia-smi
  nvidia-smi >/dev/null || die "nvidia-smi cannot talk to driver"
  log "setting persistence + power limit ${pl}W"
  sudo nvidia-smi -pm 1 >/dev/null
  sudo nvidia-smi -pl "$pl"
  nvidia-smi --query-gpu=name,power.limit,power.draw,temperature.gpu,clocks.sm,pcie.link.gen.current,pcie.link.width.current --format=csv
  # snapshot kernel errors after change
  journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'NVRM|Xid' | tail -5 || true
}

# Very light CUDA touch: allocate small tensor / vector add — NOT a burn.
# Requires python3 + torch OR falls back to nvidia-smi dmon idle soak.
cmd_light_load(){
  check_stop
  local seconds=300
  while [[ $# -gt 0 ]]; do
    case $1 in
      --seconds) seconds=$2; shift 2;;
      *) die "unknown $1";;
    esac
  done
  (( seconds <= 900 )) || die "light-load max 900s — this is not a long soak bench"
  gpu_present || die "no GPU"
  need_cmd nvidia-smi
  local pl
  pl=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | head -1 | tr -d ' ')
  assert_pl_allowed "${pl%.*}"
  log "light-load ${seconds}s under current PL=${pl}W (no full burn)"
  local out="$LOG_DIR/light-$(ts).log"
  (
    echo "start $(date -Is) PL=$pl seconds=$seconds"
    nvidia-smi --query-gpu=name,power.limit,power.draw,temperature.gpu,clocks.sm --format=csv
    if python3 - <<'PY'
import sys
try:
    import torch
    if not torch.cuda.is_available():
        sys.exit(2)
    print("torch", torch.__version__, torch.cuda.get_device_name(0))
except Exception as e:
    print("no-torch", e)
    sys.exit(3)
PY
    then
      python3 - "$seconds" <<'PY'
import sys, time, torch
sec = int(sys.argv[1])
dev = torch.device("cuda")
# tiny matmul loop — keeps power modest under -pl
a = torch.randn(2048, 2048, device=dev)
b = torch.randn(2048, 2048, device=dev)
t0 = time.time()
n = 0
while time.time() - t0 < sec:
    _ = a @ b
    torch.cuda.synchronize()
    n += 1
    if n % 20 == 0:
        time.sleep(0.05)  # duty-cycle down; not a burn
print("iters", n)
PY
    elif command -v nvcc >/dev/null; then
      log "torch unavailable — using duty-cycled nvcc SAXPY (not a burn)"
      local cu="$STATE_DIR/light_saxpy.cu"
      local bin="$STATE_DIR/light_saxpy"
      cat >"$cu" <<'CUDA'
#include <cstdio>
#include <cuda_runtime.h>
#include <unistd.h>
#include <ctime>
__global__ void saxpy(int n, float a, const float* x, float* y) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) y[i] = a * x[i] + y[i];
}
int main(int argc, char** argv) {
  int sec = argc > 1 ? atoi(argv[1]) : 60;
  const int N = 1 << 24; // 16M floats ~64MB each
  float *x, *y;
  cudaMalloc(&x, N * sizeof(float));
  cudaMalloc(&y, N * sizeof(float));
  cudaMemset(x, 1, N * sizeof(float));
  cudaMemset(y, 2, N * sizeof(float));
  time_t t0 = time(nullptr);
  long long n = 0;
  while (time(nullptr) - t0 < sec) {
    saxpy<<<(N + 255) / 256, 256>>>(N, 2.0f, x, y);
    cudaDeviceSynchronize();
    n++;
    if ((n % 50) == 0) usleep(50000); // duty-cycle down
  }
  printf("iters %lld\n", n);
  cudaFree(x); cudaFree(y);
  return 0;
}
CUDA
      nvcc -O2 -o "$bin" "$cu"
      # parallel dmon sample while compute runs
      ( timeout "$seconds" nvidia-smi dmon -s puct -d 2 || true ) &
      local dmon_pid=$!
      "$bin" "$seconds"
      wait "$dmon_pid" 2>/dev/null || true
    else
      log "torch/nvcc unavailable — idle soak with nvidia-smi dmon only (no compute)"
      timeout "$seconds" nvidia-smi dmon -s puct -d 2 || true
    fi
    echo "end $(date -Is)"
    nvidia-smi --query-gpu=name,power.limit,power.draw,temperature.gpu,clocks.sm --format=csv
    # NVIDIA Xid only — do NOT match Realtek eth "XID 689"
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'NVRM:.*Xid|NVRM:.*error|nvidia.*(fault|AER)|pcieport.*(AER|error)' | tail -40 || true
  ) | tee "$out"
  log "wrote $out"
  if grep -Ei 'NVRM:.*Xid|NVRM:.*error|nvidia.*(fault|AER)|pcieport.*(AER|Uncorrected)' "$out" >/dev/null; then
    touch "$STOP_FILE"
    die "errors seen — STOP armed. Do not raise power limit."
  fi
}

cmd_rescan(){
  check_stop
  log "PCI rescan"
  sudo sh -c 'echo 1 > /sys/bus/pci/rescan'
  sleep 2
  cmd_status
}

usage(){
  cat <<EOF
Usage: $0 <status|record-psu|set-pl|light-load|rescan|arm-stop|clear-stop>

HARD BLOCKS:
  - no automatic 320W / full TGP / gpu-burn / furmark
  - without record-psu: refuse -pl > ${MAX_WITHOUT_PSU}
  - with PSU>=750W recorded: still refuse -pl > ${ABS_HARD_CAP_WITH_PSU}
  - refuse any -pl >= ${FORBIDDEN_PL}

Physical first (YOU):
  1) Read PSU label watts + 12V amp → record-psu
  2) Confirm 12VHPWR fully seated + 8-pin chain
  3) Power eGPU enclosure ON, then: $0 rescan && $0 status
  4) Only then: set-pl 150 → light-load → step 180/200/220/250
EOF
}

cmd=${1:-}
shift || true
case $cmd in
  status) cmd_status ;;
  record-psu) cmd_record_psu "$@" ;;
  set-pl) cmd_set_pl "$@" ;;
  light-load) cmd_light_load "$@" ;;
  rescan) cmd_rescan ;;
  arm-stop) touch "$STOP_FILE"; echo "armed $STOP_FILE" ;;
  clear-stop) rm -f "$STOP_FILE"; echo "cleared STOP" ;;
  ""|-h|--help) usage ;;
  full|bench|burn|320|stress)
    die "refusing '$cmd': full-load path is intentionally unimplemented"
    ;;
  *) usage; die "unknown command: $cmd" ;;
esac
