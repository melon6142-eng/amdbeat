#!/usr/bin/env bash
# Download Halogen Flash-Next weights only (checkpoint + quality overlay + tokenizer).
set -euo pipefail
PY="${HF_PY:-$HOME/.venvs/hf/bin/python}"
DEST="${HALOGEN_DIR:-$HOME/halogen-models}"
mkdir -p "$DEST"
[[ -x $PY ]] || { echo "missing $PY"; exit 1; }
exec "$PY" - <<PY
from huggingface_hub import snapshot_download
print("download start", flush=True)
snapshot_download(
    repo_id="peonist-ai/halogen-qwen3.8-flash-next",
    local_dir="$DEST",
    allow_patterns=[
        "qwen38-flash-next-w4b.hgn",
        "qwen38-flash-next-w4b.overlay.hgn",
        "tokenizer/*",
        "README.md",
    ],
)
print("download done", flush=True)
PY
