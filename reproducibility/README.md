# MOTIF reproduction runbook

This directory is the self-contained operational runbook for reproducing MOTIF at commit
`7b0cc0741b7f15658c8609c9780aaf24dc88b810`.

The preflight permits commits containing this runbook, `.gitignore`, and the documented W&B
compatibility config on top of that pinned scientific-code commit. Any other committed scientific-
code change remains a hard failure.

It covers:

1. environment and host provenance;
2. bounded TC-PRIMED inventory and download;
3. raw-data completeness checks;
4. PMW/infrared preprocessing, splits, and normalization;
5. processed-data checks;
6. checkpoint auditing;
7. smoke training, prediction, and evaluation;
8. migration to an HPC system.

Research data and model artifacts are stored outside the Git checkout. Machine-specific settings
are read from the ignored `config.local.env`. A committed, documented template is provided:

```bash
cp reproducibility/config.example.env reproducibility/config.local.env
```

Edit the local copy for each machine. This checkout currently uses:

```ini
MOTIF_REPRO_ROOT=/data1/datasets/motif-repro
MOTIF_DEFAULT_PROFILE=local100
```

On the HPC, set its storage root and `MOTIF_DEFAULT_PROFILE=full` in the HPC clone's own
`config.local.env`. Command-line arguments override exported environment variables, which override
the local config, which overrides built-in defaults. Set `MOTIF_CONFIG_FILE` to use a differently
named config file.

## Configurable dataset profiles

The default local profile is `local100`:

| Split | Years |
|---|---|
| Train | 1993, 2003, 2009, 2016 |
| Validation | 2014 |
| Test | 2015 |

It selects specific basins within those years and contains 14,972 objects totaling
100,461,087,970 bytes (100.46 GB / 93.56 GiB). It covers every PMW source named by the active
experiment configurations.

The HPC profile is `full`: all basins for every available year, 1987–2024. It contains 256,860
objects totaling 1,865,733,153,682 bytes (1.866 TB / 1.697 TiB).

`core6` and `extended8` remain available as intermediate profiles. Budgets and required free-space
reserves are profile-specific and can be overridden with `MOTIF_RAW_BUDGET_BYTES` and
`MOTIF_STORAGE_RESERVE_BYTES`.

## Quick start

Commands are dry-run by default when they can download data or launch costly processing.

```bash
# 0. Verify repository, budget, tools, and storage.
bash reproducibility/scripts/00_preflight.sh

# 1. Recreate the exact locked Python environment and capture host provenance.
bash reproducibility/scripts/01_setup_environment.sh

# 2. Refresh the public-bucket inventory without downloading data.
.venv/bin/python reproducibility/scripts/02_inventory_tc_primed.py \
  --expect-bytes 100461087970

# 3. Preview, then explicitly execute the raw download.
bash reproducibility/scripts/03_download_tc_primed_subset.sh
bash reproducibility/scripts/03_download_tc_primed_subset.sh --execute

# 4. Verify every downloaded path and byte size against the saved remote manifest.
.venv/bin/python reproducibility/scripts/04_verify_raw_tc_primed.py

# 5. Preview, then run preprocessing.
bash reproducibility/scripts/05_preprocess_tc_primed.sh
bash reproducibility/scripts/05_preprocess_tc_primed.sh --execute

# 6. Verify sources, split seasons, constants, metadata paths, and NetCDF samples.
.venv/bin/python reproducibility/scripts/06_verify_preprocessed.py
```

After processed data passes verification, checkpoint and model commands are:

```bash
# Audit received checkpoints and optionally hash them.
.venv/bin/python reproducibility/scripts/07_audit_checkpoints.py --hash RUN_ID

# Preview a one-batch smoke training run.
bash reproducibility/scripts/08_smoke_train.sh --experiment fm_pmw

# Preview proper custom training with the ignored local settings.
bash reproducibility/scripts/11_train.sh --experiment fm_pmw

# Generate predictions after a checkpoint is available.
bash reproducibility/scripts/09_predict.sh RUN_ID fm_gpm_PI_dt6 test

# Evaluate saved predictions.
bash reproducibility/scripts/10_evaluate.sh \
  '{FM: [RUN_ID, gpm_PI_dt6]}' my_evaluation test '[quantitative,visual]'
```

For the authors' provided `fm_PI` checkpoint, keep generated predictions, visual evaluation images,
validation images, W&B logs, and fine-tune checkpoints under `reproducibility/anon_output`:

```bash
# Create the loader-compatible symlink layout for run_id=3hyfu3lz-1.
bash reproducibility/scripts/12_prepare_pretrained_checkpoint.sh

# Preview, then run a two-batch prediction + visual-evaluation smoke test.
bash reproducibility/scripts/13_smoke_pretrained_checkpoint.sh
bash reproducibility/scripts/13_smoke_pretrained_checkpoint.sh --execute

# Preview, then launch a fine-tune run initialized from the authors' weights.
bash reproducibility/scripts/14_finetune_pretrained_checkpoint.sh
bash reproducibility/scripts/14_finetune_pretrained_checkpoint.sh --execute
```

The scripts use the repository's original downloader and preprocessing entry points. They add
budget checks, explicit profiles, logs, and verification; they do not replace the scientific
processing implementation.

## SAR wind-speed fine-tuning

An optional feature workflow adapts the authors' `fm_PI` checkpoint to predict
held-out CyclObs SAR `wind_speed` fields conditioned on PMW and infrared observations.
Its download, preprocessing, fine-tuning, prediction, and evaluation helpers are dry
runs unless `--execute` is supplied. See [SAR.md](SAR.md) for commands, validation
gates, the checkpoint-transfer contract, and output layout.

## Documents

- [PLAN.md](PLAN.md): complete gated workflow and success criteria.
- [DATA.md](DATA.md): dataset profiles, exact sizes, paths, and limitations.
- [PREPROCESSING.md](PREPROCESSING.md): exact staged preprocessing, resume, outputs, and checks.
- [TRAINING.md](TRAINING.md): W&B setup, smoke/proper training, resume, and HPC adaptation.
- [CHECKPOINTS.md](CHECKPOINTS.md): required checkpoint layout and current blocker.
- [HPC.md](HPC.md): cloning and adapting this runbook to a cluster.
- [STATUS.md](STATUS.md): completed work and outstanding gates.
- [environment-2026-07-23.md](environment-2026-07-23.md): initial machine snapshot.

## Safety properties

- Download and preprocessing launchers require `--execute`.
- The download launcher enforces profile-specific byte ceilings.
- The destination root must be an absolute path and cannot be `/`.
- Downloads are resumable because the repository downloader skips same-size files.
- Raw verification compares every selected object by path and byte size.
- No script deletes raw data, processed data, predictions, or checkpoints.
