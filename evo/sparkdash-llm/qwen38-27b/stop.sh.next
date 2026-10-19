#!/usr/bin/env bash
# stops only the 8216 Strata server and its engine child (by PID, not by pattern). Does not touch 8217.
PAT="serve.server --engine strata --config strata-.*-r9700-8216.*[.]json"
srv=$(pgrep -f "$PAT"); [ -z "$srv" ] && { echo "not running"; exit 0; }
kids=$(for s in $srv; do pgrep -P $s; done)
kill -TERM $srv
for i in $(seq 1 40); do alive=0; for p in $srv $kids; do kill -0 $p 2>/dev/null && alive=1; done; [ $alive = 0 ] && { echo "strata 8216 stopped"; exit 0; }; sleep 1; done
kill -KILL $srv $kids 2>/dev/null; echo "strata 8216 killed"
