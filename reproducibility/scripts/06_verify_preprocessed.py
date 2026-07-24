#!/usr/bin/env python3
"""Verify MOTIF PMW/infrared preprocessing products and split invariants."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
from netCDF4 import Dataset

from _settings import setting

PROFILES = {
    "local100": {1993, 2003, 2009, 2014, 2015, 2016},
    "core6": {1993, 2003, 2009, 2014, 2015, 2016},
    "extended8": {1993, 2003, 2009, 2014, 2015, 2016, 2021, 2022},
    "full": set(range(1987, 2025)),
}
VAL_SEASONS = {2005, 2007, 2014, 2021, 2023}
TEST_SEASONS = {2006, 2008, 2015, 2022, 2024}
REQUIRED_SOURCES = {
    "tc_primed_pmw_AMSR2_GCOMW1",
    "tc_primed_pmw_GMI_GPM",
    "tc_primed_pmw_TMI_TRMM",
    "tc_primed_pmw_SSMI_F11",
    "tc_primed_pmw_SSMI_F13",
    "tc_primed_pmw_SSMI_F14",
    "tc_primed_pmw_SSMI_F15",
    "tc_primed_pmw_SSMIS_F16",
    "tc_primed_pmw_SSMIS_F17",
    "tc_primed_pmw_SSMIS_F18",
    "tc_primed_pmw_SSMIS_F19",
    "tc_primed_ir_tcirar",
    "tc_primed_ir_hursat",
}


def default_root() -> Path:
    return Path(setting("MOTIF_REPRO_ROOT", "/data1/datasets/motif-repro"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--profile",
        choices=sorted(PROFILES),
        default=setting("MOTIF_DEFAULT_PROFILE", "local100"),
    )
    parser.add_argument("--root", type=Path, default=default_root())
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def finite_mapping(path: Path, require_positive: bool = False) -> list[str]:
    errors: list[str] = []
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        return [f"cannot read {path}: {exc!r}"]
    if not data:
        return [f"empty mapping: {path}"]
    for key, value in data.items():
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            errors.append(f"non-finite {path}:{key}={value!r}")
        elif require_positive and value <= 0:
            errors.append(f"non-positive {path}:{key}={value!r}")
    return errors


def json_default(value: object) -> object:
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.floating):
        return float(value)
    if isinstance(value, np.ndarray):
        return value.tolist()
    raise TypeError(f"Object of type {value.__class__.__name__} is not JSON serializable")


def main() -> int:
    args = parse_args()
    processed = args.root / "preprocessed"
    prepared = processed / "prepared"
    constants = processed / "constants"
    report_path = args.report or (
        args.root / "manifests" / f"tc_primed_{args.profile}_processed_verification.json"
    )
    errors: list[str] = []

    if not prepared.is_dir():
        raise FileNotFoundError(f"Prepared directory not found: {prepared}")

    available_sources = {path.name for path in prepared.iterdir() if path.is_dir()}
    missing_sources = sorted(REQUIRED_SOURCES.difference(available_sources))
    if missing_sources:
        errors.append(f"missing required sources: {missing_sources}")

    source_counts: dict[str, int] = {}
    netcdf_errors: list[str] = []
    for source in sorted(REQUIRED_SOURCES.intersection(available_sources)):
        source_dir = prepared / source
        metadata_json = source_dir / "source_metadata.json"
        samples_csv = source_dir / "samples_metadata.csv"
        if not metadata_json.is_file():
            errors.append(f"missing {metadata_json}")
        else:
            try:
                metadata = json.loads(metadata_json.read_text())
                if metadata.get("source_name") != source:
                    errors.append(f"source_name mismatch in {metadata_json}")
            except Exception as exc:
                errors.append(f"cannot read {metadata_json}: {exc!r}")
        if not samples_csv.is_file():
            errors.append(f"missing {samples_csv}")
            continue
        source_frame = pd.read_csv(samples_csv)
        source_counts[source] = len(source_frame)
        if source_frame.empty:
            errors.append(f"empty source metadata: {samples_csv}")
            continue
        sample_path = Path(source_frame.iloc[0]["data_path"])
        if not sample_path.is_file():
            errors.append(f"missing sample file: {sample_path}")
        else:
            try:
                with Dataset(sample_path, "r") as dataset:
                    _ = list(dataset.variables)
            except Exception as exc:
                netcdf_errors.append(f"cannot open {sample_path}: {exc!r}")

        source_constants = constants / source
        errors.extend(finite_mapping(source_constants / "data_means.json"))
        errors.extend(finite_mapping(source_constants / "data_stds.json", require_positive=True))
        charac_path = source_constants / "charac_vars_min_max.json"
        if not charac_path.is_file():
            errors.append(f"missing {charac_path}")

    expected_years = PROFILES[args.profile]
    expected_by_split = {
        "train": expected_years.difference(VAL_SEASONS | TEST_SEASONS),
        "val": expected_years.intersection(VAL_SEASONS),
        "test": expected_years.intersection(TEST_SEASONS),
    }
    split_counts: dict[str, int] = {}
    split_years: dict[str, list[int]] = {}
    missing_data_paths: list[str] = []

    for split, expected_split_years in expected_by_split.items():
        split_path = processed / f"{split}.csv"
        if not split_path.is_file():
            errors.append(f"missing split file: {split_path}")
            continue
        frame = pd.read_csv(split_path)
        split_counts[split] = len(frame)
        if frame.empty:
            errors.append(f"empty split: {split_path}")
            split_years[split] = []
            continue
        seasons = set(frame["sid"].astype(str).str[:4].astype(int).unique())
        split_years[split] = sorted(seasons)
        if seasons != expected_split_years:
            errors.append(
                f"{split} seasons mismatch: expected {sorted(expected_split_years)}, "
                f"found {sorted(seasons)}"
            )
        for data_path in frame["data_path"]:
            path = Path(data_path)
            if not path.is_file():
                missing_data_paths.append(str(path))
                if len(missing_data_paths) >= 100:
                    break

    errors.extend(netcdf_errors)
    if missing_data_paths:
        errors.append(f"missing referenced data paths (first 100): {missing_data_paths}")

    report = {
        "profile": args.profile,
        "root": str(processed),
        "required_sources": sorted(REQUIRED_SOURCES),
        "available_sources": sorted(available_sources),
        "missing_sources": missing_sources,
        "source_counts": source_counts,
        "split_counts": split_counts,
        "split_years": split_years,
        "errors": errors,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, default=json_default) + "\n")

    print(
        json.dumps(
            {key: value for key, value in report.items() if key != "errors"},
            indent=2,
            default=json_default,
        )
    )
    print(f"Error count: {len(errors)}")
    print(f"Full report: {report_path}")
    if errors:
        for error in errors[:20]:
            print(f"ERROR: {error}")
        print("PROCESSED VERIFICATION FAILED")
        return 1
    print("PROCESSED VERIFICATION PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
