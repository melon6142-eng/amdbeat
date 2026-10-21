#!/bin/bash
# PHASE 2 — DO NOT RUN without go. Takes 8216 down, restores at end.
set -u
B=$HOME/opt/unsloth-llama-b10698-mix-vulkan; export LD_LIBRARY_PATH=$B
O=$MODELS_DIR/gguf/Qwen3.8-27B; K=$HOME/kl-eval; R=$K/results; mkdir -p $R
REF=$O/ref-Qwen3.8-27B-Q8_0-from-BF16.gguf
CH=100
COMMON="-c 512 --chunks $CH --device Vulkan0 -ngl 99 -fa on -b 512"
declare -A Q=( [ud-q6k]=$O/Qwen3.8-27B-UD-Q6_K.gguf [bart-q6k]=$O/bartowski-Qwen3.8-27B-Q6_K.gguf [ud-q5kxl]=$O/Qwen3.8-27B-UD-Q5_K_XL.gguf [bart-q5km]=$O/bartowski-Qwen3.8-27B-Q5_K_M.gguf )
until curl -s localhost:8216/slots | python3 -c "import sys,json; sys.exit(any(x[is_processing] for x in json.load(sys.stdin)))"; do echo "$(date -Is) 8216 busy" >> $R/timeline.txt; sleep 30; done
echo "$(date -Is) 8216 DOWN" >> $R/timeline.txt
kill $(cat $HOME/logs/serve-qwen38-27b-ud-q6k.pid) 2>/dev/null; sleep 5
for corp in wiki code; do
  T=$K/$corp.test.raw; BASE=$K/base-$corp-q8.kld
  $B/llama-perplexity -m $REF -f $T $COMMON --kl-divergence-base $BASE > $R/ref-$corp.log 2>&1
  for n in "${!Q[@]}"; do
    $B/llama-perplexity -m ${Q[$n]} $COMMON --kl-divergence-base $BASE --kl-divergence > $R/$n-$corp.log 2>&1
  done
done
$HOME/kl-eval/load-test.sh
rm -f $HOME/logs/serve-qwen38-27b-ud-q6k.pid; $HOME/bin/serve-qwen38-27b-ud-q6k.sh
for i in $(seq 1 60); do curl -s --max-time 2 localhost:8216/v1/models | grep -q qwen && break; sleep 3; done
echo "$(date -Is) 8216 UP" >> $R/timeline.txt
echo KL_ALL_DONE >> $R/done.txt
