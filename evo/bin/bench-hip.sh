#!/bin/bash
cd $HOME/code/llama.cpp-b10698/build-hip/bin; export HIP_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=$HOME/code/llama.cpp-b10698/build-hip/bin
./llama-bench -m $1 -ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 -p 512,8192 -n 128 -r 3
echo BENCH_DONE
