#!/usr/bin/env bash

set -o pipefail

cd /lustre/scratch/1054/tropical_cyclone_dynamics/code/motif || exit 1

source reproducibility/lib/common.sh
mkdir -p "$MOTIF_REPRO_ROOT/logs"

tmux_log="$MOTIF_REPRO_ROOT/logs/tmux_download_tc_primed_extended8_$(date -u +%Y%m%dT%H%M%SZ).log"
echo "Writing tmux download transcript to $tmux_log"

bash reproducibility/scripts/03_download_tc_primed_subset.sh \
    --profile extended8 \
    --workers "${MOTIF_DOWNLOAD_WORKERS:-8}" \
    --execute 2>&1 | tee -a "$tmux_log"

status="${PIPESTATUS[0]}"
echo "Download command exited with status $status" | tee -a "$tmux_log"

if [[ "$status" -ne 0 ]]; then
    echo "Leaving shell open for inspection. Press Ctrl-D to close this tmux pane." | tee -a "$tmux_log"
    exec bash
fi

exit "$status"
