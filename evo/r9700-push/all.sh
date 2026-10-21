#!/bin/bash
until grep -q ALLDONE ~/logs/m1021-build.log; do sleep 20; done
PF=~/logs/serve-qwen38-27b-ud-q6k.pid; kill $(cat $PF) 2>/dev/null; for i in $(seq 1 30); do ss -tnl | grep -q :8216 || break; sleep 1; done; sleep 3
~/r9700-push/bench.sh
V0=~/opt/unsloth-llama-b10698-mix-vulkan; V1=~/code/llama.cpp-m1021/build-vk/bin; H1=~/code/llama.cpp-m1021/build-hip/bin
M=~/r9700-push/mtp.sh
$M vk-old-n3 $V0 Vulkan0 --spec-draft-n-max 3
$M vk-new-n3 $V1 Vulkan0 --spec-draft-n-max 3
$M vk-new-n4p6 $V1 Vulkan0 --spec-draft-n-max 4 --spec-draft-p-min 0.6
$M vk-new-n6p75 $V1 Vulkan0 --spec-draft-n-max 6 --spec-draft-p-min 0.75
$M hip-new-n3 $H1 ROCm0 --spec-draft-n-max 3
$M hip-new-n4p6 $H1 ROCm0 --spec-draft-n-max 4 --spec-draft-p-min 0.6
echo MTPDONE >> ~/r9700-push/mtp.txt
rm -f $PF; ~/bin/serve-qwen38-27b-ud-q6k.sh
for i in $(seq 1 240); do curl -s --max-time 1 localhost:8216/v1/models | grep -q q4kxl && break; sleep 1; done
echo "RESTORED $(curl -s localhost:8216/v1/models | grep -o qwen3.8-27b-ud-q4kxl-mtp | head -1) 8217=$(curl -s -o /dev/null -w %{http_code} localhost:8217/health)" >> ~/r9700-push/mtp.txt
