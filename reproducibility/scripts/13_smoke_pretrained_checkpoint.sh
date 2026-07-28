#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

run_id="3hyfu3lz-1"
pred_name="authors_fm_PI_smoke"
eval_name="authors_fm_PI_smoke"
split="val"
inference_cfg="default"
limit_batches="2"
eval_classes="[visual]"
accelerator="cpu"
execute=0
extra_overrides=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) run_id="$2"; shift 2 ;;
        --pred-name) pred_name="$2"; shift 2 ;;
        --eval-name) eval_name="$2"; shift 2 ;;
        --split) split="$2"; shift 2 ;;
        --inference-cfg) inference_cfg="$2"; shift 2 ;;
        --limit-batches) limit_batches="$2"; shift 2 ;;
        --eval-classes) eval_classes="$2"; shift 2 ;;
        --accelerator) accelerator="$2"; shift 2 ;;
        --execute) execute=1; shift ;;
        --)
            shift
            extra_overrides=("$@")
            break
            ;;
        -h|--help)
            echo "Usage: $0 [options] [-- extra Hydra overrides for prediction]"
            echo
            echo "Options:"
            echo "  --run-id RUN_ID              Default: 3hyfu3lz-1"
            echo "  --pred-name NAME             Default: authors_fm_PI_smoke"
            echo "  --eval-name NAME             Default: authors_fm_PI_smoke"
            echo "  --split val|test             Default: val"
            echo "  --inference-cfg NAME         Default: default"
            echo "  --limit-batches N            Default: 2"
            echo "  --eval-classes HYDRA_LIST    Default: [visual]"
            echo "  --accelerator cpu|gpu|auto   Default: cpu"
            echo "  --execute                    Actually run prediction and evaluation"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1 (put raw Hydra overrides after --)" >&2
            exit 2
            ;;
    esac
done

if [[ "$split" != "val" && "$split" != "test" ]]; then
    echo "Split must be val or test." >&2
    exit 2
fi
if ! [[ "$limit_batches" =~ ^[1-9][0-9]*$ ]]; then
    echo "limit-batches must be a positive integer: $limit_batches" >&2
    exit 2
fi
case "$accelerator" in
    cpu|gpu|auto) ;;
    *) echo "accelerator must be cpu, gpu, or auto: $accelerator" >&2; exit 2 ;;
esac

bash "$script_dir/12_prepare_pretrained_checkpoint.sh" "$run_id"
mkdir -p "$MOTIF_ANON_OUTPUT_ROOT"/{predictions,results,validation,wandb}
mkdir -p "$MOTIF_ANON_OUTPUT_ROOT"/{matplotlib,wandb/cache,wandb/config}

export WANDB_DIR="$MOTIF_ANON_OUTPUT_ROOT/wandb"
export WANDB_CACHE_DIR="$MOTIF_ANON_OUTPUT_ROOT/wandb/cache"
export WANDB_CONFIG_DIR="$MOTIF_ANON_OUTPUT_ROOT/wandb/config"
export MPLCONFIGDIR="$MOTIF_ANON_OUTPUT_ROOT/matplotlib"

predict_command=(
    bash "$script_dir/09_predict.sh"
    "$run_id"
    "$inference_cfg"
    "$split"
    "${MOTIF_ANON_PATH_OVERRIDES[@]}"
    "pred_name=$pred_name"
    "trainer.accelerator=$accelerator"
    "+trainer.limit_predict_batches=$limit_batches"
    "+trainer.enable_progress_bar=false"
    "${extra_overrides[@]}"
)

eval_command=(
    bash "$script_dir/10_evaluate.sh"
    "{Authors_fm_PI: [$run_id, $pred_name]}"
    "$eval_name"
    "$split"
    "$eval_classes"
    "${MOTIF_ANON_PATH_OVERRIDES[@]}"
)

echo "Anonymous output root: $MOTIF_ANON_OUTPUT_ROOT"
printf 'Prediction command:'
printf ' %q' "${predict_command[@]}"
printf '\n'
printf 'Evaluation command:'
printf ' %q' "${eval_command[@]}"
printf '\n'

if (( execute == 0 )); then
    echo "Dry run only. Rerun with --execute to generate predictions and images."
    exit 0
fi

"${predict_command[@]}"
"${eval_command[@]}"
