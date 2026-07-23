# HPC migration

## 1. Clone and pin the code

```bash
git clone https://github.com/dauvillc/motif
cd motif
git checkout 7b0cc0741b7f15658c8609c9780aaf24dc88b810
git status --short
```

The status should be clean before environment setup.

## 2. Choose shared storage

```bash
cp reproducibility/config.example.env reproducibility/config.local.env
```

Edit the ignored copy:

```ini
MOTIF_REPRO_ROOT=/path/to/project-or-scratch/motif-repro
MOTIF_DEFAULT_PROFILE=full
MOTIF_DOWNLOAD_WORKERS=8
MOTIF_PREPROCESS_WORKERS=4
```

Requirements:

- absolute path;
- visible from login/transfer, preprocessing, and GPU nodes;
- at least the raw profile size plus processed-data and checkpoint headroom;
- sufficient inode quota for tens of thousands of NetCDF files.

The pinned full raw dataset is 1.866 TB. The default preflight additionally requires 1 TB of free
reserve, so provision at least 2.866 TB before starting; more is preferable for checkpoints and
predictions.

Do not place the dataset in the Git checkout or a small home quota.

## 3. Load site modules

Load the site's compiler/CUDA/uv modules as required. Record the commands in the job submission
script or environment module collection. Then run:

```bash
bash reproducibility/scripts/01_setup_environment.sh
bash reproducibility/scripts/00_preflight.sh
```

If compute nodes cannot access the internet, build `.venv` on an internet-enabled login/build node
using the same shared filesystem, or use the site's approved wheel cache.

## 4. Download on an approved data-transfer node

Preview first:

```bash
bash reproducibility/scripts/03_download_tc_primed_subset.sh
```

Then launch interactively or through the scheduler:

```bash
bash reproducibility/scripts/03_download_tc_primed_subset.sh --execute
```

The command can be rerun after interruption. Do not launch simultaneous download jobs targeting
the same year.

## 5. Preprocess

Start conservatively:

```bash
bash reproducibility/scripts/05_preprocess_tc_primed.sh --execute
```

Measure peak resident memory and I/O load before increasing workers. The processing is generally
I/O-heavy and can stress a shared metadata server.

## 6. Training setup

For exact repository-scale recipes, create a site-specific Hydra setup in `configs/setup/` based on
`configs/setup/example.yaml`. Record:

- partition/QoS/account;
- node count and GPUs per node;
- GPU model;
- CPUs and memory per task;
- time limit;
- module/activation commands;
- NCCL and network configuration;
- effective global batch size.

The checked-in canonical recipes target eight H100 GPUs. Changing GPU count, precision, per-device
batch size, or accumulation changes the training configuration and must be documented.

## 7. Transfer verification

If raw or processed data is copied from the local machine rather than redownloaded:

- transfer the saved object manifest;
- compare file counts and byte totals at the destination;
- rerun `04_verify_raw_tc_primed.py`;
- rerun `06_verify_preprocessed.py`;
- hash every transferred checkpoint.
