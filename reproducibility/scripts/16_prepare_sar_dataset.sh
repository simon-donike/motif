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
        --profile) profile="$2"; shift 2 ;;
        --workers) workers="$2"; shift 2 ;;
        --stage) stage="$2"; shift 2 ;;
        --resume) resume=1; shift ;;
        --execute) execute=1; shift ;;
        -h|--help)
            echo "Usage: $0 [--profile local100|core6|extended8|full] [--stage download|prepare|split|constants|all] [--workers N] [--resume] [--execute]"
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
    download|prepare|split|constants|all) ;;
    *) echo "stage must be download, prepare, split, constants, or all" >&2; exit 2 ;;
esac

years_csv="$(motif_years_csv "$profile")"
years_yaml="[$years_csv]"
sar_raw_root="$MOTIF_RAW_ROOT/sar_cyclobs"
sar_prepared_root="$MOTIF_PREPROCESSED_ROOT/prepared/sar_cband"

echo "Profile: $profile"
echo "Included seasons: $years_yaml"
echo "Raw SAR root: $sar_raw_root"
echo "Prepared SAR root: $sar_prepared_root"
echo "Workers: $workers"
echo "Stage: $stage"
echo "Resume mode: $resume"

if (( execute == 0 )); then
    echo
    echo "Dry run only. Selected entry points:"
    [[ "$stage" == "download" || "$stage" == "all" ]] && \
        echo "1. preproc.sar.download_sar_cyclobs (season-filtered downloads)"
    [[ "$stage" == "prepare" || "$stage" == "all" ]] && \
        echo "2. preproc.sar.prepare_sar"
    [[ "$stage" == "split" || "$stage" == "all" ]] && \
        echo "3. preproc.train_val_test_split"
    [[ "$stage" == "constants" || "$stage" == "all" ]] && \
        echo "4. preproc.compute_normalization_constants (sar_cband only)"
    echo
    echo "Rerun with --execute to perform the selected stage."
    exit 0
fi

mkdir -p "$MOTIF_REPRO_ROOT/logs"
log_file="$MOTIF_REPRO_ROOT/logs/preprocess_sar_${profile}_${stage}.log"

run_download() {
    "$MOTIF_REPO_ROOT/.venv/bin/python" -m preproc.sar.download_sar_cyclobs \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "sar_download.workers=$workers" \
        "+include_seasons=$years_yaml"
}

run_prepare() {
    local resume_args=()
    if (( resume == 1 )); then
        resume_args+=("+check_older=36500d")
    fi
    "$MOTIF_REPO_ROOT/.venv/bin/python" -m preproc.sar.prepare_sar \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers" \
        "+include_seasons=$years_yaml" \
        "${resume_args[@]}"
}

run_split() {
    "$MOTIF_REPO_ROOT/.venv/bin/python" -m preproc.train_val_test_split \
        "${MOTIF_PATH_OVERRIDES[@]}"
}

run_constants() {
    "$MOTIF_REPO_ROOT/.venv/bin/python" -m preproc.compute_normalization_constants \
        "${MOTIF_PATH_OVERRIDES[@]}" \
        "+num_workers=$workers" \
        "+process_only=[sar_cband]"
}

run_workflow() {
    cd "$MOTIF_REPO_ROOT"
    case "$stage" in
        download) run_download ;;
        prepare) run_prepare ;;
        split) run_split ;;
        constants) run_constants ;;
        all)
            run_download
            run_prepare
            run_split
            run_constants
            ;;
    esac
}

run_workflow 2>&1 | tee -a "$log_file"

echo "SAR preprocessing command completed."
echo "Log: $log_file"
if [[ "$stage" == "all" || "$stage" == "constants" ]]; then
    echo "Next: .venv/bin/python reproducibility/scripts/17_verify_sar_preprocessed.py"
fi
