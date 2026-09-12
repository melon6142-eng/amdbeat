#!/usr/bin/env python3
"""After AMD-only 16k JSON exists, run 32k on the same :8080. Idempotent."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

JSON16 = Path.home() / "hybrid-results/ds-q3-amd-realctx-16k.json"
JSON32 = Path.home() / "hybrid-results/ds-q3-amd-realctx-32k.json"
SKIP32 = Path.home() / "hybrid-results/ds-q3-amd-realctx-32k.skip"
STATUS = Path.home() / "hybrid-results/ds-amd-continue.status"
BENCH = Path.home() / "bin/evo-bench-ds-realctx.py"
WAIT_S = 5 * 3600


def write_status(text: str) -> None:
    STATUS.parent.mkdir(parents=True, exist_ok=True)
    STATUS.write_text(text + "\n", encoding="utf-8")
    print(text, flush=True)


def json_ok(path: Path) -> bool:
    if not path.is_file() or path.stat().st_size < 40:
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False
    rows = data.get("rows") or []
    return bool(rows) and bool(rows[-1].get("predicted_n"))


def sixteen_running() -> bool:
    out = subprocess.check_output(["ps", "-eo", "args"], text=True)
    return any(
        "/bin/evo-bench-ds-realctx.py" in line and "16k.json" in line and "import json" not in line
        for line in out.splitlines()
    )


def main() -> int:
    if JSON32.is_file() and json_ok(JSON32):
        write_status("DONE 32k already present")
        return 0
    if SKIP32.is_file():
        write_status("SKIP 32k already skipped: " + SKIP32.read_text(encoding="utf-8").strip())
        return 0

    write_status("WAIT 16k json")
    t0 = time.time()
    missing_since = None
    while not json_ok(JSON16):
        if time.time() - t0 > WAIT_S:
            write_status("FAIL timeout waiting 16k")
            SKIP32.write_text("timeout waiting 16k\n", encoding="utf-8")
            return 1
        if sixteen_running():
            missing_since = None
        else:
            missing_since = missing_since or time.time()
            if time.time() - missing_since > 180:
                write_status("FAIL 16k process gone without json")
                SKIP32.write_text("16k process gone without json\n", encoding="utf-8")
                return 1
        time.sleep(20)

    data = json.loads(JSON16.read_text(encoding="utf-8"))
    row = (data.get("rows") or [None])[-1]
    if not row or not row.get("predicted_n"):
        write_status("SKIP 16k has no generation")
        SKIP32.write_text("16k has no generation\n", encoding="utf-8")
        return 0

    write_status(
        "START 32k after 16k prompt_n=%s prefill=%s gen=%s"
        % (row.get("prompt_n"), row.get("prompt_per_second"), row.get("predicted_per_second"))
    )
    env = os.environ.copy()
    rc = subprocess.call(
        [
            sys.executable,
            str(BENCH),
            "http://127.0.0.1:8080",
            str(JSON32),
            "32000",
            "64",
        ],
        env=env,
    )
    if rc == 0 and json_ok(JSON32):
        write_status("DONE 32k")
        return 0
    write_status("FAIL 32k rc=%s" % rc)
    if not SKIP32.is_file():
        SKIP32.write_text("32k bench rc=%s\n" % rc, encoding="utf-8")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
