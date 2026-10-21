# PIPELINE — playbook for every new open model

Mark hypotheses as **[hypothesis]**. Only claims with a source get a URL.

## 0. Tracking

1. Confirm BF16 (and official FP8/NVFP4) releases on HF / ModelScope / official blogs.
2. Record architecture, context, MoE vs dense, vision, MTP.
3. Pick a hardware profile: Spark **TP1** / Spark **TP2** / EVO (R9700 32GB) / consumer GPU.

## 1. Get the weights

- Prefer **ModelScope** or **hf-mirror**, then `huggingface.co`.
- Always pin a **revision SHA** and record `sha256` / file lists on the scorecard.
- Disk: Spark2 is tight (~67G free per lab-ops) → plan large checkpoints on Spark1 / EVO / external storage.

## 2. Candidate quant matrix

| Format | Tool | Role on Spark | Notes |
|---|---|---|---|
| **NVFP4** | NVIDIA ModelOpt / llm-compressor | Native on GB10; direct duel with MiaAI & NVIDIA recipes | Official QAD checkpoints can beat naive PTQ ([nvidia/Qwen3.8-Flash-Next-FP4-Local](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-FP4-Local)). **[hypothesis]** Beating official QAD on quality is hard; KV / speculative / engine tuning is the practical lever. |
| **FP8** | ModelOpt / vLLM built-ins | Quality floor vs KV headroom | |
| **EXL3** bpw sweep | exllamav3 (`convert_model` / recipe yaml) | Dense mid-size tok/s–quality curve (turboderp, MiaAI) | turboderp publishes calib + `kld_table` ([turboderp/Qwen3.8-27B-exl3](https://huggingface.co/turboderp/Qwen3.8-27B-exl3)). MiaAI claims workload-calibrated 3.5bpw ([Mia-AiLab/Qwen3.8-27B-EXL3-3.5bpw](https://huggingface.co/Mia-AiLab/Qwen3.8-27B-EXL3-3.5bpw)). |
| **GGUF** imatrix | llama.cpp | EVO / consumer / cross-engine | unsloth Dynamic 3.0 and bartowski imatrix publish public benches. |
| **AWQ / GPTQ** | llm-compressor etc. | vLLM/SGLang path | Usually lower priority on Spark vs EXL3/NVFP4. **[hypothesis]** |

### KV quantization

- Engine options: FP8 / NVFP4 / int4 KV, etc.
- MiaAI one-click docs claim int4 KV ≈ KL 0.001 vs fp16 on the EXL3 path ([Qwen3.8-27B-16gb one-click](https://github.com/MiaAI-Lab/Qwen3.8-27B-16gb-NVIDIA-GPUs-one-click-install)). **Re-measure with our numbers.**

### Speculative decoding

- **MTP** (built-in head), **DFlash2**, **EAGLE**, DeepSeek **DSpark**, etc.
- Acceptance and tok/s are workload-dependent → split HumanEval-class / chat / long-prefill in the table.
- Prefer speculative **off** during KL measurement.

### TP1 vs TP2

- If it fits one card, TP1 is often simpler and lower latency. **[hypothesis]**
- Very large models (DeepSeek Flash class) need TP2 + compressed KV + speculative (MiaAI [2x Spark DSpark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)).

## 3. Levers we can actually win on

| Lever | Expected effect | Evidence type |
|---|---|---|
| **Calibration data choice** (coding / agent / multilingual mix, length) | Lower KL / better downstream at same bpw | MiaAI workload-calibrated EXL3 claims; unsloth Dynamic imatrix claims — **hypothesis + third-party until we reproduce**. |
| **Per-layer mixed bpw** (attention / MLP / experts) | Better quality–size Pareto | Common EXL3 recipe yaml / GGUF tensor layout practice (bartowski). |
| **KV quant + memory budget** | Longer ctx or higher concurrency in the same VRAM | Core differentiator in MiaAI TensorFold / NVFP4 recipes. |
| **Speculative tuning** (draft quant, K, acceptance) | Higher decode tok/s | DFlash2 EXL3 draft reports throughput gains vs bf16 draft ([Mia-AiLab DFlash2](https://huggingface.co/Mia-AiLab/Qwen3.8-27B-DFlash2-EXL3-5.0bpw)). |
| **Engine / kernels / graph capture** | Prefill / decode | MiaAI already farms this hard — **expensive to chase**. Differentiating on quant + calib + KV is more realistic. **[hypothesis]** |
| **Keep official QAD NVFP4, optimize serving only** | NVIDIA-level quality, compete on tok/s / KV | FP4-Local card: https://huggingface.co/nvidia/Qwen3.8-Flash-Next-FP4-Local |

## 4. Measure → scorecard → (after approval) publish

1. Speed + eval subset via `bench_client.py`.
2. Quality via `kl_compare.py` or EXL3 `measure_model`.
3. Re-measure competitor recipes on the **same machine**.
4. Fill README template with digests, revisions, tables.
5. GitHub/HF publish **only after explicit user GO**.

## 5. Do / don’t on this box

- **Do:** scripts, docs, result JSON, mock dry-run, web ID checks.
- **Don’t:** start/stop/kill Spark/EVO servers, heavy load on dsv41, unauthorized HF/GitHub push.
