#!/bin/bash
set -euo pipefail
LOG=$HOME/rsync-evo-nas-finish.log
exec >>"$LOG" 2>&1
echo "wait start $(date)"
while ps -p 1761836 >/dev/null 2>&1; do sleep 30; done
echo "rsync pid gone $(date)"
rsync -a --no-owner --no-group --dry-run --out-format="%n" $MODELS_DIR/ /mnt/ugreen88/AI-Workspace/models/evo/ > /tmp/evo-nas-dry.txt
if [ -s /tmp/evo-nas-dry.txt ]; then
  echo "dry-run still has files, not deleting"
  wc -l /tmp/evo-nas-dry.txt
  head /tmp/evo-nas-dry.txt
  exit 2
fi
echo "dry-run empty, deleting local models $(date)"
rm -rf $MODELS_DIR
mkdir -p $MODELS_DIR
df -h /
echo "done $(date)"
