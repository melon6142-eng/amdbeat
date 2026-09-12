from pathlib import Path
from collections import Counter
import json
import urllib.request

text = Path.home().joinpath("logs/serve-deepseek-q3-amd.log").read_text(errors="replace")
print("log_bytes", len(text), "lines", text.count("\n"))
c = Counter()
for line in text.splitlines():
    parts = line.split()
    if len(parts) >= 3:
        c[parts[2]] += 1
print("tags", c.most_common(40))
for line in text.splitlines():
    if any(x in line for x in ("MiB", "GiB", "buffer", "offload", "mmap", "no-host", "Vulkan", "CPU ")):
        if "resolve_fused" in line:
            continue
        print(line[:400])
print("===props===")
try:
    raw = urllib.request.urlopen("http://127.0.0.1:8080/props", timeout=3).read().decode()
    print(raw[:4000])
except Exception as e:
    print("props", e)
print("===slots===")
try:
    print(urllib.request.urlopen("http://127.0.0.1:8080/slots", timeout=3).read().decode()[:2000])
except Exception as e:
    print("slots", e)
