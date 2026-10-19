#!/bin/bash
while true; do echo "$(date +%T) avail=$(awk "/MemAvailable/{print int(\$2/1048576)}" /proc/meminfo)G r9700_vram=$(($(cat /sys/class/drm/card0/device/mem_info_vram_used)/1048576))M igpu_gtt=$(($(cat /sys/class/drm/card1/device/mem_info_gtt_used)/1048576))M"; sleep 5; done
