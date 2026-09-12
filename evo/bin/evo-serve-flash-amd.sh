#!/usr/bin/env bash
# EVO AMD-only Qwen3.8 Flash-Next ROCmFP4. No RTX 4080.
# Proven on this box: 262k x 1 slot, batch 2048 / ubatch 512, ~23 t/s decode.
# --fit off so context does not shrink. Prompt cache on; --no-host stays off
# because prompt_save + --no-host aborted on this stack.
set -euo pipefail
BIN="${LLAMA_SERVER:-$HOME/code/llama.cpp-rocmfpx/build/bin/llama-server}"
MODEL="${FLASH_GGUF:-$HOME/models/rocmfp4/flash-next/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf}"
DRAFT="${DRAFT:-$HOME/models/gguf/qwen38-flash-mtp/mtp-Qwen3.8-Flash-Next-Q8_0.gguf}"
SPEC_TYPE="${SPEC_TYPE:-draft-mtp,ngram-mod}"
LOG="${HOME}/logs/serve-flashnext-amd-only.log"
PORT="${PORT:-8080}"
CTX="${CTX:-262144}"
PARALLEL="${PARALLEL:-1}"
BATCH="${BATCH:-2048}"
UBATCH="${UBATCH:-512}"
TEMP="${TEMP:-0.7}"
TOP_P="${TOP_P:-0.8}"
TOP_K="${TOP_K:-20}"
CACHE_K="${CACHE_K:-q8_0}"
CACHE_V="${CACHE_V:-q8_0}"
CACHE_RAM="${CACHE_RAM:-8192}"
mkdir -p "$(dirname "$LOG")"
[[ -x $BIN ]] || { echo "missing $BIN"; exit 1; }
[[ -s $MODEL ]] || { echo "missing $MODEL"; exit 1; }
DRAFT_ARGS=()
if [[ -s "$DRAFT" ]]; then
  DRAFT_ARGS=(
    --spec-draft-model "$DRAFT"
    --spec-type "$SPEC_TYPE"
    --spec-draft-n-max "${SPEC_N_MAX:-3}"
    --spec-draft-p-min "${SPEC_P_MIN:-0.0}"
    --spec-ngram-mod-n-max "${NGRAM_MAX:-64}"
    --spec-ngram-mod-n-match "${NGRAM_MATCH:-24}"
    --spec-draft-device Vulkan0
    --spec-draft-ngl 99
  )
fi

fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1

export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="${RADV_PERFTEST:-gpl,sam,nggc}"
unset VK_DRIVER_FILES

nohup "$BIN" -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" --alias qwen38-flash-next-amd \
  --device Vulkan0 --gpu-layers all --flash-attn on --fit off \
  --load-mode mmap \
  --ctx-size "$CTX" --parallel "$PARALLEL" \
  --batch-size "$BATCH" --ubatch-size "$UBATCH" \
  --cache-type-k "$CACHE_K" --cache-type-v "$CACHE_V" \
  --cache-prompt --cache-idle-slots --cache-ram "$CACHE_RAM" \
  "${DRAFT_ARGS[@]}" \
  --jinja --no-webui --metrics \
  --temp "$TEMP" --top-p "$TOP_P" --top-k "$TOP_K" \
  >"$LOG" 2>&1 &
if [[ -s "$DRAFT" ]]; then
  echo "PID=$! log=$LOG port=$PORT alias=qwen38-flash-next-amd device=Vulkan0(AMD) draft=$(basename "$DRAFT") spec=$SPEC_TYPE ctx=$CTX"
else
  echo "PID=$! log=$LOG port=$PORT alias=qwen38-flash-next-amd device=Vulkan0(AMD) draft=none ctx=$CTX"
fi
