# FIRST_TARGET — first head-to-head

## Pick: **Qwen3.8-27B** (dense, ~27B)

### Why this first

| Candidate | Now? | Why |
|---|---|---|
| **Qwen3.8-27B** | ✅ #1 | Dense, lots of competing EXL3/GGUF quants; fits EVO R9700 32GB, consumer 24/16GB, and later Spark TP1. Clear quality/speed contest via calib, bpw, imatrix. |
| Qwen3.8-Flash-Next (~125B MoE) | ❌ hold | NVIDIA FP4/NVFP4 and MiaAI TensorFold nearly fill one Spark (~96GiB). **Sparks are saturated with dsv41 TP2 today.** |
| DeepSeek-V4/V4.1-Flash | ❌ hold | Already served on TP2; quant experiments need **approved dsv41 downtime**. |
| GLM-5.3-Flash | △ #2 | MiaAI EXL3 2× Spark recipe exists; also needs a Spark window. |

### Verified HF IDs (API-checked, 2026-10-21)

Base

| id | revision (sha) | Notes |
|---|---|---|
| `Qwen/Qwen3.8-27B` | `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0` | BF16 source |

Competitor / reference quants

| id | revision (sha) | Format |
|---|---|---|
| `turboderp/Qwen3.8-27B-exl3` | `d23340a1fdb479f3c2878136dcede06cf57ea31a` | EXL3 bpw sweep + `kld_table.json` |
| `Mia-AiLab/Qwen3.8-27B-EXL3-3.5bpw` | `19441ac874c4018295da848e250f23511361cda4` | workload-calibrated 3.5bpw |
| `Mia-AiLab/Qwen3.8-27B-DFlash2-EXL3-5.0bpw` | `4f0436269bca761b071f05319e8e04a87cc633f9` | DFlash2 draft |
| `unsloth/Qwen3.8-27B-GGUF` | `4ca720788d1e01f1bff70c033e0d0028fd02e502` | Dynamic GGUF |
| `bartowski/Qwen3.8-27B-GGUF` | `87410e7b9a5c21e6ca70c0c9cc5237de909fe621` | imatrix GGUF (+ PPL/KLD tables) |

Flash-Next (second target when a Spark window opens)

| id | revision (sha) | Notes |
|---|---|---|
| `nvidia/Qwen3.8-Flash-Next-FP4-Local` | `b9ce18a6887e18c089fdea8509a33e63429a3300` | QAD FP4 ~96GiB |
| `nvidia/Qwen3.8-Flash-Next-NVFP4` | `fc694b54fb0174e0913e6adf86691ef85a4ead47` | multi-GPU Blackwell/Spark recipes |

Related MiaAI recipes (GitHub):  
https://github.com/MiaAI-Lab/Qwen3.8-27B-16gb-NVIDIA-GPUs-one-click-install ·  
https://github.com/MiaAI-Lab/Qwen3.8-27B-SGLang-DGX-Spark ·  
https://github.com/MiaAI-Lab/Qwen3.8-27B-DFlash2-EXL3-5.0bpw

### Contest plan (we re-measure)

1. **Same bpw/size band**, EXL3: turboderp plain vs Mia workload-calibrated vs **our calib recipe**.
2. **Same disk-GB band**, GGUF: unsloth UD-Q4_K_* vs bartowski Q4_K_M vs (if ready) our imatrix.
3. Serving: ExLlamaV3 vs llama.cpp vs (when Spark is free) SGLang/vLLM — **label the engine in big type** when mixing engines.

tok/s and KL numbers are **not** hard-coded here — only our scorecard fills them in.

## GPU window / approvals needed

lab-ops snapshot (2026-10-21 ~09:36 Asia/Shanghai): Spark1+2 = dsv41 TP2 only; EVO 8216/8217 = Qwen3.8-Flash-Next quants. **No free GPU time.**

| Stage | Where | Ask for |
|---|---|---|
| A. Bench client only | this box + mock | no approval (can finish now) |
| B. Download competitor GGUF/EXL3 | EVO disk (~320G free) or external | agree path + mirror; don’t touch serving processes |
| C. **Serve + bench** (first duel) | EVO R9700 **or** Windows RTX 3060 / other | **8216 stop or swap approval** (lab-ops + user). Expect ~15–30GB VRAM + KV. Window: serve-compare only **2–4h**; EXL3 re-quant **half day+** (scales with calib tokens). |
| D. 27B recipe on Spark TP1 | Spark1 alone | **full dsv41 TP2 stop**. Weights mainly on Spark1 (333G free; Spark2 ~67G). Window: serve bench **half day**, full quant sweep **1–2 days**. |
| E. Flash-Next / DeepSeek quant | Spark 1–2 | dsv41 stop + large disk; user GO required. |

**Minimum ask right now (recommended):**  
1) keep EVO `8216` up and **only mirror** Qwen3.8-27B competitor quants to disk, or  
2) short window: take `8216` down and smoke-serve **two** of turboderp 3.0–4.0bpw + unsloth/bartowski Q4, then run `bench_client`.

dsv41, 8217, and heavy training occupancy are **not needed for this target** — leave them alone.
