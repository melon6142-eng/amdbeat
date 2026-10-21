#!/bin/bash
cd $HOME/opt/unsloth-llama-b10698-mix-vulkan; export LD_LIBRARY_PATH=$HOME/opt/unsloth-llama-b10698-mix-vulkan
./llama-bench -m $1 -dev Vulkan0 -ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 -p 512,8192 -n 128 -r 3
echo BENCH_DONE
