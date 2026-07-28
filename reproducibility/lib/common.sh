#!/usr/bin/env bash

set -euo pipefail

MOTIF_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOTIF_CONFIG_FILE="${MOTIF_CONFIG_FILE:-$MOTIF_REPO_ROOT/reproducibility/config.local.env}"

motif_load_config() {
    local config_file="$1"
    local line
    local key
    local value
    [[ -f "$config_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" != *=* ]]; then
            echo "Invalid config line in $config_file: $line" >&2
            return 2
        fi
        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        if [[ ! "$key" =~ ^MOTIF_[A-Z0-9_]+$ ]]; then
            echo "Invalid config key in $config_file: $key" >&2
            return 2
        fi
        if [[ ! -v "$key" ]]; then
            printf -v "$key" "%s" "$value"
            export "$key"
        fi
    done < "$config_file"
}

motif_load_config "$MOTIF_CONFIG_FILE"

MOTIF_REPRO_ROOT="${MOTIF_REPRO_ROOT:-/data1/datasets/motif-repro}"
MOTIF_DEFAULT_PROFILE="${MOTIF_DEFAULT_PROFILE:-local100}"
MOTIF_DOWNLOAD_WORKERS="${MOTIF_DOWNLOAD_WORKERS:-8}"
MOTIF_PREPROCESS_WORKERS="${MOTIF_PREPROCESS_WORKERS:-4}"
MOTIF_TRAIN_DEVICES="${MOTIF_TRAIN_DEVICES:-2}"
MOTIF_TRAIN_NUM_NODES="${MOTIF_TRAIN_NUM_NODES:-1}"
MOTIF_TRAIN_BATCH_SIZE="${MOTIF_TRAIN_BATCH_SIZE:-1}"
MOTIF_TRAIN_WORKERS="${MOTIF_TRAIN_WORKERS:-4}"
MOTIF_TRAIN_MAX_EPOCHS="${MOTIF_TRAIN_MAX_EPOCHS:-100}"
MOTIF_TRAIN_ACCUMULATE_GRAD_BATCHES="${MOTIF_TRAIN_ACCUMULATE_GRAD_BATCHES:-8}"
MOTIF_TRAIN_SEED="${MOTIF_TRAIN_SEED:-42}"
MOTIF_CHECKPOINT_TIME_INTERVAL="${MOTIF_CHECKPOINT_TIME_INTERVAL:-30}"
MOTIF_WANDB_MODE="${MOTIF_WANDB_MODE:-offline}"
MOTIF_WANDB_PROJECT="${MOTIF_WANDB_PROJECT:-motif-reproduction}"
MOTIF_WANDB_ENTITY="${MOTIF_WANDB_ENTITY:-}"
MOTIF_RAW_ROOT="${MOTIF_REPRO_ROOT}/raw"
MOTIF_TC_PRIMED_ROOT="${MOTIF_RAW_ROOT}/tc_primed"
MOTIF_PREPROCESSED_ROOT="${MOTIF_REPRO_ROOT}/preprocessed"
MOTIF_ANON_OUTPUT_ROOT="${MOTIF_ANON_OUTPUT_ROOT:-$MOTIF_REPO_ROOT/reproducibility/anon_output}"
MOTIF_RAW_BUDGET_BYTES="${MOTIF_RAW_BUDGET_BYTES:-}"
MOTIF_STORAGE_RESERVE_BYTES="${MOTIF_STORAGE_RESERVE_BYTES:-}"

