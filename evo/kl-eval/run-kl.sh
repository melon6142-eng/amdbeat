#!/bin/bash
set -u
B=$HOME/code/llama.cpp-master/build-hip/bin; export LD_LIBRARY_PATH=$B HIP_VISIBLE_DEVICES=0
O=${MODELS_DIR:-$HOME/models}/gguf/Qwen3.8-27B; K=$HOME/kl-eval; R=$K/results; mkdir -p $R
REF=$O/ref-Qwen3.8-27B-Q8_0-from-BF16.gguf
COMMON="-c 512 --chunks 100 -ngl 99 -fa on -b 512"
Q="iq4xs:$O/Qwen3.8-27B-UD-IQ4_XS.gguf q4km:$O/Qwen3.8-27B-UD-Q4_K_M.gguf q4kxl:$O/Qwen3.8-27B-UD-Q4_K_XL.gguf q5kxl:$O/Qwen3.8-27B-UD-Q5_K_XL.gguf q6k:$O/Qwen3.8-27B-UD-Q6_K.gguf bart-q6k:$O/bartowski-Qwen3.8-27B-Q6_K.gguf"
until curl -s localhost:8216/slots | python3 -c "import sys,json; sys.exit(any(x['is_processing'] for x in json.load(sys.stdin)))"; do sleep 30; done
echo "$(date -Is) 8216 DOWN" >> $R/timeline.txt
kill $(cat $HOME/logs/serve-qwen38-27b-ud-q6k.pid) 2>/dev/null; sleep 5
for corp in wiki code; do
  BASE=$K/base-$corp-q8.kld
  $B/llama-perplexity -m $REF -f $K/$corp.test.raw $COMMON --kl-divergence-base $BASE > $R/ref-$corp.log 2>&1
  echo "$(date -Is) ref $corp done" >> $R/timeline.txt
  for p in $Q; do n=${p%%:*}; m=${p#*:}
    $B/llama-perplexity -m $m $COMMON --kl-divergence-base $BASE --kl-divergence > $R/$n-$corp.log 2>&1
    echo "$(date -Is) $n $corp done" >> $R/timeline.txt; done
  rm -f $BASE
done
rm -f $HOME/logs/serve-qwen38-27b-ud-q6k.pid; $HOME/bin/serve-qwen38-27b-ud-q6k.sh
for i in $(seq 1 60); do curl -s --max-time 2 localhost:8216/v1/models | grep -q q4kxl && break; sleep 3; done
echo "$(date -Is) 8216 UP" >> $R/timeline.txt; echo KL_ALL_DONE >> $R/done.txt
