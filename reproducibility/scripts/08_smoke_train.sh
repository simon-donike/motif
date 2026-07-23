#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

experiment="fm_pmw"
execute=0
install_compat_wandb=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --experiment)
            experiment="$2"
            shift 2
            ;;
        --execute)
            execute=1
            shift
            ;;
        --install-compat-wandb)
            install_compat_wandb=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--experiment NAME] [--install-compat-wandb] [--execute]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

case "$experiment" in
    det_PI|fm_PI_gpm|fm_pmw|fm_PI) ;;
    *)
        echo "Unsupported active experiment: $experiment" >&2
        exit 2
        ;;
esac

wandb_config="$MOTIF_REPO_ROOT/configs/wandb/default.yaml"
compat_config="$script_dir/../configs/wandb/default.yaml"

echo "Experiment: $experiment"
echo "Dataset: $MOTIF_PREPROCESSED_ROOT"
echo "Checkpoint root: $MOTIF_REPRO_ROOT/checkpoints"
echo "Mode: one GPU, one train batch, one validation batch, one epoch"

if [[ ! -f "$wandb_config" && "$install_compat_wandb" == "1" ]]; then
    mkdir -p "$(dirname "$wandb_config")"
    cp "$compat_config" "$wandb_config"
    echo "Installed documented compatibility config: $wandb_config"
fi

if [[ ! -f "$wandb_config" ]]; then
    echo
    echo "Missing repository config: $wandb_config"
    echo "The original file was not committed. For a local disabled-W&B smoke test, run:"
    echo "bash reproducibility/scripts/08_smoke_train.sh --install-compat-wandb"
    echo "This compatibility file is a documented deviation, not the canonical author config."
    exit 1
fi

if (( execute == 0 )); then
    echo "Dry run only. Rerun with --execute after processed-data verification passes."
    exit 0
fi

"$MOTIF_REPO_ROOT/.venv/bin/python" "$script_dir/06_verify_preprocessed.py" --profile local100

cd "$MOTIF_REPO_ROOT"
uv run python scripts/train.py \
    "experiment=$experiment" \
    "model=motif_12b_d512" \
    "setup=local" \
    "${MOTIF_PATH_OVERRIDES[@]}" \
    "dataloader.batch_size=1" \
    "dataloader.num_workers=0" \
    "dataloader.persistent_workers=false" \
    "dataset.train.limit_samples=16" \
    "dataset.val.limit_samples=16" \
    "trainer.accelerator=gpu" \
    "trainer.devices=1" \
    "trainer.max_epochs=1" \
    "trainer.limit_train_batches=1" \
    "trainer.limit_val_batches=1" \
    "~trainer.strategy" \
    "wandb.mode=disabled" \
    "wandb.name=smoke_${experiment}" \
    "run_local=true"
