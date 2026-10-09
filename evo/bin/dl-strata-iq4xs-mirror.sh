#!/bin/bash
# UD-IQ4_XS via hf-mirror, resumable, sha256 verified
D=$HOME/src/Strata-data/models/unsloth-UD-IQ4_XS
B=https://modelscope.cn/models/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/master/UD-IQ4_XS
cd "$D" || exit 1
get() { f=$1; sz=$2; sh=$3
  for i in $(seq 1 200); do
    cur=$(stat -c %s "$f" 2>/dev/null || echo 0)
    [ "$cur" = "$sz" ] && break
    echo "$(date +%T) $f try $i at $cur"
    wget -4 -c -q --tries=3 --timeout=30 --read-timeout=60 -O "$f" "$B/$f"
    sleep 3
  done
  echo "$(date +%T) $f size ok, hashing"
  h=$(sha256sum "$f" | cut -d" " -f1)
  if [ "$h" = "$sh" ]; then touch "$f.done"; echo "$f SHA OK"; else echo "$f SHA BAD $h"; fi
}
get Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf 10946624 5ce89370720f8bf90890f439361282104c1aa1482d4013bb9a50923e758e71a4
get Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf 49835229856 577a38a2392b40ca2193cea502e1d92f60b8cd370675d308e0ec21885d9daaa7 &
get Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf 43836407744 d4634e6d84f0ebb0940be15c90d3790bf6464e3dea3a1cddc567dc0e83ad8833 &
wait
echo ALLDONE
