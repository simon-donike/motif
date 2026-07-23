# Reproduction status

Updated: 2026-07-23

| Step | Status | Notes |
|---|---|---|
| Repository pin | Complete | Commit `7b0cc074...` |
| Locked environment | Complete | Python 3.12.11, PyTorch 2.8.0 |
| Local GPU validation | Complete | 2 × RTX 3090 visible |
| Host provenance | Complete | See dated environment snapshot |
| TC-PRIMED full inventory | Complete | 1,865.73 GB observed |
| `local100` profile design | Complete | 100.46 GB, required sensors covered |
| `full` HPC profile design | Complete | 1.866 TB, all 1987–2024 data |
| Raw download | Not started | Await explicit `--execute` |
| Raw verification | Not started | Requires download |
| Preprocessing | Ready, not started | Staged runner and verification documented; requires verified raw data |
| Processed verification | Not started | Requires preprocessing |
| Authors' checkpoints | Blocked | No checkpoint source supplied |
| Canonical W&B config | Blocked | `configs/wandb/default.yaml` missing |
| Checkpoint inference | Not started | Requires checkpoint gate |
| Custom training | Not started | Requires processed data and W&B config decision |
