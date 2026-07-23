# TC-PRIMED preprocessing

This is the self-contained procedure for converting verified TC-PRIMED raw files into the PMW
and infrared dataset consumed by MOTIF's four active experiment configurations. The runner calls
the pinned repository's scientific implementation; it does not reimplement or alter it.

## Inputs and configuration

All commands read `reproducibility/config.local.env`. For the local checkout the defaults are:

```ini
MOTIF_REPRO_ROOT=/data1/datasets/motif-repro
MOTIF_DEFAULT_PROFILE=local100
MOTIF_PREPROCESS_WORKERS=4
```

Raw files must be under:

```text
<MOTIF_REPRO_ROOT>/raw/tc_primed/<year>/<basin>/...
```

The launcher supplies explicit Hydra path overrides, so it does not use the author-specific `jz`
paths in `configs/preproc.yaml`. It otherwise retains the pinned preprocessing defaults, including
native PMW grids, the repository's validation/test seasons, a six-hour same-source deduplication
interval, and normalization over the full selected training set.

## Prerequisite gate

Do not preprocess an incomplete download. This must pass first:

```bash
.venv/bin/python reproducibility/scripts/04_verify_raw_tc_primed.py
```

The preprocessing launcher repeats this raw-data gate whenever `--execute` is used.

## Preview

The default invocation is non-mutating and displays the selected paths, profile, years, workers,
and ordered entry points:

```bash
bash reproducibility/scripts/05_preprocess_tc_primed.sh
```

## Run one substage at a time

Run the following commands in order. Each command invokes the corresponding original repository
program and stops on a nonzero process exit:

```bash
# 1. Extract and concatenate native-grid passive-microwave samples by sensor/satellite.
bash reproducibility/scripts/05_preprocess_tc_primed.sh --stage pmw --execute

# 2. Extract TCIRAR/HURSAT infrared samples and derived masks/distances.
bash reproducibility/scripts/05_preprocess_tc_primed.sh --stage infrared --execute

# 3. Merge source metadata, deduplicate nearby observations, and create split CSVs.
bash reproducibility/scripts/05_preprocess_tc_primed.sh --stage split --execute

# 4. Compute training-data normalization and source-characteristic constants.
bash reproducibility/scripts/05_preprocess_tc_primed.sh --stage constants --execute
```

For an uninterrupted run of the same four commands in that order:

```bash
bash reproducibility/scripts/05_preprocess_tc_primed.sh --stage all --execute
```

`--profile` and `--workers` override the local config for one invocation.

## Resume after interruption

Only PMW and infrared extraction have repository-supported skip-existing behavior:

```bash
bash reproducibility/scripts/05_preprocess_tc_primed.sh --stage pmw --resume --execute
bash reproducibility/scripts/05_preprocess_tc_primed.sh --stage infrared --resume --execute
```

PMW resume returns metadata for an existing output younger than 36,500 days. Infrared resume uses
the repository's `check_exist` behavior. Split generation and normalization are deterministic
recomputation steps and should simply be rerun after extraction completes.

## Outputs

The expected layout is:

```text
<MOTIF_REPRO_ROOT>/preprocessed/
├── prepared/
│   ├── tc_primed_pmw_<SENSOR>_<SATELLITE>/
│   │   ├── source_metadata.json
│   │   ├── samples_metadata.csv
│   │   └── *.nc
│   ├── tc_primed_ir_tcirar/
│   └── tc_primed_ir_hursat/
├── constants/<SOURCE>/
│   ├── data_means.json
│   ├── data_stds.json
│   └── charac_vars_min_max.json
├── train.csv
├── val.csv
└── test.csv
```

Each execution log is appended to:

```text
<MOTIF_REPRO_ROOT>/logs/preprocess_tc_primed_<PROFILE>_<STAGE>.log
```

The pinned worker implementations can report and discard invalid samples while continuing. A zero
launcher exit alone is therefore not the acceptance gate; retain the logs and run verification.

## Final verification gate

After all four substages complete:

```bash
.venv/bin/python reproducibility/scripts/06_verify_preprocessed.py
```

It writes a JSON report under `<MOTIF_REPRO_ROOT>/manifests/` and fails if required sources,
metadata, split seasons, referenced NetCDF files, or normalization constants are missing or
invalid. Training must not start until this command prints `PROCESSED VERIFICATION PASSED`.

## Scope

This stage intentionally prepares PMW and infrared sources used by `det_PI`, `fm_PI_gpm`,
`fm_pmw`, and `fm_PI`. Radar, environmental ERA5, storm metadata, SAR, and standalone
WeatherBench preprocessing are later optional expansion stages and are not silently included.
