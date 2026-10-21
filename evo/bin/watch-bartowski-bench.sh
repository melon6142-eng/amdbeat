#!/bin/bash
F=$MODELS_DIR/gguf/Qwen3.8-27B/bartowski-Qwen3.8-27B-Q6_K.gguf; E=23860565728
L=$HOME/logs/watch-bartowski-bench.log
log(){ echo "$(date -Is) $*" >> $L; }
until [ "$(stat -c%s $F)" = "$E" ]; do sleep 60; done
log "download complete"
until curl -s localhost:8216/slots | python3 -c "import sys,json; sys.exit(any(s[\"is_processing\"] for s in json.load(sys.stdin)))"; do log "8216 busy, waiting"; sleep 30; done
kill $(cat $HOME/logs/serve-qwen38-27b-ud-q6k.pid); sleep 5; log "8216 stopped"
$HOME/bin/bench-vk.sh $F > $HOME/logs/bench-vk-bartowski.log 2>&1
log "bench done"
rm -f $HOME/logs/serve-qwen38-27b-ud-q6k.pid; $HOME/bin/serve-qwen38-27b-ud-q6k.sh >> $L
for i in $(seq 1 60); do curl -s --max-time 2 localhost:8216/v1/models | grep -q qwen && { log "8216 restored"; exit 0; }; sleep 3; done
log "RESTORE FAIL"
