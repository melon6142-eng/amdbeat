#!/usr/bin/env bash
# Resume-capable Halogen Flash-Next fetch. Checkpoint + quality overlay + tokenizer.
set -euo pipefail
DEST="${HALOGEN_DIR:-$HOME/halogen-models}"
BASE="${HALOGEN_HF_BASE:-https://hf-mirror.com/peonist-ai/halogen-qwen3.8-flash-next/resolve/main}"
mkdir -p "$DEST/tokenizer"
cd "$DEST"
wget -4 -c --retry-connrefused --tries=20 --timeout=30 \
  -O qwen38-flash-next-w4b.hgn \
  "$BASE/qwen38-flash-next-w4b.hgn"
wget -4 -c --retry-connrefused --tries=20 --timeout=30 \
  -O qwen38-flash-next-w4b.overlay.hgn \
  "$BASE/qwen38-flash-next-w4b.overlay.hgn"
for f in chat_template.jinja generation_config.json merges.txt tokenizer.json tokenizer_config.json vocab.json; do
  wget -4 -c --retry-connrefused --tries=20 --timeout=30 \
    -O "tokenizer/$f" \
    "$BASE/tokenizer/$f"
done
echo HALOGEN_WGET_OK
ls -lh qwen38-flash-next-w4b.hgn qwen38-flash-next-w4b.overlay.hgn tokenizer
