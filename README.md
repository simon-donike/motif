# MOTIF: reproducible fork

This repository is a fork of the original
[dauvillc/motif](https://github.com/dauvillc/motif) implementation of multi-source generative
modelling for spatiotemporal interpolation of tropical-cyclone observations.

Our goal is to stay as close as possible to the original scientific implementation while making
the complete workflow easier to reproduce on a workstation and on an HPC system. The model,
dataset, preprocessing, training, prediction, and evaluation entry points remain the repository's
original ones. The additions under [`reproducibility/`](reproducibility/) wrap those entry points
with explicit dataset profiles, configuration, dry runs, storage checks, manifests, verification,
logging, and provenance capture. They are operational safeguards, not a second implementation of
the science.

The reproduction runbook is pinned against upstream scientific-code commit
`7b0cc0741b7f15658c8609c9780aaf24dc88b810`. Preflight checks report unexpected scientific-code
changes so deviations from that reference are visible and can be documented.

## What MOTIF contains

MOTIF uses PyTorch, Lightning, Hydra, and Weights & Biases. It provides:

- a multi-source dataset and memory-conscious collator for a variable number of observations;
- a geospatial, DiT-inspired multi-source backbone;
- deterministic reconstruction trained with MSE and generative reconstruction trained with flow matching;
- self-supervised random source masking and supervised fixed-target training;
- preprocessing for TC-PRIMED microwave and infrared observations, plus SAR and ERA5 utilities;
- scripts for training, checkpointing, prediction, quantitative evaluation, spectra, source analysis, and visualization.

The main experiments live in [`configs/experiment/`](configs/experiment/), runtime choices are
composed through Hydra under [`configs/`](configs/), and the implementation is under
[`src/motif/`](src/motif/).

## Reproducible quick start

Python 3.12 and [`uv`](https://docs.astral.sh/uv/) are required. Data and outputs are deliberately
kept outside the Git checkout.

```bash
cp reproducibility/config.example.env reproducibility/config.local.env
```

Edit the ignored `config.local.env` and set an absolute storage path:

```ini
MOTIF_REPRO_ROOT=/path/to/large/storage/motif-repro
MOTIF_DEFAULT_PROFILE=local100
MOTIF_WANDB_MODE=offline
```

Then run the numbered workflow:

```bash
# Check the checkout, tools, selected data budget, and available storage.
bash reproducibility/scripts/00_preflight.sh

# Recreate the locked environment and record machine/software provenance.
bash reproducibility/scripts/01_setup_environment.sh

# Preview the download, then explicitly start it.
bash reproducibility/scripts/03_download_tc_primed_subset.sh
bash reproducibility/scripts/03_download_tc_primed_subset.sh --execute

# Verify every selected raw object against the remote inventory.
.venv/bin/python reproducibility/scripts/04_verify_raw_tc_primed.py

# Preview preprocessing, execute it, and verify its products.
bash reproducibility/scripts/05_preprocess_tc_primed.sh
bash reproducibility/scripts/05_preprocess_tc_primed.sh --execute
.venv/bin/python reproducibility/scripts/06_verify_preprocessed.py
```

Commands that download data, preprocess it, or start proper training are dry runs unless
`--execute` is supplied. Downloads are resumable, constrained by profile-specific byte budgets,
and produce manifests and logs. Preprocessing invokes the original PMW, infrared, split, and
normalization scripts in order; `--stage` selects an individual step and `--resume` enables the
supported existence checks.

## Local subsets and full HPC data

The same workflow accepts `--profile PROFILE`, or uses `MOTIF_DEFAULT_PROFILE`:

| Profile | Intended use | Raw TC-PRIMED selection |
|---|---|---:|
| `local100` | Local development and end-to-end testing | 100.46 GB |
| `core6` | Intermediate six-season run | 362.57 GB |
| `extended8` | Larger eight-season run | 518.65 GB |
| `full` | Full HPC reproduction, all basins in 1987–2024 | 1.866 TB |

`local100` is basin-selective but includes every PMW sensor used by the active experiments and has
separate training, validation, and test seasons. It reproduces the mechanics of the workflow, not
the numerical results of full-data training. Use `full` for that purpose.

For an HPC clone, use storage visible to transfer, preprocessing, and GPU nodes, set
`MOTIF_DEFAULT_PROFILE=full`, run environment setup and preflight on the cluster, and adapt a
Hydra setup from [`configs/setup/example.yaml`](configs/setup/example.yaml). Example PBS download,
preprocessing, and GPU-training jobs are in
[`reproducibility/hpc_scripts/`](reproducibility/hpc_scripts/). Site modules, scheduler resources,
GPU count, precision, and the effective global batch size should be recorded as part of the run.
See [`reproducibility/HPC.md`](reproducibility/HPC.md) for the migration checklist.

## Training, logging, prediction, and evaluation

All operational scripts use `MOTIF_REPRO_ROOT` for checkpoints, predictions, results, W&B data,
logs, manifests, and provenance.

```bash
# One-batch integration check (dry run by default).
bash reproducibility/scripts/08_smoke_train.sh --experiment fm_pmw

# Proper configurable training: preview, then launch.
bash reproducibility/scripts/11_train.sh --experiment fm_pmw
bash reproducibility/scripts/11_train.sh --experiment fm_pmw --name my_run --execute

# Inspect or hash checkpoints received from another machine.
.venv/bin/python reproducibility/scripts/07_audit_checkpoints.py --hash RUN_ID

# Predict and evaluate a trained run.
bash reproducibility/scripts/09_predict.sh RUN_ID fm_gpm_PI_dt6 test
bash reproducibility/scripts/10_evaluate.sh \
  '{FM: [RUN_ID, fm_gpm_PI_dt6]}' my_evaluation test '[quantitative,visual]'
```

`11_train.sh` exposes devices, nodes, per-device batch size, workers, gradient accumulation,
epochs, seed, checkpoint interval, W&B mode/project/entity, resuming, and arbitrary extra Hydra
overrides. It prints the effective global batch and complete command before execution. W&B can run
offline for disconnected systems or online after login; processing logs remain under the
reproduction root.

The wrappers ultimately call the standard entry points:

- [`scripts/train.py`](scripts/train.py): train and checkpoint a configured experiment;
- [`scripts/make_predictions.py`](scripts/make_predictions.py): load a run and write validation or test predictions;
- [`scripts/eval.py`](scripts/eval.py): compute metrics and generate analyses and visualizations;
- [`reproducibility/collect_provenance.sh`](reproducibility/collect_provenance.sh): record Git, lockfile, Python, packages, OS, CPU, memory, filesystem, and GPU information.

## Reproduction documentation

Start with [`reproducibility/README.md`](reproducibility/README.md) for the full gated runbook.
Supporting documents describe the exact
[data profiles and storage layout](reproducibility/DATA.md),
[preprocessing stages](reproducibility/PREPROCESSING.md),
[training and W&B workflow](reproducibility/TRAINING.md),
[checkpoint layout](reproducibility/CHECKPOINTS.md), and
[current reproduction status](reproducibility/STATUS.md).

For direct, non-wrapper use, create environment-specific files from
[`configs/paths/example.yaml`](configs/paths/example.yaml) and
[`configs/setup/example.yaml`](configs/setup/example.yaml), then invoke the Python entry points with
Hydra overrides. The reproducibility wrappers are recommended because they make profile selection,
verification, logs, and safety checks consistent between local and HPC runs.
