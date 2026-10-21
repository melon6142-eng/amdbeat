#!/bin/bash
# R9700 27B prefill sweep. Stops 8216, benches, ALWAYS restores 8216.
M=${MODELS_DIR:-$HOME/models}/gguf/Qwen3.8-27B/Qwen3.8-27B-UD-Q4_K_XL.gguf
L=$HOME/logs/sweep; mkdir -p $L
restore(){ cd ~; [ -f ~/bin/serve-qwen38-27b-ud-q6k.sh.final ] && cp ~/bin/serve-qwen38-27b-ud-q6k.sh.final ~/bin/serve-qwen38-27b-ud-q6k.sh
  ss -tnl | grep -q ":8216 " || ~/bin/serve-qwen38-27b-ud-q6k.sh; echo "$(date -Is) RESTORED" >> $L/timeline.txt; }
trap restore EXIT
for i in $(seq 1 120); do grep -q BUILD_OK ~/logs/build-hip-wmma.log && break; grep -qE "Error|error:" ~/logs/build-hip-wmma.log && break; sleep 15; done
until curl -s localhost:8216/slots | python3 -c "import sys,json; sys.exit(any(x[\"is_processing\"] for x in json.load(sys.stdin)))"; do sleep 20; done
kill $(cat ~/logs/serve-qwen38-27b-ud-q6k.pid) 2>/dev/null; sleep 8; echo "$(date -Is) 8216 DOWN" >> $L/timeline.txt
A="-m $M -ngl 99 -fa 1 -p 512,4096 -n 128 -r 2 -b 4096 -ub 512,1024,2048,4096 -o md"
V=$HOME/opt/unsloth-llama-b10698-mix-vulkan
( cd $V; LD_LIBRARY_PATH=$V ./llama-bench $A -dev Vulkan0 > $L/vk-coopmat-on.md 2>$L/vk-coopmat-on.err )
( cd $V; GGML_VK_DISABLE_COOPMAT=1 GGML_VK_DISABLE_COOPMAT2=1 LD_LIBRARY_PATH=$V ./llama-bench $A -dev Vulkan0 > $L/vk-coopmat-off.md 2>$L/vk-coopmat-off.err )
for b in b10698:$HOME/code/llama.cpp-b10698/build-hip/bin wmma:$HOME/code/llama.cpp-b10698/build-hip-wmma/bin master:$HOME/code/llama.cpp-master/build-hip/bin; do n=${b%%:*}; d=${b#*:}
  [ -x $d/llama-bench ] || continue
  ( cd $d; HIP_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=$d ./llama-bench $A > $L/hip-$n.md 2>$L/hip-$n.err )
  ( cd $d; ROCBLAS_USE_HIPBLASLT=1 HIP_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=$d ./llama-bench $A > $L/hip-$n-blaslt.md 2>$L/hip-$n-blaslt.err )
  echo "$(date -Is) $n done" >> $L/timeline.txt
done
echo SWEEP_DONE >> $L/timeline.txt
