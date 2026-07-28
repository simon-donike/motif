#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 MODELS_SPEC EVAL_NAME val|test EVAL_CLASSES [extra Hydra overrides...]" >&2
    echo "Example MODELS_SPEC: {FM: [run123, gpm_PI_dt6]}" >&2
    echo "Example EVAL_CLASSES: [quantitative,visual]" >&2
    exit 2
fi

models_spec="$1"
eval_name="$2"
split="$3"
eval_classes="$4"
shift 4

if [[ "$split" != "val" && "$split" != "test" ]]; then
    echo "Split must be val or test." >&2
    exit 2
fi

cd "$MOTIF_REPO_ROOT"
uv run --no-sync python scripts/eval.py \
    "models=$models_spec" \
    "eval_name=$eval_name" \
    "split=$split" \
    "eval_class=$eval_classes" \
    "setup=local" \
    "${MOTIF_PATH_OVERRIDES[@]}" \
    "num_workers=4" \
    "run_local=true" \
    "$@"
