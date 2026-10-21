#!/bin/bash
O=$MODELS_DIR/gguf/Qwen3.8-27B; L=$HOME/logs/dl-speed-quants.log; U=https://modelscope.cn/models/unsloth/Qwen3.8-27B-GGUF/resolve/master
for p in "UD-Q4_K_XL 17559178144" "UD-Q4_K_M 16464440224" "UD-IQ4_XS 14252845984"; do set -- $p; d=$O/Qwen3.8-27B-$1.gguf
 for i in $(seq 1 300); do [ "$(stat -c%s $d 2>/dev/null)" = "$2" ] && break; curl -4 -sSL -C - --retry 5 --connect-timeout 30 --speed-limit 51200 --speed-time 180 -o $d $U/Qwen3.8-27B-$1.gguf; sleep 3; done
 echo "$(date -Is) DONE $1 $(stat -c%s $d)" >> $L; done
