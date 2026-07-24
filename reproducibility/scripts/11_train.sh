#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../lib/common.sh"

# Keep runtime metadata in the repro tree so offline GPU nodes do not need writable home dirs.
export UV_CACHE_DIR="${UV_CACHE_DIR:-$MOTIF_REPO_ROOT/.uv-cache}"
export WANDB_DIR="${WANDB_DIR:-$MOTIF_REPRO_ROOT/wandb}"
export WANDB_CACHE_DIR="${WANDB_CACHE_DIR:-$MOTIF_REPRO_ROOT/wandb/cache}"
export WANDB_CONFIG_DIR="${WANDB_CONFIG_DIR:-$MOTIF_REPRO_ROOT/wandb/config}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-$MOTIF_REPRO_ROOT/matplotlib}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-1}"

experiment="fm_pmw"
profile="$MOTIF_DEFAULT_PROFILE"
setup="local"
devices="$MOTIF_TRAIN_DEVICES"
num_nodes="$MOTIF_TRAIN_NUM_NODES"
batch_size="$MOTIF_TRAIN_BATCH_SIZE"
workers="$MOTIF_TRAIN_WORKERS"
max_epochs="$MOTIF_TRAIN_MAX_EPOCHS"
accumulate="$MOTIF_TRAIN_ACCUMULATE_GRAD_BATCHES"
seed="$MOTIF_TRAIN_SEED"
checkpoint_minutes="$MOTIF_CHECKPOINT_TIME_INTERVAL"
wandb_mode="$MOTIF_WANDB_MODE"
wandb_project="$MOTIF_WANDB_PROJECT"
wandb_entity="$MOTIF_WANDB_ENTITY"
run_name=""
resume_run_id=""
resume_mode="resume"
execute=0
extra_overrides=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --experiment) experiment="$2"; shift 2 ;;
        --profile) profile="$2"; shift 2 ;;
        --setup) setup="$2"; shift 2 ;;
        --devices) devices="$2"; shift 2 ;;
        --num-nodes) num_nodes="$2"; shift 2 ;;
        --batch-size) batch_size="$2"; shift 2 ;;
        --workers) workers="$2"; shift 2 ;;
        --max-epochs) max_epochs="$2"; shift 2 ;;
        --accumulate-grad-batches) accumulate="$2"; shift 2 ;;
        --seed) seed="$2"; shift 2 ;;
        --checkpoint-minutes) checkpoint_minutes="$2"; shift 2 ;;
        --wandb-mode) wandb_mode="$2"; shift 2 ;;
        --wandb-project) wandb_project="$2"; shift 2 ;;
        --wandb-entity) wandb_entity="$2"; shift 2 ;;
        --name) run_name="$2"; shift 2 ;;
        --resume-run-id) resume_run_id="$2"; shift 2 ;;
        --resume-mode) resume_mode="$2"; shift 2 ;;
        --execute) execute=1; shift ;;
        --)
            shift
            extra_overrides=("$@")
            break
            ;;
        -h|--help)
            echo "Usage: $0 [options] [-- extra Hydra overrides]"
            echo
            echo "Core: --experiment NAME --profile PROFILE --setup SETUP --execute"
            echo "Scale: --devices N --num-nodes N --batch-size N --workers N"
            echo "Schedule: --max-epochs N --accumulate-grad-batches N --seed N"
            echo "Logging: --wandb-mode online|offline|disabled --wandb-project NAME"
            echo "         --wandb-entity NAME --name RUN_NAME --checkpoint-minutes N"
            echo "Resume: --resume-run-id RUN_ID --resume-mode resume|fine_tune"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1 (put raw Hydra overrides after --)" >&2
            exit 2
            ;;
    esac
done

case "$experiment" in
    det_PI|det_pmw|fm_PI_gpm|fm_pmw|fm_PI) ;;
    *) echo "Unsupported active experiment: $experiment" >&2; exit 2 ;;
