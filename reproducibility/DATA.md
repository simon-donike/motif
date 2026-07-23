# Dataset profiles and storage

## Public source

- Bucket: `s3://noaa-nesdis-tcprimed-pds`
- Prefix: `v01r01/final/`
- Authentication: anonymous
- Available years observed during inventory: 1987–2024
- Full observed size: 1,865,733,153,682 bytes across 256,860 objects

The full observed size is larger than the repository README's approximate 1.6 TB statement.

## Profiles

### `local100` — default local-testing profile

This profile selects basins rather than whole years:

| Year | Split | Basins |
|---:|---|---|
| 1993 | train | AL, CP, IO |
| 2003 | train | AL, CP, EP, IO |
| 2009 | train | AL, CP, EP, IO |
| 2014 | validation | AL, CP, IO |
| 2015 | test | AL, CP, IO |
| 2016 | train | AL, CP, IO |

Total: 14,972 objects and 100,461,087,970 bytes (100.46 GB / 93.56 GiB).

The training selection still contains all active configured PMW sensors:

- AMSR2/GCOM-W1
- GMI/GPM
- TMI/TRMM
- SSMI F11, F13, F14, F15
- SSMIS F16, F17, F18, F19

Validation and test both contain GMI targets, other PMW sources, and infrared observations.

### `full` — HPC reproduction profile

All basins for every available year, 1987–2024.

Total: 256,860 objects and 1,865,733,153,682 bytes (1.866 TB / 1.697 TiB).

The default full-profile raw budget is 2 TB, with an additional required 1 TB free-space reserve
for processed products and working space. Adjust these only after confirming the HPC quotas:

```bash
export MOTIF_RAW_BUDGET_BYTES=2000000000000
export MOTIF_STORAGE_RESERVE_BYTES=1000000000000
```

### `core6` — optional intermediate profile

| Year | Repository split | Objects | Bytes | GB |
|---:|---|---:|---:|---:|
| 1993 | train | 1,604 | 17,441,637,178 | 17.442 |
| 2003 | train | 7,080 | 55,645,418,697 | 55.645 |
| 2009 | train | 8,180 | 56,207,073,576 | 56.207 |
| 2014 | validation | 11,111 | 75,568,645,766 | 75.569 |
| 2015 | test | 13,134 | 86,058,286,011 | 86.058 |
| 2016 | train | 10,799 | 71,644,697,568 | 71.645 |
| **Total** | | **51,908** | **362,565,758,796** | **362.566** |

### `extended8`

Adds:

| Year | Repository split | Objects | Bytes | GB |
|---:|---|---:|---:|---:|
| 2021 | validation | 11,823 | 82,812,125,520 | 82.812 |
| 2022 | test | 10,492 | 73,270,716,592 | 73.271 |

Extended total: 74,223 objects and 518,648,600,908 bytes.

## Portable storage layout

With `MOTIF_REPRO_ROOT=/data1/datasets/motif-repro`:

```text
/data1/datasets/motif-repro/
├── raw/
│   └── tc_primed/
│       ├── 1993/
│       ├── 2003/
│       └── ...
├── preprocessed/
│   ├── prepared/
│   ├── constants/
│   ├── train.csv
│   ├── val.csv
│   └── test.csv
├── checkpoints/
├── predictions/
├── results/
├── validation/
├── wandb/
├── manifests/
├── logs/
└── provenance/
```

Default safety settings:

| Profile | Raw budget | Additional free-space reserve |
|---|---:|---:|
| `local100` | 110 GB | 200 GB |
| `core6` | 600 GB | 300 GB |
| `extended8` | 600 GB | 300 GB |
| `full` | 2 TB | 1 TB |

Budgets do not include preprocessed data, checkpoints, predictions, logs, or temporary working
space. Override them with `MOTIF_RAW_BUDGET_BYTES` and `MOTIF_STORAGE_RESERVE_BYTES`.

After every successful download, the launcher writes both its completion marker to the durable
download log and an atomic `manifests/tc_primed_<PROFILE>_download_complete.txt` record. A failed
or interrupted rerun cannot leave a stale success record. Raw verification, rather than this
record alone, remains the required preprocessing gate.

## Local configuration

Copy `config.example.env` to the Git-ignored `config.local.env` in each clone. The local config
controls the storage root, default profile, worker counts, byte budget, and free-space reserve.
Plain `KEY=VALUE` syntax is required. CLI options have highest precedence, followed by exported
environment variables, the local config, and built-in defaults.

## Subset limitation

The repository's split algorithm is retained exactly. `local100`, `core6`, and `extended8` change
the training distribution and sample count relative to a full-data author run. They validate
faithful mechanics and custom training, not full-data numerical results. Use `full` on the HPC for
the complete repository-defined data workflow.
