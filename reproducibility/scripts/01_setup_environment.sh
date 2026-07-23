#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

cd "$MOTIF_REPO_ROOT"
uv sync --frozen
uv lock --check

mkdir -p "$MOTIF_REPRO_ROOT/provenance"
snapshot="$MOTIF_REPRO_ROOT/provenance/environment-$(date -u +%Y%m%dT%H%M%SZ).txt"
bash reproducibility/collect_provenance.sh > "$snapshot"

echo "Environment ready: $MOTIF_REPO_ROOT/.venv"
echo "Provenance snapshot: $snapshot"

