#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/reproducibility/lib/common.sh"
cd "$repo_root"

echo "# Repository"
git rev-parse HEAD
git remote get-url origin
git status --porcelain
git log -1 --format="%H%n%aI%n%s"

echo
echo "# Dependency inputs"
sha256sum uv.lock pyproject.toml .python-version
uv --version
uv lock --check

echo
echo "# Operating system and compute"
uname -srmo
sed -n "1,12p" /etc/os-release
command -v lscpu >/dev/null && lscpu || true
command -v free >/dev/null && free -h || true

df_targets=("$repo_root")
if [[ -n "${MOTIF_REPRO_ROOT:-}" ]]; then
    storage_probe="$MOTIF_REPRO_ROOT"
    while [[ ! -e "$storage_probe" && "$storage_probe" != "/" ]]; do
        storage_probe="$(dirname "$storage_probe")"
    done
    df_targets+=("$storage_probe")
fi
df -h "${df_targets[@]}"

if command -v nvidia-smi >/dev/null; then
    nvidia-smi \
        --query-gpu=index,name,uuid,memory.total,driver_version \
        --format=csv,noheader
else
    echo "nvidia-smi not found"
fi

echo
echo "# Python runtime"
.venv/bin/python -c '
import platform

import boto3
import hydra
import lightning
import netCDF4
import numpy
import torch
import torchvision
import wandb
import xarray

import motif

print("python", platform.python_version())
print("motif", motif.__file__)
print("torch", torch.__version__)
print("torchvision", torchvision.__version__)
print("lightning", lightning.__version__)
print("hydra", hydra.__version__)
print("numpy", numpy.__version__)
print("xarray", xarray.__version__)
print("netCDF4", netCDF4.__version__)
print("boto3", boto3.__version__)
print("wandb", wandb.__version__)
print("cuda_available", torch.cuda.is_available())
print("cuda_runtime", torch.version.cuda)
print("cudnn", torch.backends.cudnn.version())
print("cuda_devices", torch.cuda.device_count())
for index in range(torch.cuda.device_count()):
    properties = torch.cuda.get_device_properties(index)
    print("gpu", index, torch.cuda.get_device_name(index), properties.total_memory)
'
