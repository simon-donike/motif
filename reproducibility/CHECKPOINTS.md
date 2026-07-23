# Checkpoint acquisition and audit

## Required layout

The repository does not download checkpoints. It searches the local filesystem:

```text
<MOTIF_REPRO_ROOT>/checkpoints/<run_id>/*.ckpt
```

Example:

```text
/data1/datasets/motif-repro/checkpoints/
├── k2s7ctuk/
│   └── k2s7ctuk-epoch=...-best.ckpt
└── 4yspbbv7-4/
    └── 4yspbbv7-4-epoch=...-best.ckpt
```

Historical run IDs mentioned by `commands.md` include:

- `k2s7ctuk`
- `0y7cjuuv`
- `frlwvx27-3`
- `4yspbbv7-4`

These identifiers are not download URLs.

## Provenance required for each checkpoint

Record:

- source URL, transfer mechanism, or author;
- received filename;
- SHA-256 hash;
- byte size;
- run ID;
- claimed experiment;
- claimed epoch/step;
- date acquired.

Run:

```bash
.venv/bin/python reproducibility/scripts/07_audit_checkpoints.py \
  --hash \
  k2s7ctuk 4yspbbv7-4
```

The script checks the same directory convention used by repository inference, loads the checkpoint
on CPU, and summarizes its embedded configuration and state dict.

## Current blocker

No public release or checkpoint downloader is present in the repository, and training configures
W&B with `log_model=False`. Obtain the actual `.ckpt` files from the authors or another verifiable
source before claiming authors' checkpoint inference has been reproduced.

