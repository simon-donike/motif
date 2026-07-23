# MOTIF training

This is the self-contained procedure for smoke tests, proper local custom training, checkpoint
resume, W&B logging, and adaptation to an HPC scheduler. Training uses the pinned repository's
`scripts/train.py` and original experiment/model/optimizer/scheduler configurations.

## Recovered versus reconstructed configuration

The upstream Git repository has one branch, no tags, and 137 reachable commits back to the initial
commit. `configs/wandb/default.yaml` is absent from every reachable commit and from dangling Git
objects. The training root config nevertheless requires `wandb: default`, so upstream training
cannot compose as published.

The committed `configs/wandb/default.yaml` is therefore an explicit compatibility reconstruction,
not an author-recovered file. It provides only `project`, `entity`, `mode`, and `save_code`.
Experiment configs retain authority over run `name` and `group`, while the launcher overrides local
project/entity/mode settings. This restores Hydra composition without changing model optimization.

## W&B modes and authentication

The ignored `config.local.env` defaults to `MOTIF_WANDB_MODE=offline`. Offline mode needs no
account, retains run metadata under `<MOTIF_REPRO_ROOT>/wandb`, and can later upload with `wandb
sync`. `disabled` suppresses W&B recording. `online` uploads during training and requires login.

Authenticate interactively on each machine that will run online logging:

```bash
uv run wandb login --verify
uv run wandb status
```

The first command prompts for a key obtained through W&B. Enter it in the terminal, never in this
repository or `config.local.env`. On an HPC, prefer the site's secret manager to inject
`WANDB_API_KEY`; do not place the key in job scripts or Git. Set these non-secret local values:

```ini
MOTIF_WANDB_MODE=online
MOTIF_WANDB_PROJECT=motif-reproduction
MOTIF_WANDB_ENTITY=your-team-or-user
```

## Prerequisite gate

Training is refused until processed-data verification passes:

```bash
.venv/bin/python reproducibility/scripts/06_verify_preprocessed.py
```

## Smoke test

After preprocessing, instantiate a model, run one train/validation batch, and produce a checkpoint:

```bash
bash reproducibility/scripts/08_smoke_train.sh --experiment fm_pmw
bash reproducibility/scripts/08_smoke_train.sh --experiment fm_pmw --execute
```

Repeat for `det_PI`, `fm_PI_gpm`, and `fm_PI` before a long run.

## Proper local training

The local ignored config defaults to two RTX 3090 GPUs, batch size one per GPU, and eight gradient
accumulation steps. Its effective global batch is 16, matching the authors' 8 GPUs x batch 2, but
hardware, communication, and the `local100` data distribution still differ from the author run.

Preview first:

```bash
bash reproducibility/scripts/11_train.sh --experiment fm_pmw
```

Start the full configured 100-epoch run only after checking the printed composition:

```bash
bash reproducibility/scripts/11_train.sh --experiment fm_pmw --execute
```

Run names default to the experiment name. The launcher explicitly corrects the `fm_PI_gpm` run
name, whose experiment YAML otherwise says `fm_PI`. Override any setting for a single run:

```bash
bash reproducibility/scripts/11_train.sh \
  --experiment det_PI \
  --devices 2 \
  --batch-size 1 \
  --accumulate-grad-batches 8 \
  --max-epochs 100 \
  --wandb-mode offline \
  --name local100_det_PI \
  --execute
```

Raw Hydra overrides may be appended after `--`; they are recorded in the embedded checkpoint cfg:

```bash
bash reproducibility/scripts/11_train.sh --experiment fm_pmw -- \
  dataset.train.limit_samples=1000
```

## Checkpoints and resume

Training writes best-validation and timed checkpoints under:

```text
<MOTIF_REPRO_ROOT>/checkpoints/<RUN_ID>/*.ckpt
```

Preview and resume the latest checkpoint for a run:

```bash
bash reproducibility/scripts/11_train.sh \
  --experiment fm_pmw --resume-run-id RUN_ID --resume-mode resume

bash reproducibility/scripts/11_train.sh \
  --experiment fm_pmw --resume-run-id RUN_ID --resume-mode resume --execute
```

Use `--resume-mode fine_tune` to load weights into a new run without restoring optimizer/trainer
state. Audit checkpoint contents and hashes with `07_audit_checkpoints.py`.

## Author-scale and HPC training

The published commands use `setup=jz_8xh100`: two Jean-Zay nodes, four H100 GPUs per node, batch
size two per GPU, BF16 mixed precision, and no gradient accumulation. That setup embeds the
authors' account, module commands, and scheduler details and is not portable to another cluster.

Create a site-specific setup YAML from `configs/setup/example.yaml`, preserving 8 H100 GPUs and an
effective global batch of 16 when exact author-scale mechanics are intended. Then preview a
scheduler submission, for example:

```bash
bash reproducibility/scripts/11_train.sh \
  --experiment fm_pmw \
  --profile full \
  --setup YOUR_8XH100_SETUP \
  --devices 4 \
  --num-nodes 2 \
  --batch-size 2 \
  --accumulate-grad-batches 1 \
  --wandb-mode online
```

With a non-`local` setup, `scripts/train.py` submits through Submitit. Confirm the printed setup,
paths, account, partition, GPU constraint, and W&B entity before adding `--execute`.

## Acceptance sequence

1. All four one-batch smoke tests finish with finite losses.
2. A smoke checkpoint loads and produces predictions.
3. A tiny fixed subset can be overfit.
4. Interrupted training resumes with optimizer, scheduler, epoch, and step restored.
5. The selected proper run records resolved configuration, seed, effective batch, checkpoints,
   losses, GPU topology, wall time, and W&B mode.
