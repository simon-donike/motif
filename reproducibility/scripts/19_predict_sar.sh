#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 RUN_ID [options] [-- extra prediction Hydra overrides]" >&2
    exit 2
fi

run_id="$1"
shift
split="test"
pred_name="fm_sar_PI_dt6"
eval_name="fm_sar_PI_dt6"
limit_batches=""
eval_classes="[quantitative,visual]"
accelerator="gpu"
execute=0
extra_overrides=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --split) split="$2"; shift 2 ;;
        --pred-name) pred_name="$2"; shift 2 ;;
        --eval-name) eval_name="$2"; shift 2 ;;
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
            echo "Usage: $0 RUN_ID [options] [-- extra prediction Hydra overrides]"
            echo
            echo "Options:"
            echo "  --split val|test              Default: test"
            echo "  --pred-name NAME              Default: fm_sar_PI_dt6"
            echo "  --eval-name NAME              Default: fm_sar_PI_dt6"
            echo "  --limit-batches N             Optional prediction batch limit"
            echo "  --eval-classes HYDRA_LIST     Default: [quantitative,visual]"
            echo "  --accelerator cpu|gpu|auto    Default: gpu"
            echo "  --execute"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ "$split" != "val" && "$split" != "test" ]]; then
    echo "split must be val or test" >&2
    exit 2
fi
case "$accelerator" in
    cpu|gpu|auto) ;;
    *) echo "accelerator must be cpu, gpu, or auto" >&2; exit 2 ;;
esac
if [[ -n "$limit_batches" ]] && ! [[ "$limit_batches" =~ ^[1-9][0-9]*$ ]]; then
    echo "limit-batches must be a positive integer" >&2
    exit 2
fi

predict_overrides=(
    "${MOTIF_ANON_PATH_OVERRIDES[@]}"
    "pred_name=$pred_name"
    "trainer.accelerator=$accelerator"
    "${extra_overrides[@]}"
)
if [[ -n "$limit_batches" ]]; then
    predict_overrides+=("+trainer.limit_predict_batches=$limit_batches")
fi

predict_command=(
    bash "$script_dir/09_predict.sh"
    "$run_id"
    fm_sar_PI_dt6
    "$split"
    "${predict_overrides[@]}"
)
eval_command=(
    bash "$script_dir/10_evaluate.sh"
    "{SAR_fine_tune: [$run_id, $pred_name]}"
    "$eval_name"
    "$split"
    "$eval_classes"
    "${MOTIF_ANON_PATH_OVERRIDES[@]}"
)

echo "Anonymous output root: $MOTIF_ANON_OUTPUT_ROOT"
echo "Expected variable: sar_cband/wind_speed (denormalized m/s)"
printf 'Prediction command:'
printf ' %q' "${predict_command[@]}"
printf '\n'
printf 'Evaluation command:'
printf ' %q' "${eval_command[@]}"
printf '\n'

if (( execute == 0 )); then
    echo "Dry run only. Rerun with --execute to predict and evaluate held-out SAR overpasses."
    exit 0
fi

mkdir -p "$MOTIF_ANON_OUTPUT_ROOT"/{predictions,results,wandb,matplotlib}

"$MOTIF_REPO_ROOT/.venv/bin/python" \
    "$script_dir/17_verify_sar_preprocessed.py"
"${predict_command[@]}"
"$MOTIF_REPO_ROOT/.venv/bin/python" \
    "$script_dir/20_verify_sar_predictions.py" \
    "$run_id" "$pred_name" "$split" \
    --predictions-root "$MOTIF_ANON_OUTPUT_ROOT/predictions"
"${eval_command[@]}"

echo "Predictions: $MOTIF_ANON_OUTPUT_ROOT/predictions/$run_id/$pred_name/$split"
