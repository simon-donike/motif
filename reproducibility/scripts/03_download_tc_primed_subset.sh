#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

profile="$MOTIF_DEFAULT_PROFILE"
workers="$MOTIF_DOWNLOAD_WORKERS"
execute=0

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
        --execute)
            execute=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--profile local100|core6|extended8|full] [--workers N] [--execute]"
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

expected_bytes="$(motif_profile_bytes "$profile")"
budget_bytes="$(motif_profile_budget "$profile")"
mapfile -t scopes < <(motif_profile_scopes "$profile")

echo "Profile: $profile"
echo "Download scopes: ${scopes[*]}"
echo "Expected raw bytes: $expected_bytes"
echo "Budget bytes: $budget_bytes"
echo "Destination: $MOTIF_TC_PRIMED_ROOT"
echo "Workers: $workers"

if (( expected_bytes > budget_bytes )); then
    echo "Refusing download: profile exceeds raw budget." >&2
    exit 1
fi

if (( execute == 0 )); then
    echo
    echo "Dry run only. The following repository commands would run:"
    for scope in "${scopes[@]}"; do
        echo ".venv/bin/python -m preproc.tc_primed.download_tc_primed paths=example ... scope=$scope workers=$workers"
    done
    echo
    echo "Rerun with --execute to inventory the remote objects and start downloading."
    exit 0
fi

bash "$script_dir/00_preflight.sh" --profile "$profile"

mkdir -p "$MOTIF_REPRO_ROOT/manifests" "$MOTIF_REPRO_ROOT/logs"
summary_manifest="$MOTIF_REPRO_ROOT/manifests/tc_primed_${profile}_summary.csv"
objects_manifest="$MOTIF_REPRO_ROOT/manifests/tc_primed_${profile}_objects.csv"
log_file="$MOTIF_REPRO_ROOT/logs/download_tc_primed_${profile}.log"
completion_file="$MOTIF_REPRO_ROOT/manifests/tc_primed_${profile}_download_complete.txt"

# A previous success record must not survive a failed rerun.
rm -f "$completion_file"

"$MOTIF_REPO_ROOT/.venv/bin/python" "$script_dir/02_inventory_tc_primed.py" \
    --profile "$profile" \
    --expect-bytes "$expected_bytes" \
    --max-bytes "$budget_bytes" \
    --output "$summary_manifest" \
    --objects-output "$objects_manifest"

run_downloads() {
    local scope
    local year
    local basin
    local -a basin_args
    cd "$MOTIF_REPO_ROOT"
    for scope in "${scopes[@]}"; do
        year="${scope%%:*}"
        basin_args=()
        if [[ "$scope" == *:* ]]; then
            basin="${scope#*:}"
            basin_args+=("+basin=$basin")
            echo "Downloading TC-PRIMED year $year basin $basin"
        else
            echo "Downloading TC-PRIMED year $year (all basins)"
        fi
        "$MOTIF_REPO_ROOT/.venv/bin/python" -m preproc.tc_primed.download_tc_primed \
            "${MOTIF_PATH_OVERRIDES[@]}" \
            "+year=$year" \
            "${basin_args[@]}" \
            "+workers=$workers"
    done
}

run_downloads 2>&1 | tee -a "$log_file"

completion_tmp="$(mktemp "$MOTIF_REPRO_ROOT/manifests/.download_complete.XXXXXX")"
{
    echo "profile=$profile"
    echo "expected_files=$(awk -F, 'END {print $3}' "$summary_manifest")"
    echo "expected_bytes=$expected_bytes"
    echo "objects_manifest=$objects_manifest"
    echo "completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$completion_tmp"
mv "$completion_tmp" "$completion_file"

{
    echo "Download commands completed."
    echo "Completion record: $completion_file"
    echo "Object manifest: $objects_manifest"
    echo "Log: $log_file"
    echo "Run 04_verify_raw_tc_primed.py before preprocessing."
} | tee -a "$log_file"
