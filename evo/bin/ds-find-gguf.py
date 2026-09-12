from pathlib import Path
import os
import subprocess

roots = [
    Path.home() / "models",
    Path.home() / "mnt",
    Path("/mnt"),
]
seen = set()
print("===ggufs===")
for root in roots:
    if not root.exists():
        continue
    for p in root.rglob("*.gguf"):
        try:
            st = p.stat()
        except OSError:
            continue
        key = str(p.resolve()) if p.exists() else str(p)
        if key in seen:
            continue
        seen.add(key)
        print(f"{st.st_size}\t{st.st_size/1024**3:.2f}GiB\t{p}")

print("===mix_devices===")
mix = Path.home() / "opt/unsloth-llama-b10698-mix-vulkan/llama-server"
if mix.exists():
    env = os.environ.copy()
    env.pop("VK_ICD_FILENAMES", None)
    env["LD_LIBRARY_PATH"] = str(mix.parent) + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    print(subprocess.check_output([str(mix), "--list-devices"], env=env, text=True, stderr=subprocess.STDOUT)[:2000])
