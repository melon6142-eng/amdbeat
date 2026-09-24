#!/usr/bin/env bash
# Wrap ds4-bench against the same toolbox image / device flags as serve.
# Usage: evo-bench-deepseek-ds4.sh /path/to/prompt.txt
# Does not start a long-lived server; one-shot container.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/prompt.txt" >&2
  exit 1
fi

PROMPT_HOST="$1"
if [[ ! -f "$PROMPT_HOST" ]]; then
  echo "Prompt file not found: $PROMPT_HOST" >&2
  exit 1
fi

IMAGE="docker.io/kyuz0/strix-halo-ds4-toolbox:rocm-10.0"
MODEL_DIR="$MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS"
BASE_FILE="DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf"
RESULTS_DIR="${HOME}/hybrid-results/ds4-bench"
PROMPT_BASENAME="$(basename "$PROMPT_HOST")"

mkdir -p "$RESULTS_DIR"

# README-documented ds4-bench flags: -m, --prompt-file, --ctx-start, --ctx-max,
# --step-incr, --gen-tokens.
# --rocm and --csv: verified present in ds4-bench --help (2026-09-24).
#   ds4-bench --help before relying on it (left as requested).

exec podman run --rm \
  --device /dev/kfd --device /dev/dri \
  --group-add keep-groups \
  --ipc=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
  -v "$MODEL_DIR:/models:ro" \
  -v "$RESULTS_DIR:/results:rw" \
  -v "$PROMPT_HOST:/prompts/$PROMPT_BASENAME:ro" \
  "$IMAGE" \
  ds4-bench --rocm \
    -m "/models/$BASE_FILE" \
    --prompt-file "/prompts/$PROMPT_BASENAME" \
    --ctx-start 2048 \
    --ctx-max 65536 \
    --step-incr 2048 \
    --gen-tokens 128 \
    --csv /results/bench.csv
