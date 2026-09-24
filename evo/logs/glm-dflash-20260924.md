# GLM-5.3-Flash DFlash2 speculative decode — 2026-09-24 CST

## Disk
| When | Free |
|------|------|
| Start (pre-download) | ~312.8 GiB |
| After DFlash2 GGUF | ~307 GiB |
| End (post-build/bench) | **431 GiB** (V4.1 / other cleanup elsewhere; floor ≥30 GiB OK) |

DFlash2 file: `$MODELS_DIR/gguf/GLM-5.3-Flash-DFlash2/GLM-5.3-Flash-DFlash2-BF16.gguf`  
Size **2,352,022,432 B** (matches Hub). Via Clash `127.0.0.1:7897`, `HF_HUB_DISABLE_XET=1` / ranged curl.

## Build
Unsloth `glm5next/public` @ `65fc13e` has `draft-dflash` but **DFlash1 graph only** (creates ~58 tensors). Hub GGUF is **DFlash2** (81 tensors: grouped dynamic conv + candidate selector) → load error `expected 81, got 58`.

**Working base:**
| Item | Value |
|------|-------|
| Tree | `~/src/llama-dflash2-vcruz` (vcruz305/llama.cpp `glm5next-mtp`) |
| Commit | `4a06ec6187b72313754f5f0c7a394ca5522ad8a2` (`spec: include cmath for DFlash2`) |
| Includes | PR #27342 @ `6f5ac9a` + glm5next MTP graph |
| Hostreg | `~/logs/bench-glm53-s/fast-20260924/unsloth-glm5next-hostreg-full.patch` applied clean |
| Binary | `~/src/llama-dflash2-vcruz/build-hip-dflash/bin/llama-server` |
| HIP | gfx1151, Release, `GGML_HIP_GRAPHS=ON`, `GGML_HIP_NO_VMM=ON` |
| Build log | `~/logs/glm-dflash-build-20260924_203129.log` |

Do **not** combine with `draft-mtp`.

## Bench method
- Target: AJ-IQ2_XXS GLM-5.3-Flash (hostreg mmap)
- Draft on GPU (`--spec-draft-ngl 999`)
- Prompts: chat / code / long agent (`~/bench/ds-agent-prompts/cli-text/01_code_edit_python.txt`)
- `n_predict=256`, `temperature=0`, ctx 16384 for bench
- Artifacts: `~/logs/glm-dflash-bench-20260924_204203/`

## Results table (decode tok/s)

| Config | chat t/s | code t/s | agent t/s | chat accept | code accept | agent accept | prompt_tps agent |
|--------|----------|----------|-----------|-------------|-------------|--------------|------------------|
| baseline | **13.86** | **13.92** | **13.74** | — | — | — | 70.9 |
| dflash n_max=**3** | **19.29** | **22.34** | **20.18** | 75.2% | 93.5% | 81.9% | 69.6 |
| dflash n_max=5 | 12.15 | 14.31 | 11.80 | 74.7% | 91.3% | 42.2% | 69.1 |
| dflash n_max=7 | 10.14 | 12.45 | 6.09 | 58.1% | 78.5% | 30.0% | 69.0 |

Speedup vs baseline at **n_max=3**: chat **1.39×**, code **1.61×**, agent **1.47×**.  
Prefill essentially unchanged (~69–71 t/s agent).  
n_max 5/7: higher draft work, lower accept on agentic → **slower than baseline** on this IQ2_XXS / LPDDR bandwidth-bound setup (unlike Spark Q2_K report of 41 vs 28 MTP).

### Output coherence / identity (temp 0)
| Prompt | n3 vs baseline | n5/n7 vs baseline |
|--------|----------------|-------------------|
| code | **byte-identical** | diverged (`else:` branch) |
| chat | same opening, later diverge | different path |
| agent | coherent, different wording | coherent, similar to baseline |

Verification works for structured code at n_max=3; free-form / think paths can diverge (fp / sampling path). Output remains coherent.

## Recommendation
**Adopt DFlash2 with `--spec-draft-n-max 3`** on EVO for AJ-IQ2_XXS (~1.4–1.6× decode). Do **not** use n_max 5/7 here.

Scripts:
- `~/bin/evo-serve-glm53-dflash.sh` (default `SPEC_DRAFT_N_MAX=3`)
- `~/bin/evo-bench-glm53-dflash.sh`
- Fallback still: `~/bin/evo-serve-glm53-fast.sh` (no draft)

## :8080 status (end)
- **Serving:** `evo-serve-glm53-dflash.sh` (draft-dflash, n_max=3, draft on GPU)
- **PID:** 201237
- **/health:** `{"status":"ok"}` @ 20:49:40 CST
- Alias: `glm53-dflash`
