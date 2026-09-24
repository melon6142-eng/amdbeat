#!/usr/bin/env bash
# Run one ds4 matrix row: start container, wait health, bench, stop, save logs.
# Usage: evo-ds4-matrix-row.sh <TAG> <extra-podman-e-flags...> -- <ds4-server-extra-args...>
# Env: N_REPS, OUTDIR, PROMPT_FILTER (optional basename glob), SKIP_BENCH=1
set -euo pipefail
TAG="${1:?tag}"; shift
IMAGE="docker.io/kyuz0/strix-halo-ds4-toolbox:ds4.1f-rocm10.0"
NAME="ds4-matrix-${TAG}"
MODEL_DIR="$MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS"
BASE="DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf"
MTP="DeepSeek-V4-Flash-DSpark-support-0731.gguf"
OUTDIR="${OUTDIR:-$HOME/logs/ds-matrix-20260924}"
N_REPS="${N_REPS:-3}"
mkdir -p "$OUTDIR"

PODMAN_E=()
EXTRA=()
SEEN_SEP=0
for a in "$@"; do
  if [[ "$a" == "--" ]]; then SEEN_SEP=1; continue; fi
  if [[ $SEEN_SEP -eq 0 ]]; then PODMAN_E+=("$a"); else EXTRA+=("$a"); fi
done

if podman container exists "$NAME" 2>/dev/null; then
  echo "Container $NAME exists; stop/rm first" >&2
  podman stop -t 60 "$NAME" || true
  # save logs if any
  podman logs "$NAME" > "$OUTDIR/server-${TAG}-preexist.log" 2>&1 || true
  podman rm "$NAME" || true
fi
if ss -ltn | grep -q ":8091 "; then
  echo "Port 8091 still listening" >&2
  ss -ltnp | grep 8091 || true
  exit 1
fi

CMD=(podman run -d --name "$NAME" -p 8091:8000
  --device /dev/kfd --device /dev/dri
  --group-add keep-groups
  --ipc=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined
  -v "$MODEL_DIR:/models:ro"
)
# PODMAN_E are -e KEY=VAL pairs already expanded as separate args like -e FOO=1
i=0
while [[ $i -lt ${#PODMAN_E[@]} ]]; do
  CMD+=("${PODMAN_E[$i]}")
  i=$((i+1))
done

# Build ds4-server argv
SERVER=(ds4-server --rocm -m "/models/$BASE" --ctx 65536 --prefill-chunk 4096 --host 0.0.0.0 --port 8000)
# If EXTRA contains --dspark or looks like ordinary, append EXTRA as-is
# For ordinary (TAG A) EXTRA may be empty; for others caller passes --dspark etc.
SERVER+=("${EXTRA[@]}")

echo "[$(date -Iseconds)] START $TAG name=$NAME"
echo "podman_e: ${PODMAN_E[*]:-}"
echo "server: ${SERVER[*]}"

"${CMD[@]}" "$IMAGE" "${SERVER[@]}"
CID=$(podman inspect -f "{{.Id}}" "$NAME")
echo "CID=$CID"

# Wait for health / listening inside
ok=0
for i in $(seq 1 180); do
  if curl -sf --max-time 2 "http://127.0.0.1:8091/health" >/dev/null 2>&1 \
     || curl -sf --max-time 2 "http://127.0.0.1:8091/v1/models" >/dev/null 2>&1; then
    echo "[$(date -Iseconds)] healthy after ${i}s"
    ok=1
    break
  fi
  # detect early crash
  if ! podman container exists "$NAME" 2>/dev/null || [[ "$(podman inspect -f "{{.State.Status}}" "$NAME" 2>/dev/null || echo dead)" != "running" ]]; then
    echo "Container died during startup" >&2
    podman logs "$NAME" > "$OUTDIR/server-${TAG}-crash.log" 2>&1 || true
    podman rm "$NAME" 2>/dev/null || true
    exit 2
  fi
  sleep 2
done
if [[ $ok -ne 1 ]]; then
  echo "Health timeout" >&2
  podman logs "$NAME" > "$OUTDIR/server-${TAG}-timeout.log" 2>&1 || true
  podman stop -t 60 "$NAME" || true
  podman logs "$NAME" >> "$OUTDIR/server-${TAG}-timeout.log" 2>&1 || true
  podman rm "$NAME" || true
  exit 3
fi

BENCH_RC=0
if [[ "${SKIP_BENCH:-0}" != "1" ]]; then
  export N_REPS
  export SERVER_LOG="$OUTDIR/server-${TAG}-live.log"
  # poll live logs in background while bench runs
  ( while podman container exists "$NAME" 2>/dev/null && [[ "$(podman inspect -f "{{.State.Running}}" "$NAME" 2>/dev/null)" == "true" ]]; do
      podman logs "$NAME" > "$SERVER_LOG" 2>&1 || true
      sleep 15
    done ) &
  POLL_PID=$!
  set +e
  if [[ -n "${PROMPT_FILTER:-}" ]]; then
    # temporary prompt dir with filtered prompts
    TMPD=$(mktemp -d)
    cp "$HOME/bench/ds-agent-prompts/"${PROMPT_FILTER} "$TMPD/" 2>/dev/null || true
    PROMPT_DIR="$TMPD" N_REPS="$N_REPS" SERVER_LOG="$SERVER_LOG" \
      "$HOME/bin/evo-bench-ds-agent.sh" 8091 "$TAG" "$OUTDIR"
    BENCH_RC=$?
    rm -rf "$TMPD"
  else
    N_REPS="$N_REPS" SERVER_LOG="$SERVER_LOG" \
      "$HOME/bin/evo-bench-ds-agent.sh" 8091 "$TAG" "$OUTDIR"
    BENCH_RC=$?
  fi
  set -e
  kill "$POLL_PID" 2>/dev/null || true
  wait "$POLL_PID" 2>/dev/null || true
  echo "bench_rc=$BENCH_RC"
fi

echo "[$(date -Iseconds)] stopping $NAME"
podman stop -t 60 "$NAME"
podman logs "$NAME" > "$OUTDIR/server-${TAG}-full.log" 2>&1
# Extract DSpark stats
grep -E "DSpark stats|decoding|scheduler|accept_rate|error|Error|FATAL" "$OUTDIR/server-${TAG}-full.log" \
  > "$OUTDIR/server-${TAG}-extract.txt" 2>/dev/null || true
podman rm "$NAME"
echo "[$(date -Iseconds)] DONE $TAG"
exit $BENCH_RC
