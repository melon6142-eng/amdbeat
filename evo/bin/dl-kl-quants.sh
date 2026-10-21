#!/bin/bash
O=$MODELS_DIR/gguf/Qwen3.8-27B; L=$HOME/logs/dl-kl-quants.log
log(){ echo "$(date -Is) $*" >> $L; }
dl(){ u=$1; d=$2; e=$3; for i in $(seq 1 300); do c=$(stat -c%s $d 2>/dev/null||echo 0); [ "$c" = "$e" ] && break; curl -4 -sSL -C - --retry 5 --connect-timeout 30 --speed-limit 51200 --speed-time 180 -o $d "$u"; sleep 5; done; c=$(stat -c%s $d); [ "$c" = "$e" ] && { echo "$c" > $d.done; log "DONE $d"; } || log "FAIL $d $c"; }
U=https://modelscope.cn/models/unsloth/Qwen3.8-27B-GGUF/resolve/master
B=https://modelscope.cn/models/bartowski/Qwen3.8-27B-GGUF/resolve/master
dl $U/BF16/Qwen3.8-27B-BF16-00001-of-00002.gguf $O/BF16/Qwen3.8-27B-BF16-00001-of-00002.gguf 49986159616 &
( dl $U/BF16/Qwen3.8-27B-BF16-00002-of-00002.gguf $O/BF16/Qwen3.8-27B-BF16-00002-of-00002.gguf 4671576000
  dl $U/Qwen3.8-27B-UD-Q5_K_XL.gguf $O/Qwen3.8-27B-UD-Q5_K_XL.gguf 20876938144
  dl $B/Qwen3.8-27B-Q5_K_M.gguf $O/bartowski-Qwen3.8-27B-Q5_K_M.gguf 20923877088 ) &
wait; log ALLDONE
# quantize Q8_0 on CPU
if [ -f $O/BF16/Qwen3.8-27B-BF16-00001-of-00002.gguf.done ] && [ -f $O/BF16/Qwen3.8-27B-BF16-00002-of-00002.gguf.done ]; then
  Q=$HOME/opt/unsloth-llama-b10698-mix-vulkan; cd $Q
  log "quantize start"
  LD_LIBRARY_PATH=$Q nice -n 15 ./llama-quantize $O/BF16/Qwen3.8-27B-BF16-00001-of-00002.gguf $O/ref-Qwen3.8-27B-Q8_0-from-BF16.gguf Q8_0 12 > $HOME/logs/quantize-q8.log 2>&1 && log "QUANT DONE" || log "QUANT FAIL"
fi
