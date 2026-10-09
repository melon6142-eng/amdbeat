#!/bin/bash
set -euo pipefail
VENV=~/venvs/smbupload
LOG=~/logs/nas-put-v41.log
: > "$LOG"
"$VENV/bin/python" ~/bin/nas-put-v41.py
grep -q VERIFY_OK "$LOG"

# IQ2XXS already verified on AW — double-check sizes still
OUT=$(smbclient //<host>/personal_folder -A ~/.smbpass_ugreen -c 'cd AI-Workspace/models/evo/gguf/DeepSeek-V4-Flash-IQ2XXS; ls DeepSeek-V4-Flash-DSpark-support-0731.gguf; ls DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf' 2>&1)
echo "$OUT" | tee -a "$LOG"
echo "$OUT" | grep -q 'DeepSeek-V4-Flash-DSpark-support-0731.gguf      A 5989114272'
echo "$OUT" | grep -q 'DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf      A 86720111488'

rm -rf $MODELS_DIR/gguf/DeepSeek-V4.1-Flash $MODELS_DIR/gguf/DeepSeek-V4-Flash-IQ2XXS
echo "DELETED $(date)" | tee -a "$LOG"
df -h / | tee -a "$LOG"
ls $MODELS_DIR/gguf | tee -a "$LOG"
echo ALL_DONE | tee -a "$LOG"
