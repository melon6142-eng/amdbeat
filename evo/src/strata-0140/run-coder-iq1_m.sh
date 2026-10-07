#!/bin/sh
cd "$HOME/src/strata-0140"
exec "$HOME/src/strata-0140/.venv/bin/python" "$HOME/src/strata-0140/serve/server.py" "--engine" "strata" "--config" "$HOME/src/strata-0140/strata-coder-iq1_m.json" "--port" "8080" "--open"
