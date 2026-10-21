# Verified GGUF inventory (HF API, 2026-10-21 Asia/Shanghai)

Sizes = LFS `size` from `GET /api/models/<id>/tree/main`. GiB = bytes / 1024³.

Base model: `Qwen/Qwen3.8-27B` sha `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`  
Arch (from unsloth `config.json`): `qwen3_5` / GGUF arch `qwen35`, 64 layers, 16 full-attn + 48 Gated DeltaNet, `num_key_value_heads=4`, `head_dim=256`, native ctx 262144.

## unsloth/Qwen3.8-27B-GGUF

- repo sha: `4ca720788d1e01f1bff70c033e0d0028fd02e502`
- note: **no** classic `Q4_K_M` / `Q5_K_M` / `Q6_K` filenames — Dynamic (UD-*) + `Q4_0`/`Q4_1`/`Q8_0` only.

| file | bytes | GiB |
|---|---:|---:|
| Qwen3.8-27B-Q4_0.gguf | 16056478688 | 14.95 |
| Qwen3.8-27B-Q4_1.gguf | 17540705248 | 16.34 |
| Qwen3.8-27B-Q8_0.gguf | 29047086048 | 27.05 |
| Qwen3.8-27B-UD-IQ1_S.gguf | 6192222208 | 5.77 |
| Qwen3.8-27B-UD-IQ1_M.gguf | 6729166848 | 6.27 |
| Qwen3.8-27B-UD-IQ2_XXS.gguf | 7266070528 | 6.77 |
| Qwen3.8-27B-UD-IQ2_S.gguf | 8371970048 | 7.80 |
| Qwen3.8-27B-UD-IQ3_XXS.gguf | 10934860704 | 10.18 |
| Qwen3.8-27B-UD-IQ3_S.gguf | 12040883104 | 11.21 |
| Qwen3.8-27B-UD-IQ4_XS.gguf | 14252845984 | 13.27 |
| Qwen3.8-27B-UD-Q2_K_XL.gguf | 9828981664 | 9.15 |
| Qwen3.8-27B-UD-Q3_K_XL.gguf | 13146393504 | 12.24 |
| Qwen3.8-27B-UD-Q4_K_S.gguf | 15358213024 | 14.30 |
| Qwen3.8-27B-UD-Q4_K_M.gguf | 16464440224 | 15.33 |
| Qwen3.8-27B-UD-Q4_K_XL.gguf | 17559178144 | 16.35 |
| Qwen3.8-27B-UD-Q5_K_S.gguf | 18665753504 | 17.38 |
| Qwen3.8-27B-UD-Q5_K_M.gguf | 19771509664 | 18.41 |
| Qwen3.8-27B-UD-Q5_K_XL.gguf | 20876938144 | 19.44 |
| **Qwen3.8-27B-UD-Q6_K.gguf** | **21983677344** | **20.47** |
| Qwen3.8-27B-UD-Q6_K_M.gguf | 23088409504 | 21.50 |
| Qwen3.8-27B-UD-Q6_K_L.gguf | 24193919904 | 22.53 |
| Qwen3.8-27B-UD-Q6_K_XL.gguf | 25299061664 | 23.56 |
| Qwen3.8-27B-UD-Q8_K_L.gguf | 28045695904 | 26.12 |
| Qwen3.8-27B-UD-Q8_K_XL.gguf | 31457991680 | 29.30 |
| MTP/mtp-Qwen3.8-27B-Q4_0.gguf | 1369590656 | 1.28 |
| imatrix_unsloth.gguf | 13642656 | 0.01 |
| mmproj-F16.gguf | 927607488 | 0.86 |
| mmproj-BF16.gguf | 931146432 | 0.87 |

## bartowski/Qwen3.8-27B-GGUF

- repo sha: `87410e7b9a5c21e6ca70c0c9cc5237de909fe621`
- has classic K-quants + IQ imatrix variants.

| file | bytes | GiB |
|---|---:|---:|
| Qwen3.8-27B-Q4_K_S.gguf | 16363513568 | 15.24 |
| **Qwen3.8-27B-Q4_K_M.gguf** | **17442399968** | **16.24** |
| Qwen3.8-27B-Q4_K_L.gguf | 18820703968 | 17.53 |
| Qwen3.8-27B-Q5_K_S.gguf | 19566913248 | 18.22 |
| **Qwen3.8-27B-Q5_K_M.gguf** | **20923877088** | **19.49** |
| Qwen3.8-27B-Q5_K_L.gguf | 21537478240 | 20.06 |
| Qwen3.8-27B-Q6_K_S.gguf | 22857455328 | 21.29 |
| **Qwen3.8-27B-Q6_K.gguf** | **23860565728** | **22.22** |
| Qwen3.8-27B-Q6_K_L.gguf | 24958908128 | 23.24 |
| **Qwen3.8-27B-Q8_0.gguf** | **29116388960** | **27.12** |
| Qwen3.8-27B-IQ2_XXS.gguf | 8881268448 | 8.27 |
| Qwen3.8-27B-IQ2_XS.gguf | 9088526048 | 8.46 |
| Qwen3.8-27B-IQ2_S.gguf | 9684043488 | 9.02 |
| Qwen3.8-27B-IQ2_M.gguf | 10522248928 | 9.80 |
| Qwen3.8-27B-IQ3_XXS.gguf | 12320167648 | 11.47 |
| Qwen3.8-27B-IQ3_XS.gguf | 12799604448 | 11.92 |
| Qwen3.8-27B-IQ3_M.gguf | 14860629728 | 13.84 |
| Qwen3.8-27B-IQ4_XS.gguf | 15475951328 | 14.41 |
| Qwen3.8-27B-IQ4_NL.gguf | 17442399968 | 16.24 |
| Qwen3.8-27B-imatrix.gguf | 13642688 | 0.01 |

## KV footprint (full-attn layers only)

16 full-attn layers × 4 KV heads × 256 dim × 2 (K+V) × 2 B (f16) = **65536 B/token** ≈ 64 KiB/tok.

| ctx | KV (f16) |
|---|---:|
| 8k | 0.50 GiB |
| 16k | 1.00 GiB |
| 32k | 2.00 GiB |
| 64k | 4.00 GiB |
| 128k | 8.00 GiB |
| 262k | 16.00 GiB |

Linear (DeltaNet) state is ~O(1) in sequence length (recurrent); not included above. Scratch/graph overhead typically **+1.5–3 GiB** depending on `-b`/`-ub` — **TODO measure on R9700**.
