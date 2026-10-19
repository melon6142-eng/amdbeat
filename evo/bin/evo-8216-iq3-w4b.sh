set -u
ts=$(date +%Y%m%d-%H%M%S); SD=$HOME/sparkdash-llm/qwen38-27b
M=$HOME/src/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf; PACK=$HOME/src/Strata-data/packs/iq3_xxs
say(){ echo "$(date +%T) $*"; }
cd $HOME/src/strata-0140 || exit 1
if [ ! -f $PACK/native_experts.txt ] || [ ! -d $PACK/tokenizer ]; then
  say "building pack"; ./.venv/bin/python tools/iq_pack.py --gguf "$M" --out $PACK 2>&1 | tail -5 || exit 1
  [ -d $PACK/tokenizer ] || ./.venv/bin/python tools/strata_tokenizer.py --gguf "$M" --out $PACK 2>&1 | tail -3
fi
[ -f $PACK/native_experts.txt ] && [ -d $PACK/tokenizer ] || { say "PACK FAILED; 8216 left on Coder"; exit 1; }
for f in $SD/start.sh $SD/stop.sh $HOME/strata-8216.sh; do cp -p $f $f.pre-iq3w4b-$ts; done
say "stopping 8216 coder"; $SD/stop.sh; sleep 3
pgrep -f "serve.server --engine strata --config strata-.*-r9700-8216" && { say "still running"; exit 1; }
cp -p $SD/start.sh.next $SD/start.sh; cp -p $SD/stop.sh.next $SD/stop.sh; cp -p $HOME/strata-8216.sh.next $HOME/strata-8216.sh
echo "CFG=strata-iq3_xxs-r9700-8216-w4b.json" > $HOME/strata-8216.conf
say "starting 8216 IQ3_XXS (w4b budget)"; (cd $SD && setsid nohup ./start.sh > $HOME/logs/launcher-8216-$ts.log 2>&1 < /dev/null &)
for i in $(seq 1 120); do curl -sf -m 5 localhost:8216/v1/models >/dev/null && break; sleep 5; done
curl -s -m5 localhost:8216/v1/models; echo; tail -5 $HOME/logs/strata-8216-console.log
say done
