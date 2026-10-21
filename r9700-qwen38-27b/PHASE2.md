# Phase 2 — own imatrix / calibration (after baseline H2H)

Run only after Phase 1 scorecard shows whether unsloth UD-Q6_K or bartowski Q6_K wins on R9700.

## Goal

Beat the Phase-1 winner at **same disk size / same nominal bpw** with a lab-owned imatrix GGUF, then publish recipe + numbers.

## Outline

1. **Calibration corpus**  
   - Mix: general (Wiki/C4 slice), code, long-context, Chinese+English.  
   - Keep token budget explicit (e.g. 200–500 stepts × N tokens) so others can reproduce.  
   - Prefer **not** stealing competitor calibration text verbatim if license unclear; bartowski ships `Qwen3.8-27B-calibration-v6.txt` — use only if license allows, else build our own list.

2. **Teacher / importance**  
   - Ideal teacher: BF16 or Q8_0 of same arch for KL.  
   - BF16 GGUF is multi-shard (~50GB+) — needs disk + CPU/GPU time; may use Mac Studio or a cleared Spark **with user approval**.  
   - On R9700 alone: generate imatrix with `llama-imatrix` against Q8_0 if BF16 won’t fit.

3. **Quantize**  
   ```bash
   # placeholders — exact llama-quantize args depend on binary version
   llama-imatrix -m Qwen3.8-27B-Q8_0.gguf -f cal.txt -o lab-imatrix.gguf
   llama-quantize --imatrix lab-imatrix.gguf \
     Qwen3.8-27B-BF16.gguf Qwen3.8-27B-lab-Q6_K.gguf Q6_K
   ```
   Also produce Q5_K_M / Q4_K_M from same imatrix for the ladder.

4. **Evaluate**  
   - Same `bench_client.py` + optional `kl_compare.py` vs Phase-1 winner.  
   - Report: PPL/KLD if available, fixed-prompt match, pp/tg @ 0/8k/32k depth, VRAM.

5. **Publish bar**  
   - Win on **≥2 of 3**: (quality proxy), (decode tok/s), (max stable ctx).  
   - Document binary commit, flags, cal hash, HF upload **only with user GO**.

## Hardware notes

- R9700 32GB: serving Q6 fine; **producing** BF16→GGUF may need more RAM/disk than weights alone.  
- Do not stop dsv41 for Phase 2 unless user explicitly approves Spark window.  
- EVO disk 320G free is enough for Q8 + imatrix + few K-quants if Flash-Next weights aren’t duplicated.
