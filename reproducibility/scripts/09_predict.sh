#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 RUN_ID INFERENCE_CFG val|test [extra Hydra overrides...]" >&2
    exit 2
fi

run_id="$1"
inference_cfg="$2"
split="$3"
shift 3

if [[ "$split" != "val" && "$split" != "test" ]]; then
    echo "Split must be val or test." >&2
    exit 2
fi

cd "$MOTIF_REPO_ROOT"
uv run python scripts/make_predictions.py \
    "run_id=$run_id" \
    "inference_cfg=$inference_cfg" \
    "split=$split" \
    "setup=local" \
    "${MOTIF_PATH_OVERRIDES[@]}" \
    "+dataloader.batch_size=1" \
    "+dataloader.num_workers=0" \
    "+dataloader.persistent_workers=false" \
    "trainer.devices=1" \
    "run_local=true" \
    "$@"

