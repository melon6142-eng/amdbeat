# Findings

Failed and blocked attempts stay here so the next agent does not repeat them.

## 001 HIP visible memory is ~29 GiB

- When: 2026-09-14 (GLM) and 2026-09-15 (idle recheck)
- Box: EVO-X3, kernel 7.0.0-31-generic, `amdgpu.gttsize=122880`, VRAM carve-out 96 GiB
- Sysfs idle: VRAM used 0.35 GiB, GTT used 0.05 GiB
- `llama-server --list-devices` on Unsloth MIX HIP: `ROCm0 ... (122880 MiB, 29679 MiB free)`
- 82 GiB GLM `cudaMalloc` OOM. 88 GiB Flash-Next will fail the same way.
- Vulkan sees VRAM+GTT together and loads the same files.
- Implication: Flash-Next HIP baseline is blocked until HIP can allocate the GTT pool.
  `HIP_LAUNCH_BLOCKING=1` is not the first HIP problem on this box.

## 002 USB4 peer still absent

- 2026-09-15 morning. EVO has NHI host only. Spark has no thunderbolt bus (USB 3.2).
- Out of scope for this arena until single-node baselines exist.
