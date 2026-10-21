#!/usr/bin/env python3
"""Minimal OpenAI-compatible mock server for dry-run benches (stdlib only)."""
from __future__ import annotations

import argparse
import json
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


def _approx_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def _fake_logprobs(token: str, k: int = 5) -> dict:
    # Deterministic pseudo-distribution for KL dry-run.
    alts = [token, token + "a", token + "b", "the", "and"][:k]
    base = -0.4
    content = []
    for i, t in enumerate(alts):
        content.append({"token": t, "logprob": base - 0.35 * i, "top_logprobs": None})
    # nest top_logprobs on first entry style similar to OpenAI chat
    top = [{"token": t, "logprob": base - 0.35 * i} for i, t in enumerate(alts)]
    return {"content": [{"token": token, "logprob": base, "top_logprobs": top}]}


class Handler(BaseHTTPRequestHandler):
    server_version = "quant-lab-mock/0.1"

    def log_message(self, fmt: str, *args) -> None:  # quieter
        pass

    def _json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in ("/v1/models", "/models"):
            self._json(
                200,
                {
                    "object": "list",
                    "data": [
                        {"id": "mock-bf16", "object": "model"},
                        {"id": "mock-quant", "object": "model"},
                    ],
                },
            )
            return
        if path in ("/health", "/v1/health"):
            self._json(200, {"status": "ok"})
            return
        self._json(404, {"error": {"message": f"not found: {path}"}})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            req = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            self._json(400, {"error": {"message": "invalid json"}})
            return

        if path not in ("/v1/chat/completions", "/chat/completions"):
            self._json(404, {"error": {"message": f"not found: {path}"}})
            return

        model = req.get("model", "mock-bf16")
        messages = req.get("messages") or []
        prompt = ""
        for m in messages:
            prompt += str(m.get("content", "")) + "\n"
        max_tokens = int(req.get("max_tokens") or 16)
        stream = bool(req.get("stream"))
        want_logprobs = bool(req.get("logprobs"))
        top_logprobs = int(req.get("top_logprobs") or 0)

        # Tiny latency proportional to prompt size to exercise TTFT/prefill math.
        prompt_toks = _approx_tokens(prompt)
        time.sleep(min(0.05, 0.000002 * prompt_toks + 0.002))

        # Deterministic "answer" body.
        if re.search(r"apples", prompt, re.I):
            text = "She has 3 + 2*4 = 11 apples.\n11"
        elif re.search(r"average speed", prompt, re.I):
            text = "60 / 1.5 = 40\n40"
        elif re.search(r"is_palindrome", prompt, re.I):
            text = (
                "```python\n"
                "import re\n"
                "def is_palindrome(s: str) -> bool:\n"
                "    t = re.sub(r'[^a-z0-9]', '', s.lower())\n"
                "    return t == t[::-1]\n"
                "```"
            )
        elif re.search(r"primary colors", prompt, re.I):
            text = "- red\n- blue\n- yellow"
        else:
            words = ["ok", "quant", "lab", "bench", "mock"]
            # slight distribution shift for mock-quant vs mock-bf16
            if model.endswith("quant"):
                words = ["ok", "lab", "quant", "bench", "mock"]
            text = " ".join(words[(prompt_toks + i) % len(words)] for i in range(max_tokens))
            text = " ".join(text.split()[:max_tokens])

        completion_toks = _approx_tokens(text)
        created = int(time.time())
        usage = {
            "prompt_tokens": prompt_toks,
            "completion_tokens": completion_toks,
            "total_tokens": prompt_toks + completion_toks,
        }

        if stream:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            # first chunk = TTFT mark
            first = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": None}],
            }
            self.wfile.write(f"data: {json.dumps(first)}\n\n".encode())
            self.wfile.flush()
            # emit content in small pieces
            pieces = text.split(" ") if text else [""]
            for i, piece in enumerate(pieces):
                chunk_text = piece if i == 0 else " " + piece
                time.sleep(0.003)
                delta = {"content": chunk_text}
                if want_logprobs and top_logprobs:
                    # attach a token logprob for the piece
                    lp = _fake_logprobs(piece or " ", k=top_logprobs)
                    choice = {
                        "index": 0,
                        "delta": delta,
                        "finish_reason": None,
                        "logprobs": lp,
                    }
                else:
                    choice = {"index": 0, "delta": delta, "finish_reason": None}
                obj = {
                    "id": "chatcmpl-mock",
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [choice],
                }
                self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode())
                self.wfile.flush()
            final = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                "usage": usage,
            }
            self.wfile.write(f"data: {json.dumps(final)}\n\n".encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return

        # non-stream
        message = {"role": "assistant", "content": text}
        choice: dict = {"index": 0, "message": message, "finish_reason": "stop"}
        if want_logprobs and top_logprobs:
            # one synthetic logprob entry per whitespace token
            toks = text.split() or ["ok"]
            content = []
            for t in toks[: min(len(toks), max_tokens)]:
                alts = [t, t + "x", "the", "and", "of"][:top_logprobs]
                content.append(
                    {
                        "token": t,
                        "logprob": -0.4,
                        "top_logprobs": [
                            {"token": a, "logprob": -0.4 - 0.3 * j} for j, a in enumerate(alts)
                        ],
                    }
                )
            # slight shift for quant model
            if model.endswith("quant") and content:
                content[0]["logprob"] = -0.55
                content[0]["top_logprobs"][0]["logprob"] = -0.55
            choice["logprobs"] = {"content": content}

        self._json(
            200,
            {
                "id": "chatcmpl-mock",
                "object": "chat.completion",
                "created": created,
                "model": model,
                "choices": [choice],
                "usage": usage,
            },
        )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=18765)
    args = ap.parse_args()
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"mock listening on http://{args.host}:{args.port}/v1", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
