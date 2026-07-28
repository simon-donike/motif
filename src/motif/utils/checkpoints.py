"""Implements small utility functions for loading checkpoints."""

from pathlib import Path
from typing import Mapping, Sequence

import torch
from torch import Tensor, nn


def load_experiment_cfg_from_checkpoint(checkpoints_dir, run_id, best_or_latest="latest"):
    """Loads a Lightning checkpoint and extracts from it the
    experiment configuration (which must have been saved as the "cfg"
    hyperparameter of the LightningModule).

    Args:
        checkpoints_dir (str): The directory where the checkpoints are stored.
        run_id (str): The ID of the run.
        best_or_latest (str): Whether to load the best or latest checkpoint.
    Returns:
        exp_cfg (dict): The experiment configuration.
        checkpoint_path (str): The path to the checkpoint.
    """
    checkpoints_dir = Path(checkpoints_dir) / run_id
    checkpoint_files = list(checkpoints_dir.glob("*.ckpt"))
    # The checkpoints are stored as:
    # - <run_id>-<epoch>-<step>.ckpt for the timed checkpoints
    # - <run_id>-<epoch>-best.ckpt for the best checkpoint
    if best_or_latest == "best" or checkpoint_files == []:
        best_checkpoint_files = [f for f in checkpoint_files if "best" in f.stem]
        if best_checkpoint_files == []:
            print("No best checkpoint found, loading latest instead.")
        else:
            checkpoint_files = best_checkpoint_files
    # Load the latest checkpoint out of the filtered list.
    checkpoint_files.sort(key=lambda x: x.stat().st_mtime)
    checkpoint_path = checkpoint_files[-1]
    print("Loading checkpoint:", checkpoint_path.stem, " from run ", run_id)
    # The checkpoint includes the whole configuration dict of the experiment, in
    # checkpoint["hyper_parameters"]['cfg']. We'll use this to reproduce
    # the exact configuration of the experiment.
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    exp_cfg = checkpoint["hyper_parameters"]["cfg"]
    return exp_cfg, checkpoint_path


def load_weights_intersection(former_dict, current_dict):
    """Loads the weights of the intersection of the keys in the
    former and current dictionaries.

    Args:
        former_dict (dict): The former dictionary.
        current_dict (dict): The current dictionary.
    Returns:
        new_dict (dict): The new dictionary with the weights of the intersection.
    """
    new_dict = {}
    for k, v in current_dict.items():
        if k in former_dict:
            new_dict[k] = former_dict[k]
        else:
            new_dict[k] = v
    return new_dict


def _matches_prefix(key: str, prefixes: Sequence[str]) -> bool:
    return any(key.startswith(prefix) for prefix in prefixes)


def load_validated_state_dict_transfer(
    module: nn.Module,
    state_dict: Mapping[str, Tensor],
    *,
    allowed_missing_prefixes: Sequence[str] = (),
    allowed_unexpected_prefixes: Sequence[str] = (),
) -> tuple[list[str], list[str]]:
    """Load fine-tuning weights while validating every state-dict incompatibility.

    ``strict=False`` is required when a fine-tuning task adds or removes source-type
    modules, but using it without checking the returned keys can silently skip unrelated
    weights. This helper validates missing and unexpected keys against explicit prefix
    allowlists and always rejects tensors whose shapes changed.
    """

    current_state = module.state_dict()
    missing_keys = sorted(set(current_state).difference(state_dict))
    unexpected_keys = sorted(set(state_dict).difference(current_state))
    shape_mismatches = sorted(
        (
            key,
            tuple(state_dict[key].shape),
            tuple(current_state[key].shape),
        )
        for key in set(current_state).intersection(state_dict)
        if state_dict[key].shape != current_state[key].shape
    )

    invalid_missing = [
        key for key in missing_keys if not _matches_prefix(key, allowed_missing_prefixes)
    ]
    invalid_unexpected = [
        key for key in unexpected_keys if not _matches_prefix(key, allowed_unexpected_prefixes)
    ]
    if invalid_missing or invalid_unexpected or shape_mismatches:
        details = []
        if invalid_missing:
            details.append(f"undeclared missing keys: {invalid_missing}")
        if invalid_unexpected:
            details.append(f"undeclared unexpected keys: {invalid_unexpected}")
        if shape_mismatches:
            details.append(f"shape mismatches (checkpoint, current): {shape_mismatches}")
        raise RuntimeError("Invalid checkpoint transfer: " + "; ".join(details))

    incompatible = module.load_state_dict(state_dict, strict=False)
    if sorted(incompatible.missing_keys) != missing_keys:
        raise RuntimeError("Checkpoint transfer missing-key validation changed during loading.")
    if sorted(incompatible.unexpected_keys) != unexpected_keys:
        raise RuntimeError("Checkpoint transfer unexpected-key validation changed during loading.")
    return missing_keys, unexpected_keys
