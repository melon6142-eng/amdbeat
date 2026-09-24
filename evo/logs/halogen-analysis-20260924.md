# Halogen speedup analysis — EVO (Strix Halo) — 2026-09-24

Read-only inspection of stopped `halogen-flash` (image `ghcr.io/peonist-ai/halogen-flash-server:0.13.4`), weights under `~/halogen-models`, GitHub `peonist-ai/halogen-flash-server`, and local GGUF metadata. **No GPU process was started.** Another job was using `:8080` / GLM; left untouched.

---

## 1. Halogen measured numbers (with sources)

### 1.1 On this box (EVO) — `podman logs halogen-flash`

Parsed **209** `serve_api:` lines from the stopped container’s logs.

| Metric | Value | Notes / source |
|---|---|---|
| Prefill (rates printed as `prefill Xs = Y t/s`) | **mean 1078 t/s, median 1104, range 750–1228** | 66 samples; typical cold prompts ~10k–40k tokens |
| Example cold prefill | **1177 t/s** on prompt 36034 (30.61 s) | `serve_api: mtp … prompt 36034, prefill 30.61s = 1177 t/s` |
| Example cold prefill | **1191 t/s** on prompt 22935 | same log stream |
| Example cold prefill | **1190 t/s** on prompt 40159 | same |
| Decode MTP (n≥64 generated) | **mean 45.5 t/s, median 44.4, range ~25–63** (excl. aborted/near-zero) | 181 samples; includes MTP + prompt-lookup (`pld`) |
| High decode (cached / code-like) | **61.7 t/s** (932 tok, commit 2.96/round, 97.6% prompt cached) | log |
| High decode | **56.7 t/s** (2500 tok, commit 2.63/round, 78% cached) | log |
| Mid decode (long think) | **35.8–41.2 t/s** at 10k–36k prompt | e.g. 38.40 @10371; 41.24 @36034 |
| Speculative efficiency | **commit ≈ 2.0 tokens/round** mean (median 1.97) | MTP head + PLD; byte-identical to serial greedy per FLAGS |
| Config on EVO | `HALOGEN_CTX=65536`, `HALOGEN_KV_SLOTS=2`, `HALOGEN_FLASH_PIN_TRUNK=1`, `HALOGEN_PROMPT_CACHE=2`, `HALOGEN_PREFILL_CHUNK=32768`, `HALOGEN_ARCH=gfx1151`, tuning `/opt/halogen/flash-tune.plan` | `podman inspect` Env |
| Checkpoint | `qwen38-flash-next-w4b.hgn` **116 GiB** + overlay **2.4 GiB** | `~/halogen-models` |
| Host GTT carve | **1 GiB** (`gttsize` sysfs) | matches BIOS UMA ≈1G |

**EVO interpretation:** ~**1.1k tok/s prefill**, ~**45 t/s mean MTP decode** in real chat (often 35–55), far above llama.cpp/ds4 baselines (~10–15 decode).

### 1.2 Upstream published (README `peonist-ai/halogen-flash-server`)

Conditions: Ryzen AI Max+ 395, 128GB, ROCm 7.x, ~85W sustained, **IOMMU off** (worth 13–16% prefill).

| Metric | Published | Source |
|---|---|---|
| Prefill @ 8,192 | **~1,246 t/s** (TTFT 6.6 s) | README Measured, image 0.5.3 |
| Prefill @ 32,768 | **~1,424 t/s** (TTFT 23.0 s) | same |
| Prefill @ 131,072 | **1,358 t/s** (96.5 s) | same |
| Follow-up @ 100k cached | **~2 s** | prompt cache on |
| Decode serial greedy @ 1.5k / 8k / 32k | **37.6 / 36.1 / 34.1 t/s** | same |
| Decode MTP @ 1.5k | **44.8 prose / 49.9 code** (0.6.0 sidecar) | same |
| Decode MTP @ 32k served | **41.7 t/s** mean over 10 prompts | same |
| Prefill @ ~1M (0.12.0 YaRN) | **937 t/s** | same |
| Decode MTP @ ~1M cold | **38.3 t/s** | same |
| Coding-agent MTP+PLD | **56.3 t/s** thinking off | 0.6.0 agent turns |

