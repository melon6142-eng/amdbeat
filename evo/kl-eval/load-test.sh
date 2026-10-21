#!/bin/bash
# 8216 load-time test. Assumes 8216 down. Leaves 8216 DOWN (run-kl restores).
V=$HOME/bin/vmtouch; S=$HOME/bin/serve-qwen38-27b-ud-q6k.sh
PF=$HOME/logs/serve-qwen38-27b-ud-q6k.pid
F1=${MODELS_DIR:-$HOME/models}/gguf/Qwen3.8-27B/Qwen3.8-27B-UD-Q6_K.gguf; F2=${MODELS_DIR:-$HOME/models}/gguf/Qwen3.8-27B/mtp-Qwen3.8-27B-Q4_0.gguf
O=$HOME/kl-eval/results/loadtest.txt
avail(){ awk "/MemAvailable/{printf \"%.1f\", \$2/1048576}" /proc/meminfo; }
c8217(){ echo "8217=$(curl -s -o /dev/null -w %{http_code} --max-time 3 localhost:8217/v1/models)"; }
stop(){ kill $(cat $PF) 2>/dev/null; for i in $(seq 1 30); do ss -tnl | grep -q :8216 || break; sleep 1; done; sleep 2; rm -f $PF; }
one(){ t0=$(date +%s.%N); $S >/dev/null
  until curl -s --max-time 1 localhost:8216/v1/models | grep -q qwen; do sleep 0.2; done; t1=$(date +%s.%N)
  curl -s --max-time 120 localhost:8216/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\":\"qwen3.8-27b-ud-q6k\",\"messages\":[{\"role\":\"user\",\"content\":\"Say pong.\"}],\"max_tokens\":8,\"chat_template_kwargs\":{\"enable_thinking\":false}}" >/dev/null; t2=$(date +%s.%N)
  echo "$1 models_ok=$(echo "$t1-$t0"|bc) first_completion=$(echo "$t2-$t0"|bc) avail=$(avail)GiB $(c8217)" | tee -a $O; stop; }
echo "=== loadtest $(date -Is) avail_start=$(avail)GiB $(c8217)" >> $O
for r in 1 2 3; do $V -e $F1 $F2 >/dev/null; echo "cold$r after-evict avail=$(avail)" >> $O; one cold$r; done
if awk -v a=$(avail) "BEGIN{exit !(a>=45)}"; then
  $V -t $F1 $F2 >/dev/null; echo "after warm avail=$(avail)GiB" >> $O
  for r in 1 2 3; do one warm$r; done
  $V -dl -P /tmp/vmtouch-8216.pid $F1 $F2; sleep 30; echo "after lock avail=$(avail)GiB $(c8217)" >> $O
  for r in 1 2 3; do one locked$r; done
  kill $(cat /tmp/vmtouch-8216.pid) 2>/dev/null; echo "lock released avail=$(avail)GiB" >> $O
else echo "SKIP warm/locked: avail<45GiB" >> $O; fi
echo "=== end $(date -Is) avail=$(avail)GiB $(c8217) halogen=$(pgrep -fc halogen)" >> $O
