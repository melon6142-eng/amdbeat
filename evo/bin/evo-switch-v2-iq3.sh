#!/bin/bash
# EVO switch: 8217 halogen 0.18.4+w4b -> 0.18.11+v2 ; 8216 Strata Coder IQ1_M -> IQ3_XXS (resident budget 9; KV8 on 8217).
# PREPARED 2026-10-19, NOT RUN. Usage: evo-switch-v2-iq3.sh [--check] | --go | --rollback
# Log: ~/logs/evo-switch-v2-iq3.log   State (old container name): ~/backups/evo-switch.state
set -u
LOG=$HOME/logs/evo-switch-v2-iq3.log; exec > >(tee -a "$LOG") 2>&1
ts=$(date +%Y%m%d-%H%M%S); say(){ echo "$(date +%T) $*"; }; die(){ say "ABORT: $*"; exit 1; }
NEWIMG=ghcr.io/peonist-ai/halogen-flash-server:0.18.11
OLDIMG=localhost/halogen-flash-server:0.18.4-rollback
SD=$HOME/sparkdash-llm/qwen38-27b
M=$HOME/src/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf
PACK=$HOME/src/Strata-data/packs/iq3_xxs
ST=$HOME/backups/evo-switch.state
run_halogen(){ # $1 image  $2 env-file
  podman run -d --name halogen --env-file "$2" -e HIP_VISIBLE_DEVICES=1 --device /dev/kfd --device /dev/dri \
    --group-add keep-groups --security-opt label=disable --ulimit memlock=-1:-1 --ulimit nofile=1048576:1048576 \
    -v $HOME/halogen-models:/models:ro -p 8217:8731 "$1" all; }
wait_url(){ # $1 url $2 tries(x5s)
  for i in $(seq 1 $2); do curl -sf -m 5 "$1" >/dev/null && return 0; sleep 5; done; return 1; }
smoke(){ curl -s -m 120 localhost:$1/v1/chat/completions -H "Content-Type: application/json" \
  -d "{\"model\":\"x\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK.\"}],\"max_tokens\":64}" | head -c 300; echo; }
mem(){ free -g | sed -n 2p; echo "R9700 vram $(( $(cat /sys/bus/pci/devices/0000:67:00.0/mem_info_vram_used)/1048576 ))MiB, GTT $(( $(cat /sys/bus/pci/devices/0000:68:00.0/mem_info_gtt_used)/1048576 ))MiB"; }

precheck(){
  ok=1
  for f in "$M.done" $HOME/halogen-models/qwen38-flash-next-v2.hgn.done $HOME/halogen-models/qwen38-flash-next-ngram.hgn.done; do
    [ -f "$f" ] && say "ok  $f" || { say "MISSING $f"; ok=0; }; done
  podman image exists $NEWIMG && say "ok  image $NEWIMG" || { say "MISSING image $NEWIMG"; ok=0; }
  podman image exists $OLDIMG && say "ok  rollback image $OLDIMG" || { say "MISSING rollback image"; ok=0; }
  for f in $HOME/halogen-v2.env $HOME/src/strata-0140/strata-iq3_xxs-r9700-8216-v2.json $SD/start.sh.next $SD/stop.sh.next $HOME/strata-8216.sh.next; do
    [ -f "$f" ] || { say "MISSING $f"; ok=0; }; done
  df -h / | tail -1; mem
  [ $ok = 1 ]; }

