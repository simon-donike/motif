#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

run_id="${1:-3hyfu3lz-1}"
source_ckpt="${2:-$MOTIF_REPO_ROOT/reproducibility/pretrained_checkpoints/3hyfu3lz-1-epoch=34-step=91889.ckpt}"

if [[ ! -f "$source_ckpt" ]]; then
    echo "Checkpoint not found: $source_ckpt" >&2
    exit 1
fi

dest_dir="$MOTIF_ANON_OUTPUT_ROOT/checkpoints/$run_id"
mkdir -p "$dest_dir"

dest_ckpt="$dest_dir/$(basename "$source_ckpt")"
if [[ -e "$dest_ckpt" || -L "$dest_ckpt" ]]; then
    echo "Checkpoint already prepared: $dest_ckpt"
else
    ln -s "$(realpath "$source_ckpt")" "$dest_ckpt"
    echo "Prepared checkpoint symlink: $dest_ckpt"
fi

echo "Run ID: $run_id"
echo "Checkpoint root: $MOTIF_ANON_OUTPUT_ROOT/checkpoints"
