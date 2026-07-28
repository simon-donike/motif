#!/usr/bin/env python3
"""Validate the authors' fm_PI checkpoint against the SAR fine-tuning architecture."""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
from hydra import compose, initialize_config_dir
from hydra.utils import instantiate
from omegaconf import OmegaConf

from motif.data.source import Source
from motif.data.utils import read_variables_dict
from motif.utils.checkpoints import load_validated_state_dict_transfer

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CHECKPOINT = (
    REPO_ROOT / "reproducibility" / "pretrained_checkpoints" / "3hyfu3lz-1-epoch=34-step=91889.ckpt"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=DEFAULT_CHECKPOINT)
    return parser.parse_args()


def build_sources(source_cfg: dict) -> list[Source]:
    """Build shape-compatible source metadata without requiring processed data."""

    variables = read_variables_dict(source_cfg)
    sources = []
    for source_name, (data_vars, input_only, output_only) in variables.items():
        if source_name.startswith("tc_primed_pmw_"):
            source_type = "pmw"
            # The checkpoint's PMW embedding has three characteristics for each
            # of its four channels (12 values plus the availability flag).
            charac_vars = {
                f"checkpoint_charac_{index}": {variable: 0.0 for variable in data_vars}
                for index in range(3)
            }
        elif source_name.startswith("tc_primed_ir_"):
            source_type = "infrared"
            charac_vars = {"checkpoint_charac": {variable: 0.0 for variable in data_vars}}
        elif source_name == "sar_cband":
            source_type = "sar"
            charac_vars = {}
        else:
            raise ValueError(f"Unexpected source in SAR fine-tuning config: {source_name}")

        sources.append(
            Source(
                source_name=source_name,
                source_type=source_type,
                dim=2,
                data_vars=data_vars,
                charac_vars=charac_vars,
                input_only_vars=input_only,
                output_only_vars=output_only,
            )
        )
    return sources


def main() -> int:
    args = parse_args()
    if not args.checkpoint.is_file():
        raise FileNotFoundError(f"Checkpoint not found: {args.checkpoint}")

    with initialize_config_dir(
        config_dir=str((REPO_ROOT / "configs").resolve()),
        version_base=None,
    ):
        hydra_cfg = compose(
            config_name="train",
            overrides=[
                "experiment=fm_PI_sar",
                "model=motif_12b_d512",
                "setup=local",
                "paths=example",
                "trainer.devices=1",
                "dataloader.batch_size=1",
                "wandb.name=sar_transfer_validation",
                "run_local=true",
            ],
        )
    cfg = OmegaConf.to_object(hydra_cfg)
    sources = build_sources(cfg["sources"])
    module = instantiate(
        cfg["lightning_module"],
        sources,
        cfg,
        validation_dir=None,
    )

    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    checkpoint_state = checkpoint["state_dict"]
    transfer_cfg = cfg["checkpoint_transfer"]
    missing, unexpected = load_validated_state_dict_transfer(
        module,
        checkpoint_state,
        allowed_missing_prefixes=transfer_cfg["allowed_missing_prefixes"],
        allowed_unexpected_prefixes=transfer_cfg["allowed_unexpected_prefixes"],
    )

    transferred = sorted(set(module.state_dict()).intersection(checkpoint_state))
    unequal = [
        key
        for key in transferred
        if not torch.equal(module.state_dict()[key], checkpoint_state[key])
    ]
    if unequal:
        raise RuntimeError(f"Transferred tensors differ from checkpoint: {unequal}")

    print(f"Checkpoint: {args.checkpoint}")
    print(f"Transferred tensors: {len(transferred)}")
    print(f"New SAR tensors: {len(missing)}")
    print(f"Unused PMW-head tensors: {len(unexpected)}")
    print("SAR CHECKPOINT TRANSFER PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
