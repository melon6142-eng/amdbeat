# Qwen3.8-27B (dense): R9700 vs NVIDIA, from public data (collected 2026-10-21)

Every number below comes from the linked source. Results were measured on different hosts, builds and workloads, so treat them as reference points, not a controlled ranking.
"SUB" = the substitute model Qwen3.6-27B, used where there is no Qwen3.8-27B data.

## Ours (R9700 32GB, llama.cpp b10698 Vulkan, UD-Q6_K, fa on, q8_0 KV, c=1)
| pp512 | pp8192 | tg128 (no spec) | MTP n=3 code | MTP n=3 prose |
|---|---|---|---|---|
| 872 | 798 | 24.6 | 58.4 (acc 0.758) | 41.2 (acc 0.434) |

## NVIDIA data points
| GPU | Model | Engine | Quant | Prefill tok/s (@len) | Decode tok/s | Spec/MTP | Conc. | Source |
|---|---|---|---|---|---|---|---|---|
| RTX 5090 | 3.8-27B | llama.cpp b10538 | UD-Q6_K, q8_0 KV, 131k ctx | 2289 | 155 | ngram-mod | 1 | [1] |
| RTX 5090 | 3.8-27B | llama.cpp b10538 | UD-Q6_K, q8_0 KV | 1717 | 150 | draft-mtp + ngram-mod | 1 | [1] |
| RTX 5090 | 3.8-27B | llama.cpp | UD-Q4_K_XL, q4_0 KV | 1797 | 138 | draft-mtp | 1 | [1] |
| RTX 5090 | 3.8-27B | llama.cpp b10448 CUDA | Q4_K_M | – | 73.6 off / 133.6 MTP n=3 (acc 0.674) | MTP n=1..5 | 1 | [2] |
| RTX 5090 | 3.8-27B | llama.cpp | Q4_K_M | 3750 @4k, 3593 @8k, 1146 @32k, 461 @128k | 74.8 @4k, 52.2 @8k, 29.0 @32k, 22.8 @128k | no | 1 | [3] |
| RTX 5090 | 3.8-27B | llama.cpp 9725a31 | Q4_K_M | – (TTFT 118 ms, 114-token prompt) | 65.7 | no | 1 | [4] |
| RTX 4090 | 3.8-27B | llama.cpp | Q4_K_M | 2963 @4k, 2854 @8k, 2367 @32k | 46.2 @4k, 45.5 @8k, 42.2 @32k | no | 1 | [3] |
| RTX 4090 | 3.8-27B | llama.cpp df18bee | Q4_K_M | 1915 (3.2k prompt) | 43.1 | no | 1 | [4] |
| RTX 3090 | 3.8-27B | llama.cpp | Q4_K_M | ~1300 @4k | 40.3 @4k | no | 1 | [3] |
| RTX 3090 | 3.8-27B | llama.cpp 8c2134a | Q4_K_M | 1104 (3.2k prompt) | 37.7 | no | 1 | [4] |
| RTX 5090 | SUB 3.6-27B | llama.cpp CUDA | **Q6_K** | – | **46.4** @8k ctx | no | 1 | [5] |
| RTX 5090 | SUB 3.6-27B | llama.cpp CUDA | Q5_K_M | – | 58.7 | no | 1 | [5] |
| RTX 5090 | SUB 3.6-27B | vLLM | NVFP4 | 7460 | 92 | MTP | 1 | [5] |
| H100 SXM | SUB 3.6-27B | llama.cpp CUDA | Q8_0 | – | 60.2 | no | 1 | [5] |
| H100 SXM | SUB 3.6-27B | llama.cpp CUDA | Q4_K_M | – | 68.1 | no | 1 | [5] |
| H100 PCIe | SUB 3.6-27B | llama.cpp CUDA | Q8_0 / Q4_K_M | – | 44.8 / 52.7 | no | 1 | [5] |
| A100 40GB | SUB 3.6-27B | llama.cpp CUDA | Q8_0 / Q4_K_M | – | 34.1 / 42.4 | no | 1 | [5] |
| H100 | SUB 3.6-27B | vLLM 0.25.1 | FP8 channelwise | – | 465 aggregate | ? | 8 | [6] |
| A100 80GB | SUB 3.6-27B | vLLM | FP8 (emulated), FP8 KV | – | 43 single / 177 aggregate @c8 | MTP K=3 | 1 / 8 | [7] |
| 2x A100 | SUB 3.6-27B | vLLM | (BF16 weights implied) | 24k-token prompt in ~7 s total | 47.5 off; 85.0 MTP (BF16 KV); 83.0 MTP×4 (2048 out) | MTP 2/4 | 1 | [8] |
| 2x RTX PRO 6000 | SUB 3.6-27B | vLLM (Repne fork) | FP8 W8A8 | – | 117 single; 2084 aggregate @c32 | MTP 3 | 1 / 32 | [9] |
| DGX Spark | SUB 3.6-27B | vLLM | NVFP4 | – | 37.3 | MTP 3 | 1 | [5] |

Not found: a Qwen3.8-27B DGX Spark number, or a single-GPU RTX PRO 6000 Q6 number.

## Like-for-like takeaways (Q6, llama.cpp, c=1)
- No spec: RTX 5090 Q6_K ≈ 46.4 tok/s (SUB) vs R9700 24.6 → 5090 ≈ **1.9x**. That fits the bandwidth ratio (1.79 vs 0.64 TB/s ≈ 2.8x on paper).
- Spec on: RTX 5090 UD-Q6_K at 150–155 tok/s [1] vs R9700 MTP 58.4 code → about 2.6x. That 5090 number used ngram-mod with an unknown workload, so it is likely inflated by repetitive output.
- Prefill: the 5090 gives ~1.7–2.3k [1] at UD-Q6_K and 3.6k @8k at Q4_K_M [3]; the 4090 gives 2.85k @8k Q4_K_M [3]. R9700 gives 798 @8k → NVIDIA is **2–4.5x** faster at prefill.
- Q4_K_M without spec puts the 3090 (37–40) and 4090 (43–46) above our Q6 24.6, but the quant differs. Run R9700 Q4_K_M to get a fair comparison.
- A100 40GB at Q8_0 gives 34.1 (SUB). At a heavier quant it is still faster than R9700 at Q6.

## Sources
1. https://llamabench.ai/?mode=tune&model=qwen3-8-27b
2. https://huggingface.co/Qwen/Qwen3.8-27B/discussions/112
3. https://www.hardware-corner.net/qwen3-8-27b-hardware-tests/
4. https://llm-speed.com/m/qwen3-8-27b
5. https://tokenmark.app/model/Qwen3.6-27B (aggregator; each row links to its original source)
6. https://runinfra.ai/catalog/qwen3-6-27b-fp8cd-v3-mlponly-h100-vllm
7. https://www.reddit.com/r/LocalLLaMA/comments/1ubxmek/a100_slow_qwen3627bfp8/
8. https://juejin.cn/post/7641794682348601363
9. https://github.com/jcartu/qwen36-27b-blackwell-inference-study
