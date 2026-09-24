#!/usr/bin/env bash
# Detached ds4-server launcher for DeepSeek-V4-Flash IQ2XXS on EVO (port 8091).
set -euo pipefail

IMAGE="docker.io/kyuz0/strix-halo-ds4-toolbox:rocm-10.0"
NAME="ds4-8091"
MODEL_DIR="$MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS"
BASE_FILE="DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf"
CTX="${CTX:-65536}"

if podman container exists "$NAME" 2>/dev/null; then
  echo "Container $NAME already exists; refusing to remove or replace it. Stop/remove it yourself if intended." >&2
  exit 1
fi
if ss -ltn | grep -q ":8091 "; then
  echo "Port 8091 already listening; refuse to start." >&2
  exit 1
fi

# Verified from `ds4-server --help` in rocm-10.0 (2026-09-24):
#   --prefill-chunk, --kv-disk-dir, --kv-disk-space-mb, --ctx, --rocm
# NOT present: --mtp/--mtp-draft, any DSpark flag.
# Rootless podman: --group-add keep-groups (named video/render alone failed
# with "no ROCm-capable device"; keep-groups exposes gfx1151 via rocminfo).

EXTRA_ARGS=()
PODMAN_EXTRA=()

if [[ -n "${PREFILL_CHUNK:-}" ]]; then
  EXTRA_ARGS+=(--prefill-chunk "$PREFILL_CHUNK")
fi

if [[ -n "${KV_DISK_DIR:-}" ]]; then
  mkdir -p "$KV_DISK_DIR"
  PODMAN_EXTRA+=(-v "$KV_DISK_DIR:$KV_DISK_DIR:rw")
  EXTRA_ARGS+=(--kv-disk-dir "$KV_DISK_DIR")
  if [[ -n "${KV_DISK_SPACE_MB:-}" ]]; then
    EXTRA_ARGS+=(--kv-disk-space-mb "$KV_DISK_SPACE_MB")
  fi
fi

if [[ -n "${MTP_FILE:-}" ]]; then
  echo "ERROR: MTP_FILE set but ds4-server in $IMAGE has no --mtp flag." >&2
  exit 1
fi
if [[ -n "${DSPARK_FILE:-}" ]]; then
  echo "ERROR: DSPARK_FILE set but ds4 has no DSpark flag in $IMAGE. DSPARK_K=${DSPARK_K:-5} unused." >&2
  exit 1
fi

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
