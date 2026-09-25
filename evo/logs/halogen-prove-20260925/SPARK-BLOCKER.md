# Spark Flash-Next blocker — 2026-09-25 CST

- Live `:8888` on `<host>` / `.81` = **`deepseek-v4-flash-0731`** (vLLM), NOT Qwen3.8-Flash-Next.
- `:8001` (lab Flash-Next port) unreachable.
- Did **not** stop DeepSeek / restart Flash-Next (would disrupt current Spark tenant).
- Prior rocket HTML reused: `index-spark-prior.html` (51955 B).
- Checks: {"has_doctype": true, "has_close_html": true, "has_three": true, "has_raf": true, "has_launch": true, "has_scene": true, "bytes": 51955}

## Bring up Flash-Next (manual)

```bash
ssh <spark>
cd ~/src/Qwen3.8-Flash-Next-Single-DGX-Spark
# WARNING: stops DeepSeek on this box
docker stop vllm-fn-tp1 flashnext qwen38-dflash2-production deepseek-v4-flash-spark-deepseek-v4-flash-1 2>/dev/null || true
./stop.sh --force 2>/dev/null || true
cp -n .env.sample .env
# ./download.sh   # if checkpoint missing (~99GiB)
nohup env PORT=8001 REQUIRE_IDLE_GPU=false ./start.sh > ~/logs/lab-load-flash.log 2>&1 &
# wait ~10-12 min then:
curl -sS http://127.0.0.1:8001/v1/models
```

Repo: https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark
Claimed decode (prose, 1-stream): ~48.7 tok/s.
