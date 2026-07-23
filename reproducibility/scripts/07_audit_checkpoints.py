#!/usr/bin/env python3
"""Audit local Lightning checkpoints using MOTIF's run-ID directory convention."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import torch

from _settings import setting


def default_root() -> Path:
    base = Path(setting("MOTIF_REPRO_ROOT", "/data1/datasets/motif-repro"))
    return base / "checkpoints"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_ids", nargs="+")
    parser.add_argument("--checkpoints-root", type=Path, default=default_root())
    parser.add_argument("--hash", action="store_true", dest="compute_hash")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def summarize(path: Path, compute_hash: bool) -> dict[str, object]:
    checkpoint = torch.load(path, map_location="cpu", weights_only=False)
    state_dict = checkpoint.get("state_dict", {})
    cfg = checkpoint.get("hyper_parameters", {}).get("cfg")
    summary: dict[str, object] = {
        "path": str(path),
        "bytes": path.stat().st_size,
        "modified_ns": path.stat().st_mtime_ns,
        "epoch": checkpoint.get("epoch"),
        "global_step": checkpoint.get("global_step"),
        "state_dict_keys": len(state_dict),
        "has_embedded_cfg": cfg is not None,
    }
    if isinstance(cfg, dict):
        summary["seed"] = cfg.get("seed")
        summary["wandb_name"] = cfg.get("wandb", {}).get("name")
        summary["lightning_target"] = cfg.get("lightning_module", {}).get("_target_")
        summary["model_dim"] = cfg.get("model", {}).get("dim")
    if compute_hash:
        summary["sha256"] = sha256(path)
    return summary


def main() -> int:
    args = parse_args()
    results: dict[str, object] = {}
    failed = False
    for run_id in args.run_ids:
        run_dir = args.checkpoints_root / run_id
        files = sorted(run_dir.glob("*.ckpt"), key=lambda path: path.stat().st_mtime_ns)
        if not files:
            results[run_id] = {"error": f"no .ckpt files in {run_dir}"}
            failed = True
            continue
        run_results = []
        for path in files:
            try:
                run_results.append(summarize(path, args.compute_hash))
            except Exception as exc:
                run_results.append({"path": str(path), "error": repr(exc)})
                failed = True
        best = [item for item in run_results if "best" in Path(str(item["path"])).stem]
        results[run_id] = {
            "directory": str(run_dir),
            "checkpoints": run_results,
            "repository_best_selection": best[-1] if best else run_results[-1],
        }

    output = json.dumps(results, indent=2) + "\n"
    print(output, end="")
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
