#!/bin/bash
until grep -qE "QUANT DONE|QUANT FAIL" $HOME/logs/dl-kl-quants.log 2>/dev/null; do sleep 60; done
grep -q "QUANT DONE" $HOME/logs/dl-kl-quants.log || exit 1
grep -q FAIL $HOME/logs/dl-kl-quants.log && exit 1
$HOME/kl-eval/run-kl.sh > $HOME/kl-eval/run-kl.out 2>&1
