#!/usr/bin/env python3
"""Verify SAR preprocessing and PMW/IR collocations for wind-speed fine-tuning."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
from netCDF4 import Dataset

from _settings import setting

SAR_SOURCE = "sar_cband"
REQUIRED_NETCDF_VARIABLES = {
    "wind_speed",
    "latitude",
    "longitude",
    "land_mask",
    "dist_to_center",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(setting("MOTIF_REPRO_ROOT", "/data1/datasets/motif-repro")),
    )
    parser.add_argument("--dt-hours", type=float, default=3.0)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def load_finite_mapping(
    path: Path,
    errors: list[str],
    *,
    require_positive: bool = False,
) -> dict:
    try:
        values = json.loads(path.read_text())
    except Exception as exc:
        errors.append(f"cannot read {path}: {exc!r}")
        return {}
    if not values:
        errors.append(f"empty mapping: {path}")
    for key, value in values.items():
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            errors.append(f"non-finite {path}:{key}={value!r}")
        elif require_positive and value <= 0:
            errors.append(f"non-positive {path}:{key}={value!r}")
    return values


def collocated_sar_count(frame: pd.DataFrame, dt_hours: float) -> int:
    frame = frame.copy()
    frame["time"] = pd.to_datetime(frame["time"])
    sar = frame[frame["source_name"] == SAR_SOURCE]
    pmw = frame[frame["source_name"].str.startswith("tc_primed_pmw_")]
    infrared = frame[frame["source_name"].str.startswith("tc_primed_ir_")]
    pmw_times = {
        sid: group["time"].to_numpy(dtype="datetime64[ns]") for sid, group in pmw.groupby("sid")
    }
    infrared_times = {
        sid: group["time"].to_numpy(dtype="datetime64[ns]")
        for sid, group in infrared.groupby("sid")
    }
    delta = pd.Timedelta(hours=dt_hours).to_timedelta64()

    def has_nearby(times_by_sid: dict, sid: str, target_time: pd.Timestamp) -> bool:
        times = times_by_sid.get(sid)
        if times is None:
            return False
        target = target_time.to_datetime64()
        return bool(np.any(np.abs(times - target) <= delta))

    return sum(
        has_nearby(pmw_times, target.sid, target.time)
        and has_nearby(infrared_times, target.sid, target.time)
        for target in sar.itertuples()
    )


def main() -> int:
    args = parse_args()
    processed = args.root / "preprocessed"
    prepared = processed / "prepared" / SAR_SOURCE
    constants = processed / "constants" / SAR_SOURCE
    report_path = args.report or args.root / "manifests" / "sar_processed_verification.json"
    errors: list[str] = []

    metadata_path = prepared / "source_metadata.json"
    samples_path = prepared / "samples_metadata.csv"
    try:
        metadata = json.loads(metadata_path.read_text())
        expected_metadata = {
            "source_name": SAR_SOURCE,
            "source_type": "sar",
            "dim": 2,
            "data_vars": ["wind_speed"],
        }
        for key, expected in expected_metadata.items():
            if metadata.get(key) != expected:
                errors.append(
                    f"{metadata_path}:{key} expected {expected!r}, found {metadata.get(key)!r}"
                )
    except Exception as exc:
        errors.append(f"cannot read {metadata_path}: {exc!r}")

    try:
        samples = pd.read_csv(samples_path)
    except Exception as exc:
        errors.append(f"cannot read {samples_path}: {exc!r}")
        samples = pd.DataFrame()
    if samples.empty:
        errors.append(f"empty SAR samples metadata: {samples_path}")
    else:
        missing_paths = [
            str(path)
            for path in (Path(value) for value in samples["data_path"])
            if not path.is_file()
        ]
        if missing_paths:
            errors.append(f"missing SAR files (first 20): {missing_paths[:20]}")
        sample_path = Path(samples.iloc[0]["data_path"])
        if sample_path.is_file():
            try:
                with Dataset(sample_path) as dataset:
                    missing_vars = REQUIRED_NETCDF_VARIABLES.difference(dataset.variables)
                    if missing_vars:
                        errors.append(
                            f"{sample_path} missing NetCDF variables: {sorted(missing_vars)}"
                        )
                    wind_speed = np.ma.asarray(dataset["wind_speed"][:]).compressed()
                    if wind_speed.size == 0 or not np.isfinite(wind_speed).all():
                        errors.append(f"{sample_path} has no finite wind_speed data")
            except Exception as exc:
                errors.append(f"cannot validate {sample_path}: {exc!r}")

    means = load_finite_mapping(constants / "data_means.json", errors)
    stds = load_finite_mapping(
        constants / "data_stds.json",
        errors,
        require_positive=True,
    )
    if "wind_speed" not in means or "wind_speed" not in stds:
        errors.append("SAR normalization constants do not contain wind_speed")
    charac_path = constants / "charac_vars_min_max.json"
    try:
        if json.loads(charac_path.read_text()) != {}:
            errors.append(f"{charac_path} must be empty because SAR has no characteristics")
    except Exception as exc:
        errors.append(f"cannot read {charac_path}: {exc!r}")

    split_counts: dict[str, int] = {}
    collocated_counts: dict[str, int] = {}
    for split in ("train", "val", "test"):
        split_path = processed / f"{split}.csv"
        try:
            frame = pd.read_csv(split_path)
        except Exception as exc:
            errors.append(f"cannot read {split_path}: {exc!r}")
            continue
        split_counts[split] = int((frame["source_name"] == SAR_SOURCE).sum())
        collocated_counts[split] = collocated_sar_count(frame, args.dt_hours)
        if split_counts[split] == 0:
            errors.append(f"{split} has no {SAR_SOURCE} targets")
        elif collocated_counts[split] == 0:
            errors.append(
                f"{split} has no SAR target with both PMW and IR within ±{args.dt_hours:g}h"
            )

    report = {
        "root": str(processed),
        "dt_hours": args.dt_hours,
        "sar_sample_count": len(samples),
        "split_sar_counts": split_counts,
        "split_collocated_counts": collocated_counts,
        "errors": errors,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "errors"}, indent=2))
    print(f"Error count: {len(errors)}")
    print(f"Full report: {report_path}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        print("SAR PROCESSED VERIFICATION FAILED")
        return 1
    print("SAR PROCESSED VERIFICATION PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
