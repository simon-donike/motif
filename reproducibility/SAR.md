# SAR wind-speed fine-tuning

This workflow adapts the authors' PMW + infrared `fm_PI` checkpoint to predict the
CyclObs Level-2 C-band SAR `wind_speed` product. It predicts a scalar wind-speed
field in m/s at a held-out SAR overpass's known time, footprint, coordinates, and
land mask. It does not retrieve wind from raw SAR backscatter and does not predict
wind direction or vector components.

## Model and transfer contract

The `fm_PI_sar` experiment uses nearby passive microwave and infrared observations
within ±3 hours as context. `sar_cband` is always the reference and masked target.
The checkpoint transfer:

- restores the shared backbone and PMW/infrared embeddings;
- initializes the SAR embedding and output projection;
- discards the former PMW output projection;
- rejects every missing, unexpected, or shape-mismatched tensor outside that
  declared contract;
- starts a new optimizer and the `finetune` learning-rate schedule.

Validate the provided checkpoint without processed SAR data:

```bash
.venv/bin/python reproducibility/scripts/15_validate_sar_checkpoint_transfer.py
```

## Prepare and verify SAR data

Preview the selected profile seasons and stages:

```bash
bash reproducibility/scripts/16_prepare_sar_dataset.sh \
  --profile extended8 --stage all --resume
```

Execute only after checking the printed raw and processed roots:

```bash
bash reproducibility/scripts/16_prepare_sar_dataset.sh \
  --profile extended8 --stage all --resume --execute

.venv/bin/python reproducibility/scripts/17_verify_sar_preprocessed.py
```

The stages are `download`, `prepare`, `split`, `constants`, and `all`. Downloading
retains the complete CyclObs acquisition metadata but transfers only files from the
selected profile seasons. The split stage regenerates the shared train/validation/test
CSVs, and the constants stage updates only `sar_cband`.

Verification requires every split to contain at least one SAR target with both a PMW
and an infrared observation within ±3 hours. A profile without those collocations is
not usable for this experiment; select a broader profile rather than weakening the
experiment silently.

## Fine-tune

Preview a run:

```bash
bash reproducibility/scripts/18_finetune_pretrained_sar.sh \
  --profile extended8 --devices 1 --batch-size 1
```

Start it with `--execute`. Scale and schedule options accepted by the standard
training launcher can be passed directly; extra Hydra overrides follow `--`:

```bash
bash reproducibility/scripts/18_finetune_pretrained_sar.sh \
  --profile extended8 \
  --devices 2 \
  --batch-size 1 \
  --accumulate-grad-batches 8 \
  --max-epochs 50 \
  --execute -- \
  dataset.train.limit_samples=1000
```

The new run ID is printed by `scripts/train.py`. Fine-tuned checkpoints and generated
artifacts default to `reproducibility/anon_output`.

## Predict and evaluate

Use the fine-tuned run ID:

```bash
bash reproducibility/scripts/19_predict_sar.sh FINE_TUNED_RUN_ID \
  --split test --limit-batches 2

bash reproducibility/scripts/19_predict_sar.sh FINE_TUNED_RUN_ID \
  --split test --execute
```

The helper uses `inference_cfg=fm_sar_PI_dt6`, writes generative ensembles as
denormalized NetCDF fields, and runs quantitative and visual evaluation. The output is:

```text
reproducibility/anon_output/predictions/<run_id>/<pred_name>/<split>/
├── info_<rank>.csv
├── targets/sar_cband/<index>/<sample>.nc
└── predictions/sar_cband/<index>/<sample>.nc
```

Each prediction contains `wind_speed` with realization and integration-step
dimensions plus the SAR latitude, longitude, and time coordinates. Evaluation uses
the final integration step.

## Reproduction preflight

This branch intentionally changes scientific configuration and checkpoint-loading
code relative to the pinned reproduction commit. When running the reproduction
preflight on this branch, set `MOTIF_ALLOW_DIFFERENT_COMMIT=1` and record the feature
branch commit in the run provenance.
