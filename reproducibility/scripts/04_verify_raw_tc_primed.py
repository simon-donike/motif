#!/usr/bin/env python3
"""Verify a downloaded TC-PRIMED subset against its saved S3 object manifest."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from netCDF4 import Dataset

from _settings import setting

PROFILES = {
    "local100": [1993, 2003, 2009, 2014, 2015, 2016],
    "core6": [1993, 2003, 2009, 2014, 2015, 2016],
    "extended8": [1993, 2003, 2009, 2014, 2015, 2016, 2021, 2022],
    "full": list(range(1987, 2025)),
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
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--netcdf-samples", type=int, default=20)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def select_evenly(paths: list[Path], count: int) -> list[Path]:
    if count <= 0 or not paths:
        return []
    if len(paths) <= count:
        return paths
    return [paths[index * (len(paths) - 1) // (count - 1)] for index in range(count)]


def main() -> int:
    args = parse_args()
    tc_root = args.root / "raw" / "tc_primed"
    manifest = args.manifest or (args.root / "manifests" / f"tc_primed_{args.profile}_objects.csv")
    report_path = args.report or (
        args.root / "manifests" / f"tc_primed_{args.profile}_raw_verification.json"
    )

    if not manifest.is_file():
        raise FileNotFoundError(
            f"Object manifest not found: {manifest}. Run 03_download_tc_primed_subset.sh first."
        )

    expected: dict[Path, int] = {}
    with manifest.open(newline="") as stream:
        for row in csv.DictReader(stream):
            year = int(row["year"])
            prefix = f"v01r01/final/{year}/"
            key = row["key"]
            if not key.startswith(prefix):
                raise ValueError(f"Manifest key is outside expected prefix: {key}")
            expected[tc_root / str(year) / key.removeprefix(prefix)] = int(row["bytes"])

    missing: list[str] = []
    size_mismatches: list[dict[str, int | str]] = []
    present_paths: list[Path] = []
    observed_bytes = 0
    for path, expected_size in expected.items():
        if not path.is_file():
            missing.append(str(path))
            continue
        actual_size = path.stat().st_size
        observed_bytes += actual_size
        present_paths.append(path)
        if actual_size != expected_size:
            size_mismatches.append(
                {"path": str(path), "expected": expected_size, "actual": actual_size}
            )

    years = {str(year) for year in PROFILES[args.profile]}
    actual_files: set[Path] = set()
    for year in years:
        year_dir = tc_root / year
        if year_dir.is_dir():
            actual_files.update(path for path in year_dir.rglob("*") if path.is_file())
    unexpected = sorted(str(path) for path in actual_files.difference(expected))

    netcdf_errors: list[dict[str, str]] = []
    netcdf_paths = sorted(path for path in present_paths if path.suffix == ".nc")
    for path in select_evenly(netcdf_paths, args.netcdf_samples):
        try:
            with Dataset(path, "r") as dataset:
                _ = list(dataset.groups), list(dataset.variables)
        except Exception as exc:
            netcdf_errors.append({"path": str(path), "error": repr(exc)})

    report = {
        "profile": args.profile,
        "root": str(tc_root),
        "manifest": str(manifest),
        "expected_files": len(expected),
        "expected_bytes": sum(expected.values()),
        "present_files": len(present_paths),
        "observed_bytes": observed_bytes,
        "missing_count": len(missing),
        "size_mismatch_count": len(size_mismatches),
        "unexpected_count": len(unexpected),
        "netcdf_checked": len(select_evenly(netcdf_paths, args.netcdf_samples)),
        "netcdf_error_count": len(netcdf_errors),
        "missing": missing[:100],
        "size_mismatches": size_mismatches[:100],
        "unexpected": unexpected[:100],
        "netcdf_errors": netcdf_errors,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")

    print(
        json.dumps(
            {key: value for key, value in report.items() if not isinstance(value, list)}, indent=2
        )
    )
    print(f"Full report: {report_path}")

    failed = missing or size_mismatches or unexpected or netcdf_errors
    if failed:
        print("RAW VERIFICATION FAILED")
        return 1
    print("RAW VERIFICATION PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