if [[ "$MOTIF_REPRO_ROOT" != /* ]]; then
    echo "MOTIF_REPRO_ROOT must be an absolute path: $MOTIF_REPRO_ROOT" >&2
    exit 2
fi
if [[ "$MOTIF_REPRO_ROOT" == "/" ]]; then
    echo "MOTIF_REPRO_ROOT cannot be /" >&2
    exit 2
fi

MOTIF_CORE6_YEARS=(1993 2003 2009 2014 2015 2016)
MOTIF_EXTENDED8_YEARS=(1993 2003 2009 2014 2015 2016 2021 2022)
MOTIF_FULL_YEARS=($(seq 1987 2024))
MOTIF_LOCAL100_BYTES=100461087970
MOTIF_CORE6_BYTES=362565758796
MOTIF_EXTENDED8_BYTES=518648600908
MOTIF_FULL_BYTES=1865733153682

motif_profile_scopes() {
    case "${1:-local100}" in
        local100)
            printf "%s\n" \
                1993:AL 1993:CP 1993:IO \
                2003:AL 2003:CP 2003:EP 2003:IO \
                2009:AL 2009:CP 2009:EP 2009:IO \
                2014:AL 2014:CP 2014:IO \
                2015:AL 2015:CP 2015:IO \
                2016:AL 2016:CP 2016:IO
            ;;
        core6)
            printf "%s\n" "${MOTIF_CORE6_YEARS[@]}"
            ;;
        extended8)
            printf "%s\n" "${MOTIF_EXTENDED8_YEARS[@]}"
            ;;
        full)
            printf "%s\n" "${MOTIF_FULL_YEARS[@]}"
            ;;
        *)
            echo "Unknown profile '$1'; expected local100, core6, extended8, or full." >&2
            return 2
            ;;
    esac
}

motif_profile_years() {
    case "${1:-local100}" in
        local100)
            printf "%s\n" "${MOTIF_CORE6_YEARS[@]}"
            ;;
        core6)
            printf "%s\n" "${MOTIF_CORE6_YEARS[@]}"
            ;;
        extended8)
            printf "%s\n" "${MOTIF_EXTENDED8_YEARS[@]}"
            ;;
        full)
            printf "%s\n" "${MOTIF_FULL_YEARS[@]}"
            ;;
        *)
            echo "Unknown profile '$1'; expected local100, core6, extended8, or full." >&2
            return 2
            ;;
    esac
}

motif_profile_bytes() {
    case "${1:-local100}" in
        local100)
            echo "$MOTIF_LOCAL100_BYTES"
            ;;
        core6)
            echo "$MOTIF_CORE6_BYTES"
            ;;
        extended8)
            echo "$MOTIF_EXTENDED8_BYTES"
            ;;
        full)
            echo "$MOTIF_FULL_BYTES"
            ;;
        *)
            echo "Unknown profile '$1'; expected local100, core6, extended8, or full." >&2
            return 2
            ;;
    esac
}

motif_years_csv() {
    local profile="${1:-local100}"
    local joined=""
    local year
    while IFS= read -r year; do
        if [[ -n "$joined" ]]; then
            joined+=","
        fi
        joined+="$year"
    done < <(motif_profile_years "$profile")
    echo "$joined"
}

motif_profile_budget() {
    local profile="${1:-local100}"
    if [[ -n "$MOTIF_RAW_BUDGET_BYTES" ]]; then
        echo "$MOTIF_RAW_BUDGET_BYTES"
        return
    fi
    case "$profile" in
        local100) echo 110000000000 ;;
        core6|extended8) echo 600000000000 ;;
        full) echo 2000000000000 ;;
        *) return 2 ;;
    esac
}

motif_profile_reserve() {
    local profile="${1:-local100}"
    if [[ -n "$MOTIF_STORAGE_RESERVE_BYTES" ]]; then
        echo "$MOTIF_STORAGE_RESERVE_BYTES"
        return
    fi
    case "$profile" in
        local100) echo 200000000000 ;;
        core6|extended8) echo 300000000000 ;;
        full) echo 1000000000000 ;;
        *) return 2 ;;
    esac
}

MOTIF_PATH_OVERRIDES=(
    "paths=example"
    "paths.raw_datasets=${MOTIF_RAW_ROOT}"
    "paths.tc_primed=${MOTIF_TC_PRIMED_ROOT}"
    "paths.sar_cyclobs=${MOTIF_RAW_ROOT}/sar_cyclobs"
    "paths.era5_weatherbench=${MOTIF_RAW_ROOT}/era5/1959-2023_01_10-6h-64x32_equiangular_conservative.zarr"
    "paths.preprocessed_dataset=${MOTIF_PREPROCESSED_ROOT}"
    "paths.checkpoints=${MOTIF_REPRO_ROOT}/checkpoints"
    "paths.wandb_logs=${MOTIF_REPRO_ROOT}/wandb"
    "paths.validation=${MOTIF_REPRO_ROOT}/validation"
    "paths.predictions=${MOTIF_REPRO_ROOT}/predictions"
    "paths.results=${MOTIF_REPRO_ROOT}/results"
)

MOTIF_ANON_PATH_OVERRIDES=(
    "paths.checkpoints=${MOTIF_ANON_OUTPUT_ROOT}/checkpoints"
    "paths.wandb_logs=${MOTIF_ANON_OUTPUT_ROOT}/wandb"
    "paths.validation=${MOTIF_ANON_OUTPUT_ROOT}/validation"
    "paths.predictions=${MOTIF_ANON_OUTPUT_ROOT}/predictions"
    "paths.results=${MOTIF_ANON_OUTPUT_ROOT}/results"
)

# Keep runtime metadata out of read-only home directories on shared/HPC systems.
export UV_CACHE_DIR="${UV_CACHE_DIR:-$MOTIF_REPO_ROOT/.uv-cache}"
export WANDB_DIR="${WANDB_DIR:-$MOTIF_REPRO_ROOT/wandb}"
export WANDB_CACHE_DIR="${WANDB_CACHE_DIR:-$MOTIF_REPRO_ROOT/wandb/cache}"
export WANDB_CONFIG_DIR="${WANDB_CONFIG_DIR:-$MOTIF_REPRO_ROOT/wandb/config}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-$MOTIF_REPRO_ROOT/matplotlib}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-1}"
