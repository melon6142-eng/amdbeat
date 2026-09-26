#!/usr/bin/env bash
# halogen-ctl — load / unload Qwen3.8-Flash-Next (halogen) on this EVO
set -euo pipefail

NAME="halogen-flash"
IMAGE="ghcr.io/peonist-ai/halogen-flash-server:0.13.4"
MODELS_DIR="${HALOGEN_MODELS_DIR:-$HOME/halogen-models}"
CHECKPOINT="/models/qwen38-flash-next-w4b.hgn"
TOKENIZER="/models/tokenizer"
HOST_PORT="8731"
HEALTH_URL="http://127.0.0.1:${HOST_PORT}/health"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

need_models() {
  local w="$MODELS_DIR/qwen38-flash-next-w4b.hgn"
  local o="$MODELS_DIR/qwen38-flash-next-w4b.overlay.hgn"
  local t="$MODELS_DIR/tokenizer"
  [[ -f "$w" ]] || { red "missing weights: $w"; return 1; }
  [[ -f "$o" ]] || { red "missing overlay: $o"; return 1; }
  [[ -d "$t" ]] || { red "missing tokenizer: $t"; return 1; }
}

container_exists() { podman container exists "$NAME" 2>/dev/null; }
container_running() {
  [[ "$(podman inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" == "true" ]]
}

wait_health() {
  local i
  yellow "waiting for health on :${HOST_PORT} (first load can take a few minutes)…"
  for i in $(seq 1 180); do
    if curl -fsS -m 2 "$HEALTH_URL" >/dev/null 2>&1; then
      green "healthy"
      curl -fsS -m 3 "$HEALTH_URL" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("model:", d.get("model")); print("version:", (d.get("version") or {}).get("api")); print("busy:", d.get("busy"), "in_flight:", d.get("in_flight"))' 2>/dev/null || true
      return 0
    fi
    sleep 2
  done
  red "timed out waiting for health"
  return 1
}

cmd_create() {
  need_models
  yellow "creating $NAME from $IMAGE …"
  # GPU nodes are visible with: --device kfd/dri, --ipc=host, seccomp=unconfined,
  # keep-groups, raised memlock (matches the live container we audited).
  podman run -d --name "$NAME" \
    --replace \
    --ipc=host \
    --security-opt seccomp=unconfined \
    --annotation run.oci.keep_original_groups=1 \
    --device /dev/kfd \
    --device /dev/dri \
    --ulimit memlock=-1 \
    --ulimit nofile=1048576 \
    -p "${HOST_PORT}:8731" \
    -v "$MODELS_DIR:/models:ro" \
    -e HALOGEN_CHECKPOINT="$CHECKPOINT" \
    -e HALOGEN_TOKENIZER="$TOKENIZER" \
    -e HALOGEN_CTX=131072 \
    -e HALOGEN_KV_POOL_POSITIONS=131072 \
    -e HALOGEN_KV_SLOTS=2 \
    -e HALOGEN_MAX_TOK=65536 \
    -e HALOGEN_FLASH_PIN_TRUNK=1 \
    -e HALOGEN_PROMPT_CACHE=2 \
    -e HALOGEN_API_PORT=8731 \
    -e HALOGEN_PORT=8730 \
    -e HALOGEN_BIND=127.0.0.1 \
    -e HALOGEN_ARCH=gfx1151 \
    "$IMAGE" all
}

cmd_load() {
  need_models
  if container_running; then
    green "already loaded (running)"
    cmd_status
    return 0
  fi
  if container_exists; then
    yellow "starting existing container $NAME …"
    podman start "$NAME" >/dev/null
  else
    cmd_create
  fi
  wait_health
  green "loaded — http://EVO_HOST:${HOST_PORT}/v1  (model halogen-qwen3.8-flash-next)"
  yellow "note: PIN_TRUNK keeps ~65–75 GiB in RAM; unload before another big model"
}

cmd_unload() {
  if ! container_exists; then
    yellow "nothing to unload (no container)"
    return 0
  fi
  if ! container_running; then
    yellow "already unloaded (stopped)"
    cmd_status
    return 0
  fi
  yellow "stopping $NAME (frees host RAM / GTT) …"
  podman stop -t 30 "$NAME" >/dev/null
  green "unloaded"
  free -h | head -2
}

cmd_rm() {
  cmd_unload || true
  if container_exists; then
    yellow "removing container $NAME …"
    podman rm "$NAME" >/dev/null
    green "removed (next load will re-create)"
  else
    yellow "already removed"
  fi
}

cmd_restart() {
  cmd_unload || true
  cmd_load
}

cmd_status() {
  echo "=== container ==="
  if container_exists; then
    podman ps -a --filter "name=^${NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  else
    yellow "container missing"
  fi
  echo
  echo "=== health ==="
  if curl -fsS -m 2 "$HEALTH_URL" >/dev/null 2>&1; then
    curl -fsS -m 3 "$HEALTH_URL" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("ok", d.get("model"), "api", (d.get("version") or {}).get("api"), "busy", d.get("busy"), "in_flight", d.get("in_flight"), "ctx", d.get("context"))'
  else
    yellow "API not responding on :${HOST_PORT}"
  fi
  echo
  echo "=== memory / GPU ==="
  free -h | head -2
  if command -v rocm-smi >/dev/null 2>&1; then
    rocm-smi --showuse --showtemp --showmeminfo vram 2>/dev/null | head -40 || true
  fi
  if command -v amd-smi >/dev/null 2>&1; then
    true
  fi
}

cmd_logs() {
  podman logs --tail "${1:-80}" -f "$NAME"
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") <command>

  load      Start halogen (create if needed) and wait until healthy
  unload    Stop halogen and free RAM/GTT (keeps the container)
  restart   unload then load
  status    Container + health + RAM/GPU snapshot
  logs [N]  Follow last N log lines (default 80)
  rm        Stop and delete the container (next load re-creates)

Model: qwen38-flash-next-w4b (+ overlay) under:
  $MODELS_DIR
API:   http://127.0.0.1:${HOST_PORT}/v1
USAGE
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    load|start|on)     cmd_load "$@" ;;
    unload|stop|off)   cmd_unload "$@" ;;
    restart)           cmd_restart "$@" ;;
    status|st)         cmd_status "$@" ;;
    logs|log)          cmd_logs "$@" ;;
    rm|remove|delete)  cmd_rm "$@" ;;
    -h|--help|help|"") usage ;;
    *) red "unknown: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
