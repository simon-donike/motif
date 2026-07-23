#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

profile="$MOTIF_DEFAULT_PROFILE"
workers="$MOTIF_PREPROCESS_WORKERS"
stage="all"
execute=0
resume=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            profile="$2"
            shift 2
            ;;
        --workers)
            workers="$2"
            shift 2
            ;;
        --stage)
            stage="$2"
            shift 2
            ;;
        --resume)
            resume=1
            shift
            ;;
        --execute)
            execute=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--profile local100|core6|extended8|full] [--stage pmw|infrared|split|constants|all] [--workers N] [--resume] [--execute]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if ! [[ "$workers" =~ ^[1-9][0-9]*$ ]]; then
    echo "workers must be a positive integer" >&2
    exit 2
fi

case "$stage" in
    pmw|infrared|split|constants|all) ;;
    *)
        echo "stage must be pmw, infrared, split, constants, or all" >&2
        exit 2
        ;;
esac

years_csv="$(motif_years_csv "$profile")"
years_yaml="[$years_csv]"

echo "Profile: $profile"
echo "Included seasons: $years_yaml"
echo "Raw root: $MOTIF_TC_PRIMED_ROOT"
echo "Preprocessed root: $MOTIF_PREPROCESSED_ROOT"
echo "Workers: $workers"
echo "Stage: $stage"
echo "Resume mode: $resume"

if (( execute == 0 )); then
    echo
    echo "Dry run only. Selected repository entry points:"
    [[ "$stage" == "pmw" || "$stage" == "all" ]] && echo "1. prepare_pmw_concat.py"
    [[ "$stage" == "infrared" || "$stage" == "all" ]] && echo "2. prepare_infrared.py"
    [[ "$stage" == "split" || "$stage" == "all" ]] && echo "3. train_val_test_split.py"
    [[ "$stage" == "constants" || "$stage" == "all" ]] && echo "4. compute_normalization_constants.py"
    echo
    echo "Rerun with --execute after raw verification passes."
    exit 0
fi

"$MOTIF_REPO_ROOT/.venv/bin/python" "$script_dir/04_verify_raw_tc_primed.py" \
    --profile "$profile"

mkdir -p "$MOTIF_REPRO_ROOT/logs"
log_file="$MOTIF_REPRO_ROOT/logs/preprocess_tc_primed_${profile}_${stage}.log"

run_pmw() {
    local pmw_resume_args=()
    if (( resume == 1 )); then
        pmw_resume_args+=("+check_older=36500d")
    fi
    uv run python preproc/tc_primed/prepare_pmw_concat.py \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers" \
        "+include_seasons=$years_yaml" \
        "${pmw_resume_args[@]}"
}

run_infrared() {
    local ir_resume_args=()
    if (( resume == 1 )); then
        ir_resume_args+=("+check_exist=true")
    fi
    uv run python preproc/tc_primed/prepare_infrared.py \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers" \
        "+include_seasons=$years_yaml" \
        "${ir_resume_args[@]}"
}

run_split() {
    uv run python preproc/train_val_test_split.py "${MOTIF_PATH_OVERRIDES[@]}"
}

run_constants() {
    uv run python preproc/compute_normalization_constants.py \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers"
}

run_preprocessing() {
    cd "$MOTIF_REPO_ROOT"
    case "$stage" in
        pmw) run_pmw ;;
        infrared) run_infrared ;;
        split) run_split ;;
        constants) run_constants ;;
        all)
            run_pmw
            run_infrared
            run_split
            run_constants
            ;;
    esac
}

run_preprocessing 2>&1 | tee -a "$log_file"

echo "Preprocessing commands completed."
echo "Log: $log_file"
if [[ "$stage" == "all" || "$stage" == "constants" ]]; then
    echo "Run 06_verify_preprocessed.py next."
else
    echo "Continue with the next stage described in reproducibility/PREPROCESSING.md."
fi
