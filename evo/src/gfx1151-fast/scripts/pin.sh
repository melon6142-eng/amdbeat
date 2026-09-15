#!/usr/bin/env bash
# Snapshot the EVO box. No model load.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT:-$ROOT/results/pin-$STAMP.json}"
mkdir -p "$(dirname "$OUT")"

card=""
for d in /sys/class/drm/card*/device; do
  [[ -f $d/mem_info_vram_total ]] || continue
  card=$d
done

python3 - "$OUT" "$card" <<'PY'
import json, os, subprocess, sys, time
out, card = sys.argv[1], sys.argv[2]

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        return ""

def gi(path):
    try:
        return round(int(open(path).read()) / 1024**3, 2)
    except Exception:
        return None

def sha(path):
    if not os.path.isfile(path):
        return None
    return sh(f"sha256sum {path}").split()[0] if os.path.getsize(path) < 200*(1024**3) else "skip-large"

pin = {
    "stamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "host": sh("hostname"),
    "kernel": sh("uname -r"),
    "cmdline_amd": [x for x in open("/proc/cmdline").read().split() if any(k in x for k in ("amdgpu", "gtt", "ttm", "iommu"))],
    "nproc": sh("nproc"),
    "governor": sh("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
    "dpm": sh(f"cat {card}/power_dpm_force_performance_level") if card else "",
    "vram_total_gib": gi(f"{card}/mem_info_vram_total") if card else None,
    "gtt_total_gib": gi(f"{card}/mem_info_gtt_total") if card else None,
    "vram_used_gib": gi(f"{card}/mem_info_vram_used") if card else None,
    "gtt_used_gib": gi(f"{card}/mem_info_gtt_used") if card else None,
    "mesa": sh("dpkg-query -W -f='${Version}' mesa-vulkan-drivers"),
    "rocm": sh("cat /opt/rocm/.info/version"),
    "trees": {},
    "model": {
        "path": os.path.expanduser("$MODELS_DIR/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf"),
        "sha256": "552a7a162f6a620c3aa0850d070086bc2b95094e0a4e8b860694c7f212cb59d8",
        "bytes": os.path.getsize(os.path.expanduser("$MODELS_DIR/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf")) if os.path.isfile(os.path.expanduser("$MODELS_DIR/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf")) else 0,
    },
}
for name, path in {
    "rocmfpx": os.path.expanduser("~/code/llama.cpp-rocmfpx"),
    "strix": os.path.expanduser("~/src/strix-llama.cpp"),
}.items():
    if os.path.isdir(os.path.join(path, ".git")):
        pin["trees"][name] = {
            "path": path,
            "head": sh(f"git -C {path} rev-parse HEAD"),
            "oneline": sh(f"git -C {path} log -1 --oneline"),
            "remote": sh(f"git -C {path} remote get-url origin"),
        }
open(out, "w").write(json.dumps(pin, indent=2) + "\n")
print(out)
PY
