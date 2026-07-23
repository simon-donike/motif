#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

profile="$MOTIF_DEFAULT_PROFILE"
expected_commit="7b0cc0741b7f15658c8609c9780aaf24dc88b810"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            profile="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--profile local100|core6|extended8|full]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

expected_bytes="$(motif_profile_bytes "$profile")"
budget_bytes="$(motif_profile_budget "$profile")"
reserve_bytes="$(motif_profile_reserve "$profile")"
years="$(motif_years_csv "$profile")"

echo "Repository: $MOTIF_REPO_ROOT"
echo "Storage root: $MOTIF_REPRO_ROOT"
echo "TC-PRIMED destination: $MOTIF_TC_PRIMED_ROOT"
echo "Profile: $profile"
echo "Years: $years"
echo "Expected raw bytes: $expected_bytes"
echo "Raw budget bytes: $budget_bytes"

if (( expected_bytes > budget_bytes )); then
    echo "Profile exceeds the raw-data budget." >&2
    exit 1
fi

for command_name in git uv df; do
    if ! command -v "$command_name" >/dev/null; then
        echo "Required command not found: $command_name" >&2
        exit 1
    fi
done

actual_commit="$(git -C "$MOTIF_REPO_ROOT" rev-parse HEAD)"
if [[ "$actual_commit" != "$expected_commit" ]]; then
    if git -C "$MOTIF_REPO_ROOT" merge-base --is-ancestor "$expected_commit" "$actual_commit"; then
        mapfile -t changed_scientific_files < <(
            git -C "$MOTIF_REPO_ROOT" diff --name-only "$expected_commit..$actual_commit" -- \
                . ':(exclude).gitignore' ':(exclude)reproducibility/**'
        )
        if (( ${#changed_scientific_files[@]} == 0 )); then
            echo "Pinned scientific code is unchanged; HEAD adds only the reproducibility runbook."
        elif [[ "${MOTIF_ALLOW_DIFFERENT_COMMIT:-0}" != "1" ]]; then
            echo "Scientific files changed after pinned commit $expected_commit:" >&2
            printf "  %s\n" "${changed_scientific_files[@]}" >&2
            echo "Set MOTIF_ALLOW_DIFFERENT_COMMIT=1 only for a documented deviation." >&2
            exit 1
        fi
    elif [[ "${MOTIF_ALLOW_DIFFERENT_COMMIT:-0}" != "1" ]]; then
        echo "Pinned commit $expected_commit is not an ancestor of HEAD $actual_commit." >&2
        echo "Set MOTIF_ALLOW_DIFFERENT_COMMIT=1 only for a documented deviation." >&2
        exit 1
    else
        echo "WARNING: continuing from non-pinned commit $actual_commit" >&2
    fi
fi

storage_probe="$MOTIF_REPRO_ROOT"
while [[ ! -e "$storage_probe" && "$storage_probe" != "/" ]]; do
    storage_probe="$(dirname "$storage_probe")"
done

available_bytes="$(df -B1 --output=avail "$storage_probe" | tail -n 1 | tr -d ' ')"
required_with_reserve=$((expected_bytes + reserve_bytes))
echo "Available bytes on destination filesystem: $available_bytes"
echo "Required free-space reserve beyond raw profile: $reserve_bytes"

if (( available_bytes < required_with_reserve )); then
    echo "Insufficient free space for raw profile plus configured reserve." >&2
    exit 1
fi

if [[ -d "$MOTIF_REPO_ROOT/.venv" ]]; then
    "$MOTIF_REPO_ROOT/.venv/bin/python" --version
    (
        cd "$MOTIF_REPO_ROOT"
        uv lock --check
    )
else
    echo "Environment not present yet; run 01_setup_environment.sh next."
fi

if command -v nvidia-smi >/dev/null; then
    nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader
else
    echo "nvidia-smi not found; acceptable on a download/login node."
fi

echo "Preflight passed. No files were downloaded or created."
