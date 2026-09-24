#!/usr/bin/env bash
set -uo pipefail
OUTDIR="$HOME/logs/ds-matrix-20260924"
export OUTDIR
export N_REPS=3
unset PROMPT_FILTER
MTP=/models/DeepSeek-V4-Flash-DSpark-support-0731.gguf
LOG="$OUTDIR/matrix-master.log"
run_row() {
  local tag="$1"; shift
  echo "======== $(date -Iseconds) BEGIN $tag ========" | tee -a "$LOG"
  set +e
  "$HOME/bin/evo-ds4-matrix-row.sh" "$tag" "$@" >>"$LOG" 2>&1
  local rc=$?
  set -e
  echo "======== $(date -Iseconds) END $tag rc=$rc ========" | tee -a "$LOG"
  # ensure port free
  sleep 2
  if ss -ltn | grep -q ":8091 "; then
    echo "WARN 8091 still up after $tag" | tee -a "$LOG"
  fi
  return 0
}

# A: ordinary
run_row A --

# B: conf 0.5 + STATS
run_row B -e DS4_DSPARK_STATS=1 -- --dspark --mtp-model "$MTP" --dspark-confidence 0.5

# C: conf 0.7
run_row C -e DS4_DSPARK_STATS=1 -- --dspark --mtp-model "$MTP" --dspark-confidence 0.7

# E: B + TAIL_MIN=128 + COLD_SKIP=16
run_row E -e DS4_DSPARK_STATS=1 \
  -e DS4_DSPARK_SCHEDULER_TAIL_MIN_TOKENS=128 \
  -e DS4_DSPARK_SCHEDULER_COLD_LOW_CONFIDENCE_SKIP=16 \
  -- --dspark --mtp-model "$MTP" --dspark-confidence 0.5

# F: conf 0.3
run_row F -e DS4_DSPARK_STATS=1 -- --dspark --mtp-model "$MTP" --dspark-confidence 0.3

# D: B + SCHEDULER=0
run_row D -e DS4_DSPARK_STATS=1 -e DS4_DSPARK_SCHEDULER=0 \
  -- --dspark --mtp-model "$MTP" --dspark-confidence 0.5

# G: B + --mtp-exact-sampling
run_row G -e DS4_DSPARK_STATS=1 \
  -- --dspark --mtp-model "$MTP" --dspark-confidence 0.5 --mtp-exact-sampling

echo "======== $(date -Iseconds) MATRIX COMPLETE ========" | tee -a "$LOG"
