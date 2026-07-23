# Environment provenance — 2026-07-23

## Repository

- Origin: `https://github.com/dauvillc/motif`
- Commit: `7b0cc0741b7f15658c8609c9780aaf24dc88b810`
- Commit date: `2026-07-11T20:22:54+02:00`
- Commit subject: `Add motif-jz Jean-Zay cluster skill`
- Working tree before reproduction setup: clean

Dependency input hashes:

```text
6820d4a7f02e260d4c76e7492128bb1bbf42e6505339feb565649405ece6113a  uv.lock
e9c83864b9b0333ec38ee67b665871379a814420fe5da4696e96e4958a93ec99  pyproject.toml
43fd694bd564dd2215f51a6b23f6a3712834850225e629d7781c81c71076092d  .python-version
```

## Environment construction

```bash
uv sync --frozen
uv lock --check
```

- uv: `0.11.24`
- Requested and installed Python: `3.12.11`
- Lock check: passed (`214` packages resolved)
- Installed project: editable local `motif==0.1.0`

Selected locked runtime versions:

| Package | Version |
|---|---:|
| PyTorch | `2.8.0+cu128` |
| torchvision | `0.23.0+cu128` |
| Lightning | `2.6.0` |
| Hydra | `1.3.2` |
| NumPy | `2.3.5` |
| xarray | `2025.12.0` |
| netCDF4 | `1.7.3` |
| boto3 | `1.42.10` |
| W&B | `0.23.1` |

All imports above passed.

## Host

- OS: Ubuntu 24.04.4 LTS
- Kernel: Linux 6.8.0-136-generic x86_64
- CPU: AMD Ryzen 5 7600X, 6 cores / 12 threads
- RAM: 30 GiB
- Swap: 39 GiB
- NVIDIA driver: `580.159.03`
- GPUs: 2 × NVIDIA GeForce RTX 3090, 24,576 MiB each
- CUDA visible to PyTorch: yes
- PyTorch CUDA runtime: `12.8`
- cuDNN version reported by PyTorch: `91002`

Free space at setup time:

| Mount | Available |
|---|---:|
| `/work` | 123 GiB |
| `/data1` | 948 GiB |
| `/data2` | 1.6 TiB |

## Verification result

The lockfile, Python runtime, package imports, CUDA runtime, cuDNN, and both GPUs are
operational. No research data or checkpoints were downloaded during this step.

