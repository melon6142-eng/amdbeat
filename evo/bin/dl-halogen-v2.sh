#!/bin/bash
# halogen v2 checkpoint + its n-gram table via modelscope (hf-mirror was ~1 MB/s), sequential; resumable, size+sha256 verified, .done markers.
# Single instance (flock). Cron watchdog (*/5) restarts it until both .done exist. Log: ~/logs/dl-halogen-v2.log
exec 9>/tmp/dl-halogen-v2.lock; flock -n 9 || exit 0
[ -f $HOME/src/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf.done ] || { echo "$(date +%FT%T) waiting for IQ3_XXS to finish first (sequential, shared WAN)"; exit 0; }
D=$HOME/halogen-models; cd "$D" || exit 1
B=https://modelscope.cn/models/peonist-ai/halogen-qwen3.8-flash-next/resolve/master
get() { F=$1; SZ=$2; SH=$3
  [ -f "$F.done" ] && { echo "$(date +%FT%T) $F already done"; return 0; }
  for i in $(seq 1 500); do
    cur=$(stat -c %s "$F" 2>/dev/null || echo 0); [ "$cur" -ge "$SZ" ] && break
    echo "$(date +%FT%T) $F try $i at $cur"
    curl -sSL -4 -C - --retry 3 --retry-delay 5 --connect-timeout 30 --speed-limit 102400 --speed-time 120 -o "$F" "$B/$F"
    echo "$(date +%FT%T) $F curl_exit=$? size=$(stat -c %s "$F" 2>/dev/null)"; sleep 5
  done
  cur=$(stat -c %s "$F" 2>/dev/null || echo 0)
  [ "$cur" = "$SZ" ] || { echo "$(date +%FT%T) $F SIZE BAD $cur (expected $SZ)"; return 1; }
  echo "$(date +%FT%T) $F size ok, hashing"; h=$(sha256sum "$F" | cut -d" " -f1)
  if [ "$h" = "$SH" ]; then echo "$SZ $h $(date +%FT%T)" > "$F.done"; echo "$(date +%FT%T) $F SHA OK"; else echo "$(date +%FT%T) $F SHA BAD $h"; mv "$F" "$F.bad"; return 1; fi
}
get qwen38-flash-next-v2.hgn 66687678432 71246c6ab3fc1de2cf06326f18e275fe9c2a18366d646ed3357d194c884fc687 || exit 1
get qwen38-flash-next-ngram.hgn 51200246144 3450acada94e19aabad88bd49b45eb70304820949c2240fc178067b20ae5dffe || exit 1
echo "$(date +%FT%T) ALL DONE (tokenizer/ reused: identical to repo)"
