#!/usr/bin/env bash
# DeepSeek-V4-Flash + DSpark draft for coding-agent workloads on EVO.
# Matrix 2026-09-24 (N_REPS=3, 6 prompts): no config met all selection criteria
# (code>=95% of B, tool04>=90% of A, geomean>=A). Tool04 stayed ~49% of ordinary
# across B/C/E/F/D/G. Among conf 0.5 (B geomean 15.81) vs 0.7 (C geomean 16.08),
# keep conf 0.7. Tool-call regression remains.
# Same port 8091 as evo-serve-deepseek-fast.sh — only one of the two can run.
# No fuser -k. Does not kill other servers. Container is not --rm so logs survive stop.
# Graceful stop + stats: podman stop -t 60 ds4-dspark-8091
#   then: podman logs ds4-dspark-8091 | grep 'DSpark stats'
set -euo pipefail

IMAGE="docker.io/kyuz0/strix-halo-ds4-toolbox:ds4.1f-rocm10.0"  # id cbcfa1378e35
NAME="ds4-dspark-8091"
MODEL_DIR="$MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS"
BASE_FILE="DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf"
MTP_FILE="DeepSeek-V4-Flash-DSpark-support-0731.gguf"
CTX="${CTX:-65536}"
DSPARK_CONF="${DSPARK_CONF:-0.7}"

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
# DSpark: --dspark + --mtp-model; do NOT pass --mtp-timing (errors with DSpark).
# DS4_DSPARK_STATS=1 prints acceptance stats at graceful shutdown.
exec podman run -d --name "$NAME" \
  -p 8091:8000 \
  --device /dev/kfd --device /dev/dri \
  --group-add keep-groups \
  --ipc=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
  -e DS4_DSPARK_STATS=1 \
  -v "$MODEL_DIR:/models:ro" \
  "${PODMAN_EXTRA[@]}" \
  "$IMAGE" \
  ds4-server --rocm -m "/models/$BASE_FILE" --ctx "$CTX" --host 0.0.0.0 --port 8000 \
  --dspark --mtp-model "/models/$MTP_FILE" --dspark-confidence "$DSPARK_CONF" \
  "${EXTRA_ARGS[@]}"
