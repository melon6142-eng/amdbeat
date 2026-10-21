#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/scripts/env.local" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/env.local"
elif [[ -f "$ROOT/scripts/env.example" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/env.example"
fi
require_confirm() {
  if [[ "${EVO_CONFIRM:-}" != "1" ]]; then
    echo "Refusing: set EVO_CONFIRM=1 after lab-ops clears 8216 / agrees paths." >&2
    echo "This is a template run-guard; no EVO action taken." >&2
    exit 2
  fi
}
