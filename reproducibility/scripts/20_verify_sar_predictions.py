#!/usr/bin/env python3
"""Verify generated SAR wind-speed NetCDF predictions before evaluation."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import xarray as xr


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_id")
    parser.add_argument("pred_name")
    parser.add_argument("split", choices=("val", "test"))
    parser.add_argument("--predictions-root", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_root = args.predictions_root / args.run_id / args.pred_name / args.split
    prediction_files = sorted((run_root / "predictions" / "sar_cband").glob("*/*.nc"))
    errors = []
    if not prediction_files:
        errors.append(f"no SAR prediction files under {run_root}")

    required_dims = {"realization", "integration_step", "H", "W"}
    required_coords = {"lat", "lon", "dt"}
    for path in prediction_files:
        try:
            with xr.open_dataset(path) as dataset:
                if "wind_speed" not in dataset:
                    errors.append(f"{path}: missing wind_speed")
                    continue
                wind_speed = dataset["wind_speed"]
                missing_dims = required_dims.difference(wind_speed.dims)
                if missing_dims:
                    errors.append(f"{path}: missing dimensions {sorted(missing_dims)}")
                missing_coords = required_coords.difference(dataset.coords)
                if missing_coords:
                    errors.append(f"{path}: missing coordinates {sorted(missing_coords)}")
                final_values = wind_speed.isel(integration_step=-1).values
                if final_values.size == 0 or not np.isfinite(final_values).all():
                    errors.append(f"{path}: final wind_speed field is not finite")
        except Exception as exc:
            errors.append(f"{path}: cannot read prediction: {exc!r}")

    target_files = sorted((run_root / "targets" / "sar_cband").glob("*/*.nc"))
    if len(target_files) != len(prediction_files):
        errors.append(
            f"target/prediction count mismatch: {len(target_files)} != {len(prediction_files)}"
        )

    print(f"Prediction root: {run_root}")
    print(f"SAR prediction files: {len(prediction_files)}")
    print(f"SAR target files: {len(target_files)}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        print("SAR PREDICTION VERIFICATION FAILED")
        return 1
    print("SAR PREDICTION VERIFICATION PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
