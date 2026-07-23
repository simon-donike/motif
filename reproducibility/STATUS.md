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
| Raw download | Complete locally | `local100`: 14,972 files, 100,461,087,970 bytes |
| Raw verification | Complete locally | Exact manifest/size match; 20 NetCDF samples passed |
| Preprocessing | Running locally | `local100` all-stage run in detached screen session |
| Processed verification | Not started | Requires preprocessing |
| Authors' checkpoints | Blocked | No checkpoint source supplied |
| Canonical W&B config | Unrecoverable | Compatibility reconstruction committed and documented |
| Local W&B authentication | Complete | Credentials remain outside Git; local mode configured online |
| Checkpoint inference | Not started | Requires checkpoint gate |
| Custom training | Ready, not started | Proper launcher/config ready; requires verified processed data |
