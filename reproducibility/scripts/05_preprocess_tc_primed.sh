#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

profile="$MOTIF_DEFAULT_PROFILE"
workers="$MOTIF_PREPROCESS_WORKERS"
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
        --resume)
            resume=1
            shift
            ;;
        --execute)
            execute=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--profile local100|core6|extended8|full] [--workers N] [--resume] [--execute]"
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

years_csv="$(motif_years_csv "$profile")"
years_yaml="[$years_csv]"

echo "Profile: $profile"
echo "Included seasons: $years_yaml"
echo "Raw root: $MOTIF_TC_PRIMED_ROOT"
echo "Preprocessed root: $MOTIF_PREPROCESSED_ROOT"
echo "Workers: $workers"
echo "Resume mode: $resume"

if (( execute == 0 )); then
    echo
    echo "Dry run only. Planned order:"
    echo "1. prepare_pmw_concat.py"
    echo "2. prepare_infrared.py"
    echo "3. train_val_test_split.py"
    echo "4. compute_normalization_constants.py"
    echo
    echo "Rerun with --execute after raw verification passes."
    exit 0
fi

"$MOTIF_REPO_ROOT/.venv/bin/python" "$script_dir/04_verify_raw_tc_primed.py" \
    --profile "$profile"

mkdir -p "$MOTIF_REPRO_ROOT/logs"
log_file="$MOTIF_REPRO_ROOT/logs/preprocess_tc_primed_${profile}.log"

run_preprocessing() {
    local pmw_resume_args=()
    local ir_resume_args=()
    if (( resume == 1 )); then
        pmw_resume_args+=("+check_older=36500d")
        ir_resume_args+=("+check_exist=true")
    fi

    cd "$MOTIF_REPO_ROOT"
    uv run python preproc/tc_primed/prepare_pmw_concat.py \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers" \
        "+include_seasons=$years_yaml" \
        "${pmw_resume_args[@]}"

    uv run python preproc/tc_primed/prepare_infrared.py \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers" \
        "+include_seasons=$years_yaml" \
        "${ir_resume_args[@]}"

    uv run python preproc/train_val_test_split.py "${MOTIF_PATH_OVERRIDES[@]}"

    uv run python preproc/compute_normalization_constants.py \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers"
}

run_preprocessing 2>&1 | tee -a "$log_file"

echo "Preprocessing commands completed."
echo "Log: $log_file"
echo "Run 06_verify_preprocessed.py next."