### 1.3 User baselines (contrast; as given)

| Engine | Prefill | Decode | Notes |
|---|---|---|---|
| llama.cpp ROCm GLM `--cpu-moe` | ~66 t/s @8k | ~12.6 short / ~9.7 @8k | GTT cap → expert CPU offload |
| ds4 DeepSeek-V4-Flash IQ2XXS | ~211 @8k | ~14.3 @8k | kyuz0 strix-halo-ds4-toolbox |

---

## 2. Techniques found (evidence)

### T1 — Pin trunk + `hipHostRegister` / GTT path (`HALOGEN_FLASH_PIN_TRUNK=1`) ★★★★★

Weights `mlock`’d and **`hipHostRegister`’d** so the iGPU DMA-reads system RAM via GTT, **bypassing ~62 GiB GTT “VRAM” ceiling**; BIOS UMA kept at **~1 GiB**.

Evidence: container env `HALOGEN_FLASH_PIN_TRUNK=1`; binary strings `hipHostRegister`, `PIN_TRUNK=0 … several times the decode cost`, `trunk NOT pinned … measured at 11.4 GB/s`, `drives the GPU through GTT`, `FlashModel::pin_experts`; AGENTS.md “weights pinned”; EVO `gttsize=1GiB`.

### T2 — Native MTP speculative decode + prompt-lookup (PLD) ★★★★★ (decode)

Default MTP drafter + `HALOGEN_PLD=3,3`; adaptive `HALOGEN_SPEC_ADAPT`; lossless vs serial greedy. EVO commit ≈ **2.0 tok/round** → ~1.5–2× over serial 34–38 t/s.

Evidence: every EVO `serve_api: mtp … pld`; FLAGS.md; README MTP tables; `k_ngram_*` strings.

### T3 — gfx1151-tuned GEMM + fused MoE ★★★★

Baked `/opt/halogen/flash-tune.plan` (`HGNTUNE3`/`gfx1151`); **hipblaslt**; fused MoE envs; warp/grouped expert + WMMA indexer kernels; wave32-oriented names.

Evidence: `readelf` NEEDED `libhipblaslt` `libamdhip64`; plan magic; kernel symbol strings.

### T4 — Architecture: ~6B active + paged 51B n-gram ★★★★★ (fairness)

125B MoE with **~6B activated** (10+1 experts); **51B n-gram** FP8 table ~47.7 GiB **paged via page cache**; hybrid GDN + sparse attention cuts KV traffic.

Evidence: QUANT.md; GGUF `qwen4exp`: expert_count=512, expert_used=10, embd=2560, blocks=48; HF card 6B activated.

### T5 — Quality overlay 2.4 GiB / custom 4-bit ★★

Sidecar requants hard non-expert tensors; 12× `o_proj` → 8-bit. Speed overlay ≈ −2% decode.

### T6 — Prompt cache ★★★★ (multi-turn)

`HALOGEN_PROMPT_CACHE=2`; follow-up @100k ≈ **2 s** vs ~88 s cold.

### T7 — Sparse indexer budget ★★ (long ctx)

`HALOGEN_INDEXER_BUDGET` default 2048; keeps decode flat with depth.

### T8 — hipGraphs

**Unconfirmed** (no strong strings this pass).

---

## 3. Theoretical decode ceiling

Strix Halo: **256 GB/s** theoretical LPDDR5X; ~**212 GB/s** sustained (community rocm_bandwidth_test). Use 212 GB/s.

