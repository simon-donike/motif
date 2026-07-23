# Reproduction plan and acceptance gates

## Scope

The first target is the active PMW/infrared workflow:

- `det_PI`
- `fm_PI_gpm`
- `fm_pmw`
- `fm_PI`

SAR, radar, standalone WeatherBench ERA5, and embedded TC-PRIMED environmental products are a
separate expansion phase. They are not inputs to these four active experiment configurations.

The `local100` basin/year subset validates the complete software workflow and supports custom
training. It does not reproduce metrics from a model trained on the authors' full dataset. The
`full` profile is reserved for the HPC reproduction.

## Step 1 — Freeze code and environment

Actions:

- check out the pinned Git commit;
- run `uv sync --frozen`;
- verify `uv lock --check`;
- import core libraries;
- record repository, lockfile, OS, CPU, RAM, GPUs, CUDA, cuDNN, and storage.

Acceptance gate:

- lock check passes;
- Python is 3.12.11;
- PyTorch is 2.8.0;
- the intended GPUs are visible;
- dependency input hashes match the recorded provenance.

Status: complete on the initial local machine.

## Step 2 — Inventory and bound raw data

Actions:

- anonymously list the NOAA TC-PRIMED S3 objects for the selected years;
- save aggregate and object-level manifests;
- compare totals with the pinned profile;
- refuse profiles over the configured raw-byte ceiling.

Acceptance gate:

- `local100` remains exactly 14,972 objects and 100,461,087,970 bytes;
- `full` remains exactly 256,860 objects and 1,865,733,153,682 bytes;
- any upstream difference is investigated and explicitly accepted before download.

## Step 3 — Download the selected raw data

Actions:

- run the repository's `preproc/tc_primed/download_tc_primed.py` once per selected year;
- use anonymous S3 access;
- preserve the repository's destination hierarchy;
- retain logs and the remote object manifest.

Acceptance gate:

- the downloader exits successfully for every year;
- disk usage remains below the agreed ceiling;
- no `.tmp` or partial objects remain.

## Step 4 — Verify raw data

Actions:

- compare every manifest key with its expected local path;
- compare exact byte sizes;
- detect unexpected local files;
- open a deterministic sample of NetCDF files.

Acceptance gate:

- zero missing files;
- zero size mismatches;
- zero unexpected files, except explicitly documented non-data files;
- all sampled NetCDF files open successfully.

S3 does not publish a simple cryptographic checksum for every object. Multipart ETags are not
treated as MD5 hashes, so path, byte size, and NetCDF readability are the available repository-
compatible integrity checks.

## Step 5 — Preprocess PMW and infrared

Operational instructions: [PREPROCESSING.md](PREPROCESSING.md).

Run in this order:

1. `prepare_pmw_concat.py`
2. `prepare_infrared.py`
3. `train_val_test_split.py`
4. `compute_normalization_constants.py`

The initial local worker count is four because the machine has 12 CPU threads and 30 GiB RAM.
Reassess worker memory before raising it on HPC.

Acceptance gate:

- every configured active PMW and infrared source has metadata and data;
- no worker exits unsuccessfully;
- preprocessing logs record all discarded samples;
- all split and constant files are created.

## Step 6 — Verify processed data

Actions:

- verify required source directories;
- validate `source_metadata.json` and `samples_metadata.csv`;
- check split seasons against the repository configuration;
- ensure metadata paths exist;
- ensure normalization means/stds are finite and standard deviations are positive;
- open sample processed NetCDF files.

Acceptance gate:

- all required sources pass;
- no row is assigned to the wrong split;
- no referenced file is missing;
- constants are usable by the dataset.

## Step 7 — Audit authors' checkpoints

Actions:

- obtain checkpoint files and checksums from a confirmed source;
- store each checkpoint under `<root>/checkpoints/<run_id>/`;
- inspect embedded experiment configuration;
- verify state-dict structure and checkpoint selection.

Acceptance gate:

- the checkpoint file source and checksum are documented;
- the embedded configuration loads;
- the run ID maps unambiguously to one checkpoint used for inference.

This gate is currently blocked because the repository provides run IDs but no checkpoint
download URL or release.

## Step 8 — Smoke training

Operational instructions: [TRAINING.md](TRAINING.md).

Actions:

- retain the documented compatibility reconstruction for the unrecoverable W&B config;
- select disabled, offline, or authenticated online W&B mode;
- instantiate all four active experiments;
- run one train and validation batch;
- save and reload a checkpoint;
- test deterministic seeds and resume behavior;
- overfit a tiny fixed subset.

Acceptance gate:

- finite loss and gradients;
- no NaNs;
- checkpoint reload reproduces the saved state;
- prediction works from the smoke checkpoint.

## Step 9 — Authors' checkpoint inference and evaluation

Actions:

- generate validation/test predictions with the matching inference preset;
- repeat with fixed seeds;
- run quantitative, visual, spectrum, availability, source, and footprint evaluations as
  applicable;
- compare with author-provided predictions or metrics.

Acceptance gate:

- repeated runs agree within the documented numerical tolerance;
- saved prediction metadata describes the exact same selected samples;
- metrics match a trusted reference where one is available.

## Step 10 — Custom/full training

Operational instructions: [TRAINING.md](TRAINING.md).

Actions:

- choose a documented hardware/global-batch configuration;
- train `det_PI`, `fm_PI_gpm`, `fm_pmw`, and `fm_PI`;
- record W&B mode, run IDs, seeds, checkpoints, loss curves, and wall time;
- run the same inference/evaluation suite.

The repository recipes use eight H100 GPUs. Two RTX 3090 GPUs can validate code and train custom
models, but cannot reproduce the original hardware-dependent training trajectory bit-for-bit.

## Step 11 — Optional data-source expansion

Only after the active workflow passes:

- CyclObs SAR download and preprocessing;
- TC-PRIMED radar preprocessing;
- TC-PRIMED embedded ERA5 preprocessing;
- storm-metadata preprocessing;
- standalone WeatherBench ERA5 download.

After adding any source, rerun split generation and normalization.
