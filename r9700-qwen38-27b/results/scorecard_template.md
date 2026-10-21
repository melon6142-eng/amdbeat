# Scorecard — R9700 Qwen3.8-27B GGUF H2H

Date (Asia/Shanghai): ________  
llama.cpp binary / commit: ________  
Backend: ROCm / Vulkan (circle)  
Flags (identical both sides): `-ngl 99 -c ____ -b ____ -ub ____ -fa ____ --jinja --mmap -np 1`

## Contenders

| id | repo | file | GiB | alias |
|---|---|---|---:|---|
| A (primary) | unsloth/Qwen3.8-27B-GGUF | Qwen3.8-27B-UD-Q6_K.gguf | 20.47 | qwen38-27b-ud-q6k |
| B (rival) | bartowski/Qwen3.8-27B-GGUF | Qwen3.8-27B-Q6_K.gguf | 22.22 | qwen38-27b-q6k |
| C (optional) | lab Phase2 | …-lab-Q6_K.gguf | | |

## Speed (tok/s)

| metric | A | B | C |
|---|---:|---:|---:|
| pp @ prompt≈512 | | | |
| pp @ prompt≈8k | | | |
| tg @ depth 0 | | | |
| tg @ depth 8k | | | |
| tg @ depth 32k | | | |
| VRAM used (GiB) | | | |
| max stable -c | | | |

## Quality proxies

| metric | A | B | C |
|---|---:|---:|---:|
| fixed-prompt exact/near match (n=__) | | | |
| eval subset score (bench_client) | | | |
| KL vs Q8/BF16 (if run) | | | |
| notes (garbage/repetition) | | | |

## Winner

- Speed: ________  
- Quality: ________  
- Overall (quality×speed @ ≥32k): ________  
- Next action: keep winner as baseline / drop to Q5 for 128k / start Phase 2 imatrix

Raw JSON: `results/bench_*.json`
