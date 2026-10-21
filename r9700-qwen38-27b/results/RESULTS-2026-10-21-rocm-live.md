# Qwen3.8-27B on R9700 — ROCm master live (2026-10-21, Asia/Shanghai)

Live switch after prefill + MTP A/B. Alias `qwen3.8-27b-ud-q4kxl-mtp`, port `${PORT:-8216}`.

## Live config

| Item | Value |
|---|---|
| Binary | llama.cpp **master** HIP gfx1201 (`build-hip`) |
| Weights | unsloth **UD-Q4_K_XL** + MTP draft **Q4_0** |
| Flags | `-ngl 99 -fa on -c 65536 -b 2048 -ub 2048 -ctk f16 -ctv f16 --jinja --spec-type draft-mtp -ngld all --spec-draft-n-max 3` |
| Alias | `qwen3.8-27b-ud-q4kxl-mtp` |
| VRAM | ~25.4 GiB used |
| Serve script | `evo/bin/serve-qwen38-27b-ud-q6k.sh` (Vulkan backup: `.bak-vulkan-20261021`) |

## Prefill (llama-bench, UD-Q4_K_XL, -fa 1, r2)

| Backend | pp512 | pp4096 | tg128 |
|---|---:|---:|---:|
| Vulkan mix b10698 (coopmat ON) | ~890–916 | ~864–892 | ~28.8 |
| ROCm b10698 HIP | ~1178 | ~1113–1132 | ~27.8 |
| **ROCm master HIP** | **~1294** | **~1280–1295** | **~29.3** |

ROCm master ≈ **+46% prefill** vs live Vulkan mix. rocWMMA / hipBLASLt: no gain on gfx1201. Vulkan coopmat must stay ON (~2.1×).

## MTP decode (chat, max_tokens=256, temp 0, thinking off)

Fair same-prompt compare (before permanent switch):

| Backend | code tok/s (accept) | prose tok/s (accept) |
|---|---|---|
| Vulkan MTP n-max 3 | 73.4 (90.3%) | 56.2 (60.3%) |
| ROCm master MTP n-max 3 | ~71.1 (89.8%) | ~54.8 (60.3%) |
| ROCm master no-MTP | ~29.3 | ~29.3 |

After live switch (`-b/-ub 2048`): code **67.6** (81.6%), prose **47.2** (47.5%). User accepted ~3% decode tradeoff for +46% prefill.

## KL (own BF16→Q8_0 ref, c512×100)

Mean KLD wiki / code (99% KLD code): bartowski Q6_K best → UD-Q6_K → UD-Q5_K_XL → **UD-Q4_K_XL (live)** → UD-Q4_K_M → IQ4_XS.

## Notes

- Earlier same-day table (UD-Q6_K Vulkan) remains in `RESULTS-2026-10-21.md`.
- NVIDIA 5090 reference: Q6_K pp512 ~3100 / tg ~63 → R9700 best still ~2.4× behind prefill.
- Public AMD leaderboard: our ROCm ~1294 pp beats published UD-Q4_K_XL ~1151 (akougkas).
