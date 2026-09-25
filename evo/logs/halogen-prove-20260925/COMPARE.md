# Rocket cinematic compare — Halogen vs Spark vs GLM/DS

Timezone: Asia/Shanghai (CST). Generated 2026-09-25 ~23:05 CST.

## Paths (for hop-grok4.7-2 video pickup)

| artifact | path |
|---|---|
| **Halogen HTML (Studio)** | `$HOME/AI/project/index-halogen-rocket.html` |
| Compare pack | `$HOME/AI/project/rocket-compare/` |
| Halogen meta | `$HOME/AI/project/rocket-compare/meta-halogen.json` |
| **Halogen on EVO** | `~/logs/halogen-prove-20260925/rocket-halogen-index.html` |
| Halogen meta EVO | `~/logs/halogen-prove-20260925/meta-halogen.json` |
| Spark prior HTML | `$HOME/AI/project/rocket-compare/index-spark-prior.html` (+ EVO prove dir) |
| Spark blocker | `meta-spark-BLOCKED.json` / `SPARK-BLOCKER.md` |
| GLM-hi / DS-hi | `rocket-compare/index-{glm,ds}-hi.html` |
| Prior video clips | `$HOME/rocket-rec/clips/spark-qwen.mp4`, `rocket-comparison.mp4` |

## Speed / completeness table

| system | wall s | TTFT s | decode tok/s | out tok | finish | html B | </html> | rAF | notes |
|---|---:|---:|---:|---:|---|---:|---|---|---|
| Halogen EVO fresh | 335.831 | 0.417 | 45.607 | 15315 | stop | 41004 | True | True | thinking off; cache_n=1357; draft_acc=0.799; MAX_TOK=8192 did not clamp (15315 tok) |
| GLM-hi :8080 | 1271.28 | — | 12.121 | 15129 | stop | 47556 | True | True | max_tokens=20480 temp=0.3 + doctype prefill |
| DS-hi Luce | 213.31 | — | 23.8 | 4977 | stop | 14433 | True | True | complete but thin HTML |
| Spark Flash-Next LIVE | — | — | — | — | BLOCKED | — | — | — | :8888 = deepseek-v4-flash-0731; Flash-Next not loaded |
| Spark prior artifact | — | — | ~48.7 claimed | — | prior | 51955 | True | True | rocket-rec/sites/spark-qwen |

## Quality (static HTML scan)

| system | B | mesh~ | particles | webAudio | shader | multi-stage | stars/smoke | HUD |
|---|---:|---:|---|---|---|---|---|---|
| Halogen_EVO_fresh | 41004 | 91 | True | True | True | True | True/True | True |
| Spark_prior | 51955 | 87 | True | True | True | True | True/True | True |
| GLM_hi | 47590 | 101 | True | True | True | True | True/True | True |
| DS_hi | 14439 | 31 | True | True | False | True | True/True | True |
| Halogen_prior_site | 43413 | 79 | True | True | True | True | True/True | True |

## Verdict

**Halogen EVO clearly beats Flash-tier GLM and DeepSeek on this exact cinematic prompt for speed×completeness:** decode **45.6 tok/s** vs GLM-hi **12.1** / DS-hi **23.8**, wall **336 s** vs GLM **1271 s** (DS wall 213 s but only ~14 kB HTML). Halogen finished `stop` with **41 004 B**, closed `</html>`, Three.js + rAF + launch, **15 315** tokens — denser than DS-hi and near GLM-hi size without truncation. vs **Spark**: live Flash-Next **not running** (`:8888` = DeepSeek); prior Spark rocket site is the densest artifact (**51 955 B**, full checks). Mia README claims ~**48.7 tok/s** prose 1-stream on Spark — similar ballpark to Halogen 45.6 on long HTML. **For Shorts/X/Douyin video:** use fresh Halogen HTML + Spark prior (or reload Flash-Next on `:8001`) + GLM/DS-hi as slow/thin baselines; do **not** claim a live same-prompt Spark Flash-Next run tonight.

## Spark bring-up (blocked)

See `meta-spark-BLOCKED.json` / EVO `SPARK-BLOCKER.md`. Repo https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark — on Spark: `cd ~/src/Qwen3.8-Flash-Next-Single-DGX-Spark && ./start.sh` (lab_control uses `PORT=8001`, stops DeepSeek).

