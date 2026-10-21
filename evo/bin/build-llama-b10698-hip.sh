#!/bin/bash
set -e
cd ~/code/llama.cpp-b10698
export PATH=/opt/rocm/bin:$PATH ROCM_PATH=/opt/rocm
HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build-hip -G Ninja -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1201 -DGPU_TARGETS=gfx1201 -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF
nice -n 15 cmake --build build-hip -j 8 --target llama-server llama-bench
echo BUILD_DONE
