# R9700 × Qwen3.8-27B UD-Q4_K_XL: stew675 rdna-boosts build (2026-10-21)

This is the live config on our single **Radeon AI PRO R9700 32GB** (gfx1201, ROCm/HIP) as of 2026-10-21.
Serve script: [`../configs/serve-rdna-boosts.sh`](../configs/serve-rdna-boosts.sh).
The flags are the same as the llama.cpp-master ROCm config. Only the binary changed.

```
-ngl 99 -fa on -c 65536 -b 2048 -ub 2048 -ctk f16 -ctv f16 --jinja \
--spec-type draft-mtp -md mtp-Qwen3.8-27B-Q4_0.gguf -ngld all --spec-draft-n-max 3
```

## Building stew675/llama-cpp-rdna-boosts

Source: https://github.com/stew675/llama-cpp-rdna-boosts

> ⚠️ **Beta.** Our tree is at `62ef562` (all 12 rdna-boosts patch blocks applied). Its tree hash **does not match** the tagged release tarball, so treat this as an unofficial build. Keep a stock llama.cpp-master HIP build next to it so you can roll back.

```bash
git clone https://github.com/stew675/llama-cpp-rdna-boosts $HOME/code/rdna-src
cd $HOME/code/rdna-src
cmake -B build-hip -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1201 \
      -DGGML_HIP_ROCWMMA_FATTN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-hip -j --target llama-server llama-bench
```

Roll back by pointing `BIN=` at the stock `llama.cpp-master/build-hip/bin` and restarting.

## Leaderboard: single R9700, Qwen3.8-27B UD-Q4_K_XL

| Metric | **Ours** | Best published we found |
|---|---|---|
| Prefill pp2048 (llama-bench) | **1327** | 1151 ([akougkas](https://akougkas.io/journal/2026/serving-qwen38-27b-on-a-radeon-ai-pro-r9700/), b10687 HIP, q8_0 KV) |
| Decode tg (no MTP) | **30.94** | 26.7 ([akougkas](https://akougkas.io/journal/2026/serving-qwen38-27b-on-a-radeon-ai-pro-r9700/)) |
| MTP chat, code (n-max 3) | **75.4** | 43.3 R9700 row in [sudoingX/qwen38-mtp](https://github.com/sudoingX/qwen38-mtp) (n-max 2); 43.44 on [r/LocalLLM](https://www.reddit.com/r/LocalLLM/comments/1vzcuwa/r9700_32gb_qwen3827b_q4_vs_q6_and_some_mtp_testing/) (Vulkan, n-max 3) |
| MTP chat, prose (n-max 3) | **62.1** | — |

Ours: rdna-boosts HIP build, f16 KV, b/ub 2048. On the same flags, the stock master HIP build reached 61.7 code / 50.9 prose, so rdna-boosts is about **22% faster**.

## Quality and stability A/B (rdna-boosts vs master, temp 0, thinking off)

| Check | Result |
|---|---|
| Fibonacci code | Same output on both builds, passes |
| Korean 3-sentence summary | Same text on both builds |
| Capacitance math (C=ε₀A/d) | Correct, 177 pF |
| 5 small coding tasks (reverse, binary search, JSON keys, 2×2 matmul, gcd) | **5/5 pass** when executed |
| Needle at ~4.5k prompt tokens | Found |
| 512-token generation | Completed |
| 20 sequential requests | **20/20 OK**, 0 crashes, 0 hangs, 0 HTTP 5xx |
| VRAM | ~24.8 GiB / 31.9 GiB |

Spot speeds during the A/B: code 73 → **89** tok/s, prose 59 → **71** tok/s.
**Caveat:** this was a short A/B. There has been no multi-hour soak yet.

## Context probes (ROCm, MTP n=3, 4 slots unified)

| KV type | Context | Result |
|---|---|---|
| f16 | 128k | OK, 30.1 GiB, pp 1062 / tg 50.7 at a 29k prompt |
| f16 | 160k | Loads at 32.5 GiB but crashes on a request |
| f16 | 192k / 256k | Fails |
| q8_0 | 128k / 192k / 224k | 26.6 / 29.8 / 31.4 GiB |
| q8_0 | 256k | Fails at ub 2048. OK at b/ub 1024: 31.7 GiB, pp 1073 / tg 46.2 |
| q4_0 | 256k | OK, 29.0 GiB, pp 1036 / tg 45.6 |
| q4_0 | 512k (YaRN) | Fails (MTP context) |
| q8_0 + `-nkvo` | 1M (YaRN, ub 512) | Loads (29.6 GiB VRAM plus ~40 GB host RAM), pp 390 / tg 6.5. **Not usable.** |

The practical ceiling is the native **262k** with q4_0 KV. With f16 KV, 128k is safe.
