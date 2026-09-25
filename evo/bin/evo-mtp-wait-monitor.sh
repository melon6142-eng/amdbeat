#!/usr/bin/env bash
set +e
LOG=~/logs/glm-mtp-wait2.log
echo "ext_monitor_start $(date -Is)" | tee -a "$LOG"
prev_s3=0
stall=0
while true; do
  TS=$(date '+%Y-%m-%d %H:%M:%S CST')
  NOW=$(date +%H%M)
  N=$(ls $MODELS_DIR/gguf/GLM-5.3-Flash-UD-IQ2_XXS/GLM-5.3-Flash-UD-IQ2_XXS-0000*-of-00004.gguf 2>/dev/null | wc -l)
  S3=$(python3 -c "import os;p=os.path.expanduser('$MODELS_DIR/gguf/GLM-5.3-Flash-UD-IQ2_XXS/.parts/GLM-5.3-Flash-UD-IQ2_XXS-00003-of-00004.gguf');print(sum(os.path.getsize(os.path.join(p,n)) for n in os.listdir(p) if n.startswith('part-') and '.tmp' not in n and not n.endswith('.more')) if os.path.isdir(p) else 0)")
  ORCH=$(ps -p $(cat ~/logs/glm-mtp-orch.pid 2>/dev/null) -o etime= 2>/dev/null || echo DEAD)
  LOCK=$(cat ~/.gpu-owner 2>/dev/null || echo NO_LOCK)
  HF=$(curl -sS -o /dev/null -w "%{http_code}" -x http://127.0.0.1:7897 --connect-timeout 5 --max-time 12 -I https://huggingface.co/ 2>/dev/null || echo fail)
  echo "$TS shards=$N s3=$S3 orch=$ORCH lock=[$LOCK] hf=$HF" | tee -a "$LOG"
  if (( N < 4 )); then
    if (( S3 <= prev_s3 )); then stall=$((stall+1)); else stall=0; fi
    prev_s3=$S3
    # resume if dead, or stalled >=2 cycles (~40min) AND hf recovers
    need=0
    if ! ps -p $(cat ~/logs/glm53-udiq2xxs.pid 2>/dev/null) >/dev/null 2>&1; then need=1; fi
    if (( stall >= 2 )) && [[ "$HF" =~ ^[23] ]]; then need=1; fi
    if (( need == 1 )); then
      if ! pgrep -f glm53-udiq2xxs-resume >/dev/null; then
        echo "$TS DL_RESUME (stall=$stall hf=$HF)" | tee -a "$LOG"
        pkill -f "GLM-5.3-Flash-UD-IQ2_XXS" 2>/dev/null || true
        sleep 2
        find $MODELS_DIR/gguf/GLM-5.3-Flash-UD-IQ2_XXS/.parts -name "*.tmp" -size 0 -delete 2>/dev/null
        nohup bash ~/logs/glm53-udiq2xxs-resume-hfmirror.sh >> ~/logs/glm53-udiq2xxs.nohup 2>&1 &
        echo $! > ~/logs/glm53-udiq2xxs.pid
        stall=0
      fi
    fi
  fi
  if (( 10#$NOW < 745 )); then
    if ! ps -p $(cat ~/logs/glm-mtp-orch.pid 2>/dev/null) >/dev/null 2>&1; then
      if ! grep -q 'DONE OUT=' ~/logs/glm-mtp-orch-nohup.log 2>/dev/null; then
        echo "$TS ORCH_RESTART" | tee -a "$LOG"
        nohup ~/bin/evo-run-glm53-mtp-priority.sh > ~/logs/glm-mtp-orch-nohup.log 2>&1 &
        echo $! > ~/logs/glm-mtp-orch.pid
      fi
    fi
  fi
  if (( 10#$NOW >= 800 )); then
    echo "$TS stop monitor" | tee -a "$LOG"; break
  fi
  sleep 1200
done
