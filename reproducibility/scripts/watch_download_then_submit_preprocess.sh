#!/usr/bin/env bash

set -euo pipefail

cd /lustre/scratch/1054/tropical_cyclone_dynamics/code/motif
source reproducibility/lib/common.sh

profile="${MOTIF_PROFILE:-extended8}"
poll_seconds="${MOTIF_WATCH_POLL_SECONDS:-300}"
completion_file="$MOTIF_REPRO_ROOT/manifests/tc_primed_${profile}_download_complete.txt"
logs_dir="$MOTIF_REPRO_ROOT/logs"
watch_log="$logs_dir/watch_download_then_submit_preprocess_${profile}_$(date -u +%Y%m%dT%H%M%SZ).log"

mkdir -p "$logs_dir"
exec > >(tee -a "$watch_log") 2>&1

echo "Watcher started UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Repository: $PWD"
echo "Profile: $profile"
echo "Completion marker: $completion_file"
echo "Poll seconds: $poll_seconds"
echo "Watcher log: $watch_log"

while [[ ! -f "$completion_file" ]]; do
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) waiting for download completion marker..."
    sleep "$poll_seconds"
done

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) download completion marker found."
echo "Submitting preprocessing PBS job."

qsub -v "MOTIF_PROFILE=$profile" reproducibility/hpc_scripts/download_and_preprocess_tc_primed.pbs

echo "Watcher finished UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
