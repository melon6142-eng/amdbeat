#!/bin/bash
# usage: mtp.sh TAG BINDIR DEV EXTRA...   (assumes 8216 down; uses port 8299)
TAG=$1; B=$2; DEV=$3; shift 3
M=~/models/gguf/Qwen3.8-27B/Qwen3.8-27B-UD-Q4_K_XL.gguf; D=~/models/gguf/Qwen3.8-27B/mtp-Qwen3.8-27B-Q4_0.gguf
O=~/r9700-push/mtp.txt; L=~/r9700-push/srv-$TAG.log
cd $B; LD_LIBRARY_PATH=$B ./llama-server -m $M --host 127.0.0.1 --port 8299 -a q -ngl 99 -fa on -c 65536 -b 4096 -ub 1024 -ctk f16 -ctv f16 --jinja --device $DEV --spec-type draft-mtp -md $D -devd $DEV -ngld all "$@" > $L 2>&1 &
P=$!; for i in $(seq 1 240); do curl -s --max-time 1 localhost:8299/v1/models | grep -q '"q"' && break; sleep 1; done
q(){ curl -s --max-time 300 localhost:8299/v1/chat/completions -H 'Content-Type: application/json' -d "{\"model\":\"q\",\"temperature\":0,\"max_tokens\":256,\"chat_template_kwargs\":{\"enable_thinking\":false},\"messages\":[{\"role\":\"user\",\"content\":\"$1\"}]}" | python3 -c 'import sys,json;t=json.load(sys.stdin)["timings"];print("%.1f %s"%(t["predicted_per_second"],t.get("draft_n_accepted","?")))'; }
CP="Write a Python function that parses a CSV file and returns a list of dicts, with type hints, docstring and error handling."
PP="Write a short essay about the history of the printing press and its effect on European society."
q "Hi" >/dev/null
c=(); p=(); for r in 1 2 3; do c+=("$(q "$CP")"); p+=("$(q "$PP")"); done
echo "$TAG | $* | code: ${c[*]} | prose: ${p[*]}" | tee -a $O
kill $P; wait $P 2>/dev/null; sleep 3
