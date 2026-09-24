#!/usr/bin/env bash
# Fastest measured DeepSeek-V4-Flash decode on EVO (2026-09-24): ds4-server ~16.2 tok/s
# vs llama.cpp hostreg ~13.5 tok/s. Port 8091. No fuser -k. Does not kill other servers.
set -euo pipefail

IMAGE="docker.io/kyuz0/strix-halo-ds4-toolbox:rocm-10.0"
NAME="ds4-8091"
MODEL_DIR="$MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS"
BASE_FILE="DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf"
CTX="${CTX:-65536}"

if podman container exists "$NAME" 2>/dev/null; then
  echo "Container $NAME already exists; refusing to remove/replace." >&2
  exit 1
fi
if ss -ltn | grep -q ":8091 "; then
  echo "Port 8091 already listening; refuse to start." >&2
  exit 1
fi

EXTRA_ARGS=()
PODMAN_EXTRA=()
if [[ -n "${PREFILL_CHUNK:-}" ]]; then
  EXTRA_ARGS+=(--prefill-chunk "$PREFILL_CHUNK")
fi
if [[ -n "${KV_DISK_DIR:-}" ]]; then
  mkdir -p "$KV_DISK_DIR"
  PODMAN_EXTRA+=(-v "$KV_DISK_DIR:$KV_DISK_DIR:rw")
  EXTRA_ARGS+=(--kv-disk-dir "$KV_DISK_DIR")
  [[ -n "${KV_DISK_SPACE_MB:-}" ]] && EXTRA_ARGS+=(--kv-disk-space-mb "$KV_DISK_SPACE_MB")
fi

# Rootless: keep-groups required for gfx1151 visibility (named video/render failed).
# This image has no --mtp / DSpark flags (verified ds4-server --help 2026-09-24).
exec podman run -d --name "$NAME" \
  -p 8091:8000 \
  --device /dev/kfd --device /dev/dri \
  --group-add keep-groups \
  --ipc=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
  -v "$MODEL_DIR:/models:ro" \
  "${PODMAN_EXTRA[@]}" \
  "$IMAGE" \
  ds4-server --rocm -m "/models/$BASE_FILE" --ctx "$CTX" --host 0.0.0.0 --port 8000 \
  "${EXTRA_ARGS[@]}"
