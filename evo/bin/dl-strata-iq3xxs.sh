#!/bin/bash
# Strata Qwen3.8 Flash-Next GSQ-RCO IQ3_XXS shard 1 via modelscope (hf-mirror was ~1 MB/s); resumable, size+sha256 verified, .done marker.
# Single instance (flock). Started by cron watchdog (*/5) if not done. Log: ~/logs/dl-strata-iq3xxs.log
exec 9>/tmp/dl-strata-iq3xxs.lock; flock -n 9 || exit 0
D=$HOME/src/Strata-data/models/IQ3_XXS; cd "$D" || exit 1
F=Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf
SZ=47039860096; SH=219ea929900dfa9ef091f3aa473fdba6874b65fcb36526d7d851ac9e95856d15
U=https://modelscope.cn/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/master/IQ3_XXS/$F
[ -f "$F.done" ] && { echo "$(date +%FT%T) already done"; exit 0; }
for i in $(seq 1 500); do
  cur=$(stat -c %s "$F" 2>/dev/null || echo 0)
  [ "$cur" -ge "$SZ" ] && break
  echo "$(date +%FT%T) try $i at $cur"
  curl -sSL -4 -C - --retry 3 --retry-delay 5 --connect-timeout 30 --speed-limit 102400 --speed-time 120 -o "$F" "$U"
  echo "$(date +%FT%T) curl_exit=$? size=$(stat -c %s "$F" 2>/dev/null)"
  sleep 5
done
cur=$(stat -c %s "$F" 2>/dev/null || echo 0)
[ "$cur" = "$SZ" ] || { echo "$(date +%FT%T) SIZE BAD $cur (expected $SZ)"; exit 1; }
echo "$(date +%FT%T) size ok, hashing"
h=$(sha256sum "$F" | cut -d" " -f1)
if [ "$h" = "$SH" ]; then echo "$SZ $h $(date +%FT%T)" > "$F.done"; echo "$(date +%FT%T) SHA OK - DONE"; else echo "$(date +%FT%T) SHA BAD $h"; mv "$F" "$F.bad"; fi
