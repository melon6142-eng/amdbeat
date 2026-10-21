"""Unit tests for partial KL (top-k + tail bucket) math."""
from __future__ import annotations

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from kl_compare import (  # noqa: E402
    partial_kl_topk_tail,
    raw_probs_from_logprobs,
)


def test_identical_distributions_kl_zero():
    # Two identical raw top-k maps with the same leftover tail.
    p = {"a": 0.5, "b": 0.3}  # tail 0.2
    q = {"a": 0.5, "b": 0.3}
    out = partial_kl_topk_tail(p, q)
    assert out["kl"] is not None
    assert abs(out["kl"]) < 1e-12
    assert abs(out["p_tail"] - 0.2) < 1e-12
    assert abs(out["q_tail"] - 0.2) < 1e-12


def test_known_small_example():
    # P puts more mass on "a" than Q; shared support {a,b}, tails equal 0.
    p = {"a": 0.8, "b": 0.2}
    q = {"a": 0.5, "b": 0.5}
    out = partial_kl_topk_tail(p, q)
    expected = 0.8 * math.log(0.8 / 0.5) + 0.2 * math.log(0.2 / 0.5)
    assert abs(out["kl"] - expected) < 1e-12
    assert out["p_tail"] == 0.0
    assert out["q_tail"] == 0.0


def test_tail_bucket_behavior():
    # Disjoint top-k -> intersection empty; all mass in tails.
    p = {"x": 0.7}  # p_tail = 0.3 over empty intersection... wait:
    # shared sum is 0, so p_tail = 1.0, q_tail = 1.0, KL = 1*log(1/1) = 0
    # That is the coarsening lower bound (everything merged into one bucket).
    q = {"y": 0.4}
    out = partial_kl_topk_tail(p, q)
    assert out["intersection_size"] == 0
    assert abs(out["p_tail"] - 1.0) < 1e-12
    assert abs(out["q_tail"] - 1.0) < 1e-12
    assert abs(out["kl"]) < 1e-12

    # Partial overlap: token only on P folds into P's tail.
    p = {"a": 0.4, "only_p": 0.3}  # shared {a} sum 0.4 -> p_tail 0.6
    q = {"a": 0.5, "only_q": 0.2}  # shared {a} sum 0.5 -> q_tail 0.5
    out = partial_kl_topk_tail(p, q)
    assert out["intersection_size"] == 1
    assert abs(out["p_tail"] - 0.6) < 1e-12
    assert abs(out["q_tail"] - 0.5) < 1e-12
    expected = 0.4 * math.log(0.4 / 0.5) + 0.6 * math.log(0.6 / 0.5)
    assert abs(out["kl"] - expected) < 1e-12


def test_raw_probs_not_renormalized():
    items = [
        {"token": "a", "logprob": math.log(0.4)},
        {"token": "b", "logprob": math.log(0.3)},
    ]
    probs = raw_probs_from_logprobs(items)
    assert abs(probs["a"] - 0.4) < 1e-12
    assert abs(probs["b"] - 0.3) < 1e-12
    assert abs(sum(probs.values()) - 0.7) < 1e-12  # leftover 0.3 is the tail