go(){
  precheck || die "precheck failed"
  # 1. Strata pack for IQ3_XXS (seconds; no download)
  if [ ! -f $PACK/native_experts.txt ] || [ ! -d $PACK/tokenizer ]; then
    say "building pack $PACK"; cd $HOME/src/strata-0140 || die cd
    ./.venv/bin/python tools/iq_pack.py --gguf "$M" --out $PACK || die "iq_pack failed"
    [ -d $PACK/tokenizer ] || ./.venv/bin/python tools/strata_tokenizer.py --gguf "$M" --out $PACK || die "tokenizer failed"
  fi
  # 2. install the generic 8216 launchers (config chosen by ~/strata-8216.conf), keep old copies
  for f in $SD/start.sh $SD/stop.sh $HOME/strata-8216.sh; do cp -p $f $f.pre-v2iq3-$ts; done
  # 3. stop 8216 Strata (Coder) via its CURRENT launcher stop.sh
  say "stopping 8216"; $SD/stop.sh; sleep 3
  pgrep -f "serve.server --engine strata --config strata-.*-r9700-8216" && die "8216 still running"
  cp -p $SD/start.sh.next $SD/start.sh; cp -p $SD/stop.sh.next $SD/stop.sh; cp -p $HOME/strata-8216.sh.next $HOME/strata-8216.sh
  # 4. back up 8217 container config, stop it, keep it (renamed) for rollback
  mkdir -p $HOME/backups; podman container inspect halogen > $HOME/backups/halogen-0184-w4b-$ts.inspect.json
  cp -p $HOME/halogen.env $HOME/backups/halogen.env.0184-w4b-$ts
  say "stopping 8217 (halogen 0.18.4 w4b)"; podman stop -t 60 halogen || die "podman stop failed"
  podman rename halogen halogen-w4b-0184-$ts || die "rename failed"; echo "OLD=halogen-w4b-0184-$ts" > $ST
  mem
  # 5. start 8217 on 0.18.11 + v2 (same port, ctx 262144, pool 524288 default, 4 slots, prompt cache 2, MAX_TOK 16384)
  say "starting 8217 (halogen 0.18.11 v2)"; run_halogen $NEWIMG $HOME/halogen-v2.env || { say "run failed -> rollback"; rollback; exit 1; }
  wait_url localhost:8217/health 120 || { podman logs --tail 60 halogen; say "8217 not healthy in 10 min -> rollback"; rollback; exit 1; }
  curl -s -m 5 localhost:8217/health | grep -o -E "\"(kv_cache|version)\":[^}]*" ; curl -s -m 5 localhost:8217/health | head -c 300; echo; curl -s -m 5 localhost:8217/v1/models | head -c 200; echo; smoke 8217
  podman logs halogen 2>&1 | grep -E "memory:|kv pool|checkpoint:|host memory left" | head -12; mem
  # 6. start 8216 Strata IQ3_XXS (budget 16) via the sparkDash launcher
  echo "CFG=strata-iq3_xxs-r9700-8216-v2.json" > $HOME/strata-8216.conf
  say "starting 8216 (Strata IQ3_XXS)"; (cd $SD && setsid nohup ./start.sh > $HOME/logs/luncher-8216-$ts.log 2>&1 < /dev/null &)
  wait_url localhost:8216/v1/models 120 || { tail -40 $HOME/logs/strata-8216-console.log; say "8216 not up in 10 min (8217 stays on v2). Fix or: $0 --rollback"; exit 1; }
  curl -s -m 5 localhost:8216/health | head -c 200; echo; curl -s -m 5 localhost:8216/v1/models | head -c 200; echo; smoke 8216
  grep -E "expert cache|resident RAM|KV|slot" $HOME/logs/strata-8216.log | tail -8; mem
  say "DONE. 8217=halogen 0.18.11 v2, 8216=Strata IQ3_XXS. Rollback: $0 --rollback"; }

rollback(){
  say "ROLLBACK to halogen 0.18.4 w4b + Strata Coder IQ1_M"
  [ -x $SD/stop.sh ] && $SD/stop.sh; sleep 3
  OLD=$(sed -n "s/^OLD=//p" $ST 2>/dev/null)
  if podman container exists halogen && [ "$(podman inspect halogen --format "{{.ImageName}}")" != "ghcr.io/peonist-ai/halogen-flash-server:0.18.4" ]; then
    podman stop -t 60 halogen; podman rm halogen; fi
  if ! podman container exists halogen; then
    if [ -n "$OLD" ] && podman container exists "$OLD"; then podman rename "$OLD" halogen && podman start halogen
    else run_halogen $OLDIMG $HOME/halogen.env; fi
  fi
  wait_url localhost:8217/health 120 && say "8217 healthy (w4b)" || say "8217 NOT healthy - check podman logs halogen"
  echo "CFG=strata-coder-iq1_m-r9700-8216.json" > $HOME/strata-8216.conf
  (cd $SD && setsid nohup ./start.sh > $HOME/logs/luncher-8216-rb-$ts.log 2>&1 < /dev/null &)
  wait_url localhost:8216/v1/models 120 && say "8216 up (Coder IQ1_M)" || say "8216 NOT up - see ~/logs/strata-8216-console.log"
  mem; }

case "${1:---check}" in
  --check) precheck && say "precheck OK (nothing changed)" || say "precheck: not ready";;
  --go) go;;
  --rollback) rollback;;
  *) echo "usage: $0 [--check] | --go | --rollback";;
esac
