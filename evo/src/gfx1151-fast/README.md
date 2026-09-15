# gfx1151.fast

Single-node Strix Halo arena on **EVO-X3** (Ryzen AI Max+ 395 / Radeon 8060S).

First target: **Qwen3.8-Flash-Next** only. No multi-node, no official frontier.fast
leaderboard. Goal is a reproducible Vulkan vs HIP picture at 8K / 32K / 128K, then
agent loops that keep a patch only when median + correctness both win.

## Score (Lab-Strix)

| Weight | Axis |
| --- | --- |
| 50% | decode tok/s (8K and 32K) |
| 30% | prefill tok/s (32K and 128K) |
| 10% | TTFT |
| 10% | sustained stability (spread + no hang) |

A candidate is rejected if correctness moves or any other workload drops more than 5%.

## 2x2 arms

| Tree | Vulkan/RADV | ROCm/HIP |
| --- | --- | --- |
| stock llama.cpp | not on disk yet | not on disk yet |
| halo-box/strix-llama.cpp | `~/src/strix-llama.cpp` (needs build) | needs build |
| lab (Laurent rocmfpx) | `~/code/llama.cpp-rocmfpx` **current Vulkan path** | Unsloth MIX HIP: **29 GiB visible, cannot hold 88G Flash** |

HIP on this box advertises 120 GiB and reports ~29 GiB free even when sysfs VRAM/GTT
are empty. That is finding 001. Do not treat a missing HIP Flash number as "HIP is slower".

## Model pin

- Target: `$MODELS_DIR/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf`
- SHA256: `552a7a162f6a620c3aa0850d070086bc2b95094e0a4e8b860694c7f212cb59d8`
- Draft: `$MODELS_DIR/gguf/qwen38-flash-mtp/mtp-Qwen3.8-Flash-Next-Q8_0.gguf`

## How to run on EVO

```bash
bash ~/src/gfx1151-fast/scripts/pin.sh
# micro: 512 pp / 128 tg at depth 0, 5 reps
bash ~/src/gfx1151-fast/scripts/bench-micro.sh vulkan-rocmfpx
```

Do not start a second big model while a bench holds the GPU.
