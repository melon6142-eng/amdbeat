#!/usr/bin/env bash
# Download P0 (+ optional P1) — run ON EVO or a machine with $EVO_MODELS mounted.
# Does not stop any server. Requires EVO_CONFIRM=1.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"
require_confirm

mkdir -p "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF" "$EVO_MODELS/bartowski-Qwen3.8-27B-GGUF"

download_one() {
  local repo="$1" file="$2" dest="$3"
  if command -v hf >/dev/null 2>&1; then
    HF_ENDPOINT="${HF_ENDPOINT}" hf download "$repo" "$file" --local-dir "$dest"
  elif command -v huggingface-cli >/dev/null 2>&1; then
    HF_ENDPOINT="${HF_ENDPOINT}" huggingface-cli download "$repo" "$file" --local-dir "$dest"
  elif command -v aria2c >/dev/null 2>&1; then
    local base="${HF_ENDPOINT:-https://hf-mirror.com}"
    aria2c -x16 -s16 -c -d "$dest" \
      "${base}/${repo}/resolve/main/${file}"
  else
    echo "Need hf, huggingface-cli, or aria2c" >&2
    exit 1
  fi
}

download_one "unsloth/Qwen3.8-27B-GGUF" "Qwen3.8-27B-UD-Q6_K.gguf" \
  "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF"

if [[ "${DOWNLOAD_RIVAL:-1}" == "1" ]]; then
  download_one "bartowski/Qwen3.8-27B-GGUF" "Qwen3.8-27B-Q6_K.gguf" \
    "$EVO_MODELS/bartowski-Qwen3.8-27B-GGUF"
fi

if [[ "${DOWNLOAD_DRAFT:-0}" == "1" ]]; then
  download_one "unsloth/Qwen3.8-27B-GGUF" "MTP/mtp-Qwen3.8-27B-Q4_0.gguf" \
    "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF"
fi

ls -lh "$EVO_MODELS/unsloth-Qwen3.8-27B-GGUF" "$EVO_MODELS/bartowski-Qwen3.8-27B-GGUF" || true
