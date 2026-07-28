#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

run_id="3hyfu3lz-1"
experiment="fm_PI"
name="finetune_authors_fm_PI"
execute=0
train_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) run_id="$2"; shift 2 ;;
        --experiment) experiment="$2"; shift 2 ;;
        --name) name="$2"; shift 2 ;;
        --execute) execute=1; shift ;;
        --)
            shift
            train_args=("$@")
            break
            ;;
        -h|--help)
            echo "Usage: $0 [options] [-- additional 11_train.sh options/Hydra overrides]"
            echo
            echo "Options:"
            echo "  --run-id RUN_ID       Default: 3hyfu3lz-1"
            echo "  --experiment NAME     Default: fm_PI"
            echo "  --name RUN_NAME       Default: finetune_authors_fm_PI"
            echo "  --execute             Actually launch training"
            echo
            echo "Example smoke-sized fine-tune:"
            echo "  $0 --execute -- --max-epochs 1 --devices 1 --batch-size 1 --workers 0 -- ++trainer.limit_train_batches=2 ++trainer.limit_val_batches=2"
            exit 0
            ;;
        *)
            train_args+=("$1")
            shift
            ;;
    esac
done

bash "$script_dir/12_prepare_pretrained_checkpoint.sh" "$run_id"
mkdir -p "$MOTIF_ANON_OUTPUT_ROOT"/{checkpoints,validation,wandb}

command=(
    bash "$script_dir/11_train.sh"
    --experiment "$experiment"
    --name "$name"
    --resume-run-id "$run_id"
    --resume-mode fine_tune
    "${train_args[@]}"
)

if (( execute == 1 )); then
    command+=(--execute)
fi

command+=(
    --
    "${MOTIF_ANON_PATH_OVERRIDES[@]}"
    "+load_state_strict=true"
)

echo "Anonymous output root: $MOTIF_ANON_OUTPUT_ROOT"
printf 'Fine-tune command:'
printf ' %q' "${command[@]}"
printf '\n'

if (( execute == 0 )); then
    echo "Dry run only. Rerun with --execute to launch fine-tuning."
    exit 0
fi

"${command[@]}"
