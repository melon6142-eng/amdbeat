"""Dry-run smoke: mock OpenAI server + bench_client + kl_compare."""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]


def test_dry_run_against_mock_server(tmp_path: Path):
    port = 18766
    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "scripts" / "mock_openai_server.py"), "--port", str(port)],
        cwd=str(ROOT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        base = f"http://127.0.0.1:{port}/v1"
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                r = httpx.get(f"http://127.0.0.1:{port}/health", timeout=0.5)
                if r.status_code == 200:
                    break
            except Exception:
                time.sleep(0.1)
        else:
            raise AssertionError("mock server did not become healthy")

        endpoints = tmp_path / "endpoints.yaml"
        endpoints.write_text(
            "\n".join(
                [
                    "endpoints:",
                    "  mock:",
                    f'    base_url: "{base}"',
                    '    model: "mock-bf16"',
                    "    api_key: null",
                    "",
                ]
            )
        )
        out_name = "pytest_dryrun"
        bench = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "bench_client.py"),
                "--endpoints",
                str(endpoints),
                "--endpoint",
                "mock",
                "--dry-run",
                "--out-name",
                out_name,
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert bench.returncode == 0, bench.stderr + bench.stdout
        result_json = ROOT / "results" / f"{out_name}.json"
        assert result_json.exists()
        payload = json.loads(result_json.read_text())
        assert "speed" in payload and "eval" in payload

        kl_out = tmp_path / "kl.json"
        kl = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "kl_compare.py"),
                "--endpoints",
                str(endpoints),
                "--ref",
                "mock",
                "--cand",
                "mock",
                "--cand-model",
                "mock-quant",
                "--out",
                str(kl_out),
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert kl.returncode == 0, kl.stderr + kl.stdout
        report = json.loads(kl_out.read_text())
        assert "top1_agreement" in report
        assert "mean_partial_kl" in report
        assert "partial_kl_note" in report
        note = report["partial_kl_note"].lower()
        assert "lower-bound" in note or "lower bound" in note
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
