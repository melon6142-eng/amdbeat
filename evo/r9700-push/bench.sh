#!/bin/bash
# llama-bench sweep. Assumes 8216 down. Never touches 8217.
M=~/models/gguf/Qwen3.8-27B/Qwen3.8-27B-UD-Q4_K_XL.gguf
O=~/r9700-push/bench.txt
VKOLD=~/opt/unsloth-llama-b10698-mix-vulkan; VKNEW=~/code/llama.cpp-m1021/build-vk/bin
HIPOLD=~/code/llama.cpp-master/build-hip/bin; HIPNEW=~/code/llama.cpp-m1021/build-hip/bin
run(){ tag=$1; dir=$2; shift 2; echo "### $tag $(date +%T)" >> $O
  ( cd $dir; LD_LIBRARY_PATH=$dir:$LD_LIBRARY_PATH timeout 1200 env $ENVX ./llama-bench -m $M -ngl 99 -fa 1 -p 512,4096 -n 128 -r 3 -o md "$@" ) 2>&1 | grep -E "^\|" >> $O; }
ENVX="GGML_VK_VISIBLE_DEVICES=0" run vk-old $VKOLD -dev Vulkan0
ENVX="GGML_VK_VISIBLE_DEVICES=0" run vk-new $VKNEW -dev Vulkan0
ENVX="GGML_VK_VISIBLE_DEVICES=0" run vk-new-ub2048 $VKNEW -dev Vulkan0 -ub 2048 -b 4096
ENVX="GGML_VK_VISIBLE_DEVICES=0 RADV_PERFTEST=sam" run vk-new-sam $VKNEW -dev Vulkan0
ENVX="HIP_VISIBLE_DEVICES=0" run hip-old $HIPOLD
ENVX="HIP_VISIBLE_DEVICES=0" run hip-new $HIPNEW
ENVX="HIP_VISIBLE_DEVICES=0" run hip-new-ub1024 $HIPNEW -ub 1024 -b 4096
ENVX="HIP_VISIBLE_DEVICES=0" run hip-new-ub2048 $HIPNEW -ub 2048 -b 4096
ENVX="HIP_VISIBLE_DEVICES=0" run hip-new-q8kv $HIPNEW -ctk q8_0 -ctv q8_0
ENVX="HIP_VISIBLE_DEVICES=0 GGML_CUDA_FORCE_MMQ=1" run hip-new-mmq $HIPNEW
ENVX="HIP_VISIBLE_DEVICES=0" run hip-new-mmap0 $HIPNEW -mmp 0
echo DONE >> $O
