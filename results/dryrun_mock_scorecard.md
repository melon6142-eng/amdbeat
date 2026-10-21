# Scorecard: mock / mock-bf16

- generated_at (UTC): `2026-10-21T01:41:58Z`
- base_url: `http://127.0.0.1:18765/v1`
- seed: `42`
- dry_run: `True`

## Speed

| depth | c | TTFT s | prefill tok/s | decode tok/s | prompt toks |
|---|---:|---:|---:|---:|---:|
| 0 | 1 | 0.008 | 240.192 | 374.806 | 2 |
| 512 | 1 | 0.009 | 60731.057 | 377.964 | 576 |
| 2048 | 1 | 0.013 | 179349.032 | 376.306 | 2297 |

## Eval subset

| suite | n | pass | pass_rate |
|---|---:|---:|---:|
| kl | 5 | n/a | n/a |
| gsm8k_subset | 2 | 2 | 1.000 |
| humaneval_subset | 1 | 1 | 1.000 |
| ifeval_subset | 1 | 1 | 1.000 |

## Notes

- Quality vs BF16 (KL / top-token agreement) requires a reference endpoint; see `scripts/kl_compare.py`.
- Memory (weights GB, KV capacity) must be filled from server logs / `nvidia-smi` — not auto-measured here.
- Pin engine image digest, weight revision, and sampling flags before publishing comparisons.
