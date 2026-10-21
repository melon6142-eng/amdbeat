"""Tests for HumanEval subprocess executor."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from bench_client import extract_python_code, run_humaneval_test, score_humaneval  # noqa: E402

PASSING = """
def is_palindrome(s: str) -> bool:
    t = "".join(ch.lower() for ch in s if ch.isalnum())
    return t == t[::-1]
"""

FAILING = """
def is_palindrome(s: str) -> bool:
    return False
"""

TEST = """
def check(candidate):
    assert candidate("A man, a plan, a canal: Panama") is True
    assert candidate("race a car") is False
    assert candidate("") is True
"""


def test_passing_solution():
    result = run_humaneval_test(PASSING, TEST, "is_palindrome", timeout_s=5.0)
    assert result["passed"] is True
    assert result["error"] is None


def test_failing_solution():
    result = run_humaneval_test(FAILING, TEST, "is_palindrome", timeout_s=5.0)
    assert result["passed"] is False
    assert result["error"]


def test_timeout():
    slow = """
def is_palindrome(s: str) -> bool:
    import time
    time.sleep(30)
    return True
"""
    result = run_humaneval_test(slow, TEST, "is_palindrome", timeout_s=1.0)
    assert result["passed"] is False
    assert "timeout" in (result["error"] or "")


def test_missing_test_marked_not_available():
    ok, detail = score_humaneval({"id": "x"}, "def is_palindrome(s): return True")
    assert ok is None
    assert detail == "not_available_missing_test"


def test_extract_fenced_code():
    text = "Sure!\n```python\ndef foo():\n    return 1\n```\n"
    code = extract_python_code(text)
    assert "def foo" in code
