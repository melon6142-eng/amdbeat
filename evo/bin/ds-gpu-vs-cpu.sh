#!/bin/bash
set -e
echo ===meminfo===
grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo
echo ===cmdline===
tr " " "\n" < /proc/cmdline | grep -E "gtt|ttm|amdgpu" || true
echo ===drm===
python3 - <<'PY'
from pathlib import Path
for d in sorted(Path("/sys/class/drm").glob("card*/device")):
    tot = d / "mem_info_vram_total"
    if not tot.exists():
        continue
    print("CARD", d)
    print("vendor", (d/"vendor").read_text().strip(), "device", (d/"device").read_text().strip())
    for n in ["mem_info_vram_total","mem_info_vram_used","mem_info_vis_vram_total","mem_info_vis_vram_used","mem_info_gtt_total","mem_info_gtt_used"]:
        f = d/n
        if f.exists():
            v = int(f.read_text())
            print(f"{n} {v} ({v/1024**3:.2f} GiB)")
    busy = d/"gpu_busy_percent"
    if busy.exists():
        print("busy", busy.read_text().strip())
PY
echo ===llama===
pid=520642
if [ -d /proc/$pid ]; then
  ps -p $pid -o pid,pcpu,pmem,rss,vsz,nlwp
  python3 - <<PY
from pathlib import Path
s = Path("/proc/520642/smaps").read_text(errors="replace")
rss=pss=swap=0
for line in s.splitlines():
    if line.startswith("Rss:"): rss += int(line.split()[1])
    elif line.startswith("Pss:"): pss += int(line.split()[1])
    elif line.startswith("Swap:"): swap += int(line.split()[1])
print(f"rss_gb={rss/1024/1024:.2f} pss_gb={pss/1024/1024:.2f} swap_gb={swap/1024/1024:.2f}")
PY
else
  echo "llama pid gone"
fi
echo ===log===
python3 - <<'PY'
from pathlib import Path
text = (Path.home()/"logs/serve-deepseek-q3-amd.log").read_text(errors="replace")
for line in text.splitlines():
    low = line.lower()
    if "resolve_fused" in low:
        continue
    if any(k in low for k in ("buffer size", "offloaded", "load_tensors", "model size", "n_params", "cpu0", "vulkan1", "host buffer", "ggml_gallocr", "sched", "device_count", "repeating")):
        print(line[:320])
PY
echo ===busy_loop===
for i in 1 2 3 4 5; do
  echo $(date +%T) busy=$(cat /sys/class/drm/card1/device/gpu_busy_percent) power_uW=$(cat /sys/class/drm/card1/device/hwmon/hwmon*/power1_average 2>/dev/null | head -1)
  sleep 0.5
done