esac
case "$wandb_mode" in
    online|offline|disabled) ;;
    *) echo "wandb mode must be online, offline, or disabled" >&2; exit 2 ;;
esac
case "$resume_mode" in
    resume|fine_tune) ;;
    *) echo "resume mode must be resume or fine_tune" >&2; exit 2 ;;
esac

for value_name in devices num_nodes batch_size max_epochs accumulate checkpoint_minutes; do
    value="${!value_name}"
    if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo "$value_name must be a positive integer: $value" >&2
        exit 2
    fi
done
if ! [[ "$workers" =~ ^[0-9]+$ ]]; then
    echo "workers must be a non-negative integer: $workers" >&2
    exit 2
fi
if ! [[ "$seed" =~ ^[0-9]+$ ]]; then
    echo "seed must be a non-negative integer: $seed" >&2
    exit 2
fi

if [[ -z "$run_name" ]]; then
    run_name="$experiment"
fi

effective_batch=$((devices * num_nodes * batch_size * accumulate))
persistent_workers=true
if (( workers == 0 )); then
    persistent_workers=false
fi

wandb_config="$MOTIF_REPO_ROOT/configs/wandb/default.yaml"
if [[ ! -f "$wandb_config" ]]; then
    echo "Missing committed W&B compatibility config: $wandb_config" >&2
    exit 1
fi

command=(
    uv run --no-sync python scripts/train.py
    "experiment=$experiment"
    "model=motif_12b_d512"
    "setup=$setup"
    "${MOTIF_PATH_OVERRIDES[@]}"
    "dataloader.batch_size=$batch_size"
    "dataloader.num_workers=$workers"
    "dataloader.persistent_workers=$persistent_workers"
    "trainer.devices=$devices"
    "++trainer.num_nodes=$num_nodes"
    "trainer.max_epochs=$max_epochs"
    "++trainer.accumulate_grad_batches=$accumulate"
    "seed=$seed"
    "++checkpoint_time_interval=$checkpoint_minutes"
    "wandb.mode=$wandb_mode"
    "wandb.project=$wandb_project"
    "wandb.entity=$wandb_entity"
    "wandb.name=$run_name"
)

if [[ "$setup" == "local" ]]; then
    command+=("run_local=true")
    if (( devices == 1 && num_nodes == 1 )); then
        command+=("~trainer.strategy")
    fi
fi
if [[ -n "$resume_run_id" ]]; then
    command+=("+resume_run_id=$resume_run_id" "+resume_mode=$resume_mode")
fi
command+=("${extra_overrides[@]}")

echo "Experiment: $experiment"
echo "Profile verification gate: $profile"
echo "Setup: $setup"
echo "Data: $MOTIF_PREPROCESSED_ROOT"
echo "Devices x nodes: $devices x $num_nodes"
echo "Per-device batch: $batch_size"
echo "Gradient accumulation: $accumulate"
echo "Effective global batch: $effective_batch"
echo "Epochs: $max_epochs"
echo "W&B: mode=$wandb_mode project=$wandb_project entity=${wandb_entity:-<default>}"
echo "Checkpoint root: $MOTIF_REPRO_ROOT/checkpoints"
echo "Resume run: ${resume_run_id:-<none>}"
printf 'Command:'
printf ' %q' "${command[@]}"
printf '\n'

if (( execute == 0 )); then
    echo "Dry run only. Rerun with --execute after processed verification passes."
    exit 0
fi

"$MOTIF_REPO_ROOT/.venv/bin/python" "$script_dir/06_verify_preprocessed.py" \
    --profile "$profile"

if [[ "$wandb_mode" == "online" ]]; then
    if ! "$MOTIF_REPO_ROOT/.venv/bin/python" -c \
        'import wandb; raise SystemExit(0 if wandb.Api().api_key else 1)'; then
        echo "W&B online mode requested, but no API key is configured." >&2
        echo "Run: uv run wandb login --verify" >&2
        exit 1
    fi
fi

cd "$MOTIF_REPO_ROOT"
"${command[@]}"
