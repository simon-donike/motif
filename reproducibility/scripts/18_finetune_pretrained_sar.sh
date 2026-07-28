#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

run_id="3hyfu3lz-1"
checkpoint="$MOTIF_REPO_ROOT/reproducibility/pretrained_checkpoints/3hyfu3lz-1-epoch=34-step=91889.ckpt"
name="finetune_authors_fm_PI_sar"
profile="$MOTIF_DEFAULT_PROFILE"
execute=0
train_options=()
hydra_overrides=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) run_id="$2"; shift 2 ;;
        --checkpoint) checkpoint="$2"; shift 2 ;;
        --name) name="$2"; shift 2 ;;
        --profile) profile="$2"; shift 2 ;;
        --devices|--num-nodes|--batch-size|--workers|--max-epochs|--accumulate-grad-batches|--seed|--checkpoint-minutes|--wandb-mode|--wandb-project|--wandb-entity)
            train_options+=("$1" "$2")
            shift 2
            ;;
        --execute) execute=1; shift ;;
        --)
            shift
            hydra_overrides=("$@")
            break
            ;;
        -h|--help)
            echo "Usage: $0 [options] [-- extra Hydra overrides]"
            echo
            echo "Checkpoint: --run-id ID --checkpoint FILE"
            echo "Run: --name NAME --profile PROFILE --execute"
            echo "Scale: --devices N --num-nodes N --batch-size N --workers N"
            echo "       --max-epochs N --accumulate-grad-batches N"
            echo "Logging: --wandb-mode MODE --wandb-project NAME --wandb-entity NAME"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

command=(
    bash "$script_dir/11_train.sh"
    --experiment fm_PI_sar
    --profile "$profile"
    --name "$name"
    --resume-run-id "$run_id"
    --resume-mode fine_tune
    "${train_options[@]}"
)
if (( execute == 1 )); then
    command+=(--execute)
fi
command+=(
    --
    "${MOTIF_ANON_PATH_OVERRIDES[@]}"
    "${hydra_overrides[@]}"
)

echo "Anonymous output root: $MOTIF_ANON_OUTPUT_ROOT"
echo "SAR target: sar_cband/wind_speed"
printf 'Fine-tune command:'
printf ' %q' "${command[@]}"
printf '\n'

if (( execute == 0 )); then
    echo "Dry run only. Rerun with --execute after SAR verification passes."
    exit 0
fi

bash "$script_dir/12_prepare_pretrained_checkpoint.sh" "$run_id" "$checkpoint"
mkdir -p "$MOTIF_ANON_OUTPUT_ROOT"/{checkpoints,validation,wandb}

"$MOTIF_REPO_ROOT/.venv/bin/python" \
    "$script_dir/17_verify_sar_preprocessed.py"
"$MOTIF_REPO_ROOT/.venv/bin/python" \
    "$script_dir/15_validate_sar_checkpoint_transfer.py" \
    --checkpoint "$checkpoint"
"${command[@]}"
