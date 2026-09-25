# Halogen prove — 2026-09-25 (CST)

Sole-tenant on EVO `:8731`. DeepSeek/luce stopped. GLM `:8080` left alone (down).
Image `0.13.4`, model `halogen-qwen3.8-flash-next`, `HALOGEN_FLASH_PIN_TRUNK=1`, `HALOGEN_PROMPT_CACHE=2`, overlay auto, drafter default MTP+PLD.

## Prove table

| Label | Prefill t/s | Decode t/s | cache_n | draft accept | wall s | notes |
|---|---:|---:|---:|---:|---:|---|
| A_baseline_mtp_pad12k | 1099.618 | 48.393 | 0 | 0.8864 | 8.191 | ~matches hist ~1100/45 |
| A_baseline_mtp_pad40k | 1247.438 | 54.489 | 0 | 0.875 | 14.966 | prefill above hist |
| A_short_coding_mtp | 99.767 | 53.913 | 0 | 0.8243 | 2.979 | short TTFT-ish wall |
| B1_coding_mtp | 0.0 | 56.712 | 60 | 0.8571 | 3.535 | MTP+PLD |
| B1_coding_serial | 0.0 | 38.559 | 60 | — | 5.193 | serial greedy |
| B2fair_toolish_mtp | 117.206 | 27.027 | 0 | — | 1.599 | short ans; draft unused |
| B2fair_toolish_serial | 128.648 | 27.707 | 0 | — | 1.509 | short ans |
| C_turn1_cold_sys8k | 907.638 | 38.653 | 0 | 0.64 | 4.035 | cold long system |
| C_turn2_cached_sys8k | 103.503 | 48.416 | 2669 | 0.8929 | 2.847 | 2669/2734 cached |
| C_turn1_shortsys | 78.876 | 47.717 | 0 | 0.7857 | 1.479 |  |
| C_turn2_shortsys | 108.92 | 52.73 | 32 | 0.8571 | 2.657 |  |
| C_overlay_ON_pad12k | 1101.172 | 56.343 | 0 | 0.8864 | 7.545 | quality overlay on |
| C_overlay_OFF_pad12k | 1084.383 | 55.779 | 0 | 0.8957 | 7.278 | CK_OVERLAY_SKIP=1 |
| C_overlay_ON_short | 98.798 | 56.925 | 0 | 0.8571 | 4.125 |  |
| C_overlay_OFF_short | 100.217 | 56.276 | 0 | 0.8632 | 4.175 |  |
| D_stream_smoke | — | — | — | — | 24.302 |  |
| D_stream_75s | — | — | — | — | 75.026 | client cut at 75s; no disconnect |

## What moved speed
- **MTP+PLD vs serial (B1 coding, 200 tok, cached prompt):** decode **56.7 vs 38.6 t/s (~1.47×)**. Same content length (597). Accept rate ~0.86.
- **Prompt cache (C long system):** turn1 prompt_ms **2941** → turn2 **628** with cache_n=2669/2734 (~4.7× faster prompt phase).
- **Large cold prefill:** pad12k **~1100 t/s**, pad40k **~1247 t/s** — at/above historical ~1100.
- **Stream idle:** 75s continuous stream, TTFT 0.55s, max inter-event gap 0.55s; OMP `streamIdleTimeoutMs=1800000` is ample.

## What moved quality
- **Overlay ON vs SKIP:** speed within ~1–2% (ON pad12k decode 56.3 vs OFF 55.8). Content diverged (ON short head len 597 vs OFF 609) — overlay is quality/stability, not a speed dial.
- **Long system prefix:** shapes plan text; cache makes follow-ups cheap. Prefer stable long system for agent sessions.
- Tool-ish turns: model answered in prose (not tool JSON) when asked for next step — expected for that prompt; MTP≈serial on tiny 12-token answers.

## What did not (much)
- Overlay SKIP did **not** unlock meaningful decode speed.
- Very short completions (<~30 tok): MTP draft often unused / noisy; measure decode on ≥128–256 tok.
- Tiny prompts show low prefill t/s (fixed overhead); use ≥4k prompt tokens for prefill claims.

## Recommended max config

### EVO (`halogen-ctl` / container env)
```
HALOGEN_FLASH_PIN_TRUNK=1
HALOGEN_PROMPT_CACHE=2
HALOGEN_CTX=65536
HALOGEN_KV_POOL_POSITIONS=65536
HALOGEN_KV_SLOTS=2
HALOGEN_MAX_TOK=8192
HALOGEN_ARCH=gfx1151
# overlay: leave auto (do NOT set HALOGEN_CK_OVERLAY_SKIP)
# speculation: request drafter=mtp (default); PLD+SPEC_ADAPT server defaults
# sole-tenant: no luce/DeepSeek/:8091 while Halogen up
```

### Request defaults (OMP / clients)
- `drafter: mtp` (or omit — default)
- Agent coding speed path: `enable_thinking: false` / `reasoning_effort: none` when you want max decode; keep thinking for hard planning
- `temperature: 0` for lossless MTP vs serial

### OMP `~/.omp/agent/models.yml` provider `evo-halogen`
- `baseUrl: http://EVO_HOST:8731/v1`
- model id `halogen-qwen3.8-flash-next`
- `streamIdleTimeoutMs: 1800000`, `streamFirstEventTimeoutMs: 600000`
- `thinkingFormat: openai` (not deepseek)
- **Restart Orca/omp agent session** to pick up models.yml

## Artifacts
- `~/logs/halogen-prove-20260925/runs.jsonl`
- `~/logs/halogen-prove-20260925/prove.py`
- `~/logs/halogen-prove-20260925/REPORT.md` (this file)

