#!/usr/bin/env bash
# stops only the 8216 Strata server (+ its engine child). Does not touch 8217.
PAT="serve.server --engine strata --config strata-coder-iq1_m-r9700-8216.json"
pkill -TERM -f "$PAT" || { echo "not running"; exit 0; }
for i in $(seq 1 40); do pgrep -f "engine/strata --serve.*--batch 4 --resident-budget-gib 12" >/dev/null || { echo "strata 8216 stopped"; exit 0; }; sleep 1; done
pkill -KILL -f "engine/strata --serve.*--batch 4 --resident-budget-gib 12"; echo "strata 8216 killed"