| Model | Total / active | Quant (EVO) | Approx weight bytes/tok | Theo @212 GB/s | Observed |
|---|---|---|---|---|---|
| Qwen3.8-Flash-Next | 125B+51B ngram / **~6B** | halogen ~4–4.5 bpw | ~3.4 GB | **~62 t/s** | halogen serial ~34–38; MTP ~42–55 |
| GLM-5.3-Flash | ~320B / **~18B** (8/288) | AJ-IQ2_XXS; GGUF expert_count=288 used=8 embd=4096 | ~5.1 GB | **~42 t/s** | llama.cpp ~10–13 |
| DeepSeek-V4-Flash | ~284B / **~13B** | IQ2XXS; GGUF experts 256 used=6 embd=4096 | ~3.3 GB | **~65 t/s** | ds4 ~14.3 @8k |

**Split:** ~half of halogen vs GLM gap is **6B vs 18B active**; rest is pinning + fused kernels + MTP/PLD + no cpu-moe. Halogen serial is ~60% of Qwen BW ceiling (good); llama/ds4 are ~20–35% of their ceilings (large headroom).

---

## 4. Ranked transferable plan (GLM / DeepSeek)

| Rank | Technique | Expected gain | Implementation | Effort | Root? |
|---|---|---|---|---|---|
| **1** | Pin/`hipHostRegister` MoE weights; drop `--cpu-moe`; keep UMA min | **1.5–3× decode** | `GGML_CUDA_REGISTER_HOST=1` → `hipHostRegister` via HIP shim; `ulimit -l unlimited`; **note:** `GGML_CUDA_ENABLE_UNIFIED_MEMORY` UMA meminfo path is `#if !GGML_USE_HIP` (CUDA-only). Small patch: register mmap’d weights in ggml-hip. ds4: same if not already. BIOS UMA 512M–1G. | Small patch / env | No (memlock via limits.conf) |
| **2** | Speculative decode (MTP / draft / PLD) | **1.3–2× decode** | llama `--draft` / MTP GGUF / prompt-lookup; ds4 MTP flags | Low–med | No |
| **3** | Fused MoE + hipblaslt gfx1151 tune | **1.2–2× prefill** | HIP+hipblaslt build; community fused-MoE PRs | Med | No |
| **4** | Prefix cache | Multi-turn wall clock | llama-server cache | Low | No |
| **5** | IOMMU off / power | Prefill 10–16% | cmdline / BIOS | Low | Reboot |
| **6** | Calibrated quant overlay | Quality; ~2% speed | imatrix/GPTQ | High | No |
| **7** | Sparse attn budget | Long-ctx flatness | Model must have indexer | High | No |

### Top 2 on GLM when GPU free

1. **Full-GPU or host-registered MoE (kill `--cpu-moe`)** — target **≥25–30 t/s** short decode on IQ2_XXS toward ~40 theoretical.  
2. **Enable speculation** — target **1.4–1.8×** over that new serial baseline on agent/code.

---

## 5. Inventory

- Image: `ghcr.io/peonist-ai/halogen-flash-server:0.13.4` (0.12.0 also local)
- Container `halogen-flash` **Exited**; **not started** this session
- Binary `flash_serve` 13M stripped; HIP + hipblaslt
- Overlay 2.4G quality tensors (not a separate MTP-only file in the weight dir)
- Tune plan `/opt/halogen/flash-tune.plan`
- Inspect via `podman create` + `podman cp` only; extract cleaned; GPU unused

---

## 6. Bottom line

Halogen wins by **(a)** ~6B-active MoE + paged n-gram, **(b)** pin+`hipHostRegister` trunk with 1G UMA, **(c)** gfx1151 fused MoE/GEMM, **(d)** lossless MTP+PLD (~2 tok/verify). llama/ds4 at ~10–15 t/s leave **2–4×** on the table vs bandwidth math; port **host-register/pin MoE** and **speculation** first.

*2026-09-24 CST; numbers from logs, README, FLAGS/QUANT, binary strings, GGUF headers only.*
