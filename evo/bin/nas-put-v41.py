#!/usr/bin/env python3
import os, sys, time
from pathlib import Path

cred_path = Path.home() / ".smbpass_ugreen"
user = passwd = None
for line in cred_path.read_text().splitlines():
    if line.startswith("username="):
        user = line.split("=", 1)[1]
    elif line.startswith("password="):
        passwd = line.split("=", 1)[1]

import smbclient

server = "<host>"
share = "personal_folder"
remote_root = f"\\\\{server}\\{share}\\models-archive\\evo-deepseek\\DeepSeek-V4.1-Flash"
src = Path.home() / "models/gguf/DeepSeek-V4.1-Flash"
log = Path.home() / "logs/nas-put-v41.log"

def logw(msg):
    line = f"{time.strftime('%F %T')} {msg}"
    print(line, flush=True)
    with log.open("a") as f:
        f.write(line + "\n")

smbclient.register_session(server, username=user, password=passwd)
for d in [remote_root, remote_root + "\\.parts"]:
    try:
        smbclient.mkdir(d)
    except Exception:
        pass

files = []
for p in src.rglob("*"):
    if not p.is_file():
        continue
    rel = p.relative_to(src).as_posix()
    if rel.startswith(".cache/") or rel.endswith(".tmp") or rel.endswith(".incomplete"):
        continue
    files.append((p, rel))
files.sort(key=lambda x: x[1])
logw(f"files={len(files)} total_bytes={sum(p.stat().st_size for p,_ in files)}")

bytes_done = 0
t0 = time.time()
for i, (p, rel) in enumerate(files, 1):
    rpath = remote_root + "\\" + rel.replace("/", "\\")
    try:
        st = smbclient.stat(rpath)
        if st.st_size == p.stat().st_size:
            bytes_done += p.stat().st_size
            if i % 100 == 0:
                logw(f"skip-ok {i}/{len(files)} {rel}")
            continue
    except Exception:
        pass
    parent = rpath.rsplit("\\", 1)[0]
    try:
        smbclient.mkdir(parent)
    except Exception:
        pass
    with p.open("rb") as rf, smbclient.open_file(rpath, mode="wb") as wf:
        while True:
            chunk = rf.read(8 * 1024 * 1024)
            if not chunk:
                break
            wf.write(chunk)
    bytes_done += p.stat().st_size
    if i % 20 == 0 or i == len(files):
        elapsed = max(time.time() - t0, 1e-6)
        mbps = (bytes_done / 1e6) / elapsed
        logw(f"put {i}/{len(files)} bytes={bytes_done} ~{mbps:.1f}MB/s last={rel}")

logw("UPLOAD_COMPLETE")
src_bytes = sum(p.stat().st_size for p, _ in files)

def walk(path):
    for e in smbclient.scandir(path):
        full = path + "\\" + e.name
        if e.is_dir():
            if e.name == ".cache":
                continue
            yield from walk(full)
        else:
            if e.name.endswith(".tmp") or e.name.endswith(".incomplete"):
                continue
            yield full, e.stat().st_size

all_r = list(walk(remote_root))
rb = sum(s for _, s in all_r)
logw(f"VERIFY src_files={len(files)} src_bytes={src_bytes} remote_files={len(all_r)} remote_bytes={rb}")
if len(all_r) == len(files) and rb == src_bytes:
    logw("VERIFY_OK")
    sys.exit(0)
logw("VERIFY_FAIL")
sys.exit(2)
