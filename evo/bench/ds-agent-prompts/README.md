# ds-agent-prompts

Agent-style long-generation request bodies for DeepSeek V4 Flash / ds4-server
OpenAI-compatible `/v1/chat/completions`.

## Shared fields
- `model`: default `deepseek-v4-flash` (edit per environment)
- `temperature`: 0
- `max_tokens`: 768
- `stream`: false
- `chat_template_kwargs.enable_thinking`: false

## Prompt inventory
| File | Kind | Intent |
|------|------|--------|
| `01_code_edit_python.json` | code-edit | Full rewrite of ~90-line Python task queue with logging/cancel/snapshot/budget |
| `02_code_edit_javascript.json` | code-edit | Full rewrite of ~80-line JS TTL store with touch/sweep/LRU |
| `03_tool_call_openai_tools.json` | tool-call | OpenAI `tools` schema; multi-step search/read/test/patch + long final explanation |
| `04_tool_call_plaintext_fallback.json` | tool-call | Same task without `tools` field; XML `<tool_call>` emulation |
| `05_explain_rocm_dspark.json` | long-explain | 8-section ROCm/DSpark technical deep-dive |
| `06_explain_openai_gateway.json` | long-explain | 10-section gateway design document |

Each prompt is designed to keep generating toward `max_tokens` (>=400 completion tokens)
rather than early EOS from short chat answers.

## Harness
Use `~/bin/evo-bench-ds-agent.sh` (dry-run first):

```bash
~/bin/evo-bench-ds-agent.sh --dry-run
~/bin/evo-bench-ds-agent.sh 8091 agent1 ~/logs/ds-agent-bench
SERVER_LOG=~/logs/dspark-bench/runs/B/server.log ~/bin/evo-bench-ds-agent.sh 8091 tag outdir
```
