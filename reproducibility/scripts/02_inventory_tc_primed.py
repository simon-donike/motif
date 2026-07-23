#!/usr/bin/env python3
"""Inventory selected TC-PRIMED years without downloading research data."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import boto3
from botocore import UNSIGNED
from botocore.client import Config

from _settings import setting

BUCKET = "noaa-nesdis-tcprimed-pds"
BASE_PREFIX = "v01r01/final"
PROFILE_SCOPES = {
    "local100": [
        (1993, "AL"),
        (1993, "CP"),
        (1993, "IO"),
        (2003, "AL"),
        (2003, "CP"),
        (2003, "EP"),
        (2003, "IO"),
        (2009, "AL"),
        (2009, "CP"),
        (2009, "EP"),
        (2009, "IO"),
        (2014, "AL"),
        (2014, "CP"),
        (2014, "IO"),
        (2015, "AL"),
        (2015, "CP"),
        (2015, "IO"),
        (2016, "AL"),
        (2016, "CP"),
        (2016, "IO"),
    ],
    "core6": [(year, None) for year in [1993, 2003, 2009, 2014, 2015, 2016]],
    "extended8": [(year, None) for year in [1993, 2003, 2009, 2014, 2015, 2016, 2021, 2022]],
    "full": [(year, None) for year in range(1987, 2025)],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--profile",
        choices=sorted(PROFILE_SCOPES),
        default=setting("MOTIF_DEFAULT_PROFILE", "local100"),
    )
    group.add_argument("--years", nargs="+", type=int)
    parser.add_argument("--output", type=Path, help="Write the per-year summary CSV.")
    parser.add_argument(
        "--objects-output",
        type=Path,
        help="Write the complete object-level manifest CSV.",
    )
    parser.add_argument("--expect-bytes", type=int)
    parser.add_argument("--max-bytes", type=int, default=600_000_000_000)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    scopes = (
        [(year, None) for year in sorted(set(args.years))]
        if args.years is not None
        else PROFILE_SCOPES[args.profile]
    )

    s3 = boto3.client(
        "s3",
        config=Config(signature_version=UNSIGNED, max_pool_connections=16),
    )
    paginator = s3.get_paginator("list_objects_v2")

    summary: list[tuple[int, str, int, int]] = []
    object_rows: list[tuple[int, str, str, int, str, str]] = []

    for year, basin in scopes:
        count = 0
        total_bytes = 0
        prefix = f"{BASE_PREFIX}/{year}/"
        if basin is not None:
            prefix += f"{basin}/"
        for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key.endswith("/"):
                    continue
                size = int(obj["Size"])
                count += 1
                total_bytes += size
                if args.objects_output is not None:
                    object_rows.append(
                        (
                            year,
                            basin or "ALL",
                            key,
                            size,
                            str(obj.get("ETag", "")).strip('"'),
                            obj["LastModified"].isoformat(),
                        )
                    )
        if count == 0:
            raise RuntimeError(f"No objects found for {year} under s3://{BUCKET}/{prefix}")
        summary.append((year, basin or "ALL", count, total_bytes))

    total_files = sum(row[2] for row in summary)
    total_bytes = sum(row[3] for row in summary)

    print("year,basin,files,bytes,GB")
    for year, basin, count, size in summary:
        print(f"{year},{basin},{count},{size},{size / 1e9:.3f}")
    print(f"TOTAL,,{total_files},{total_bytes},{total_bytes / 1e9:.3f}")

    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["year", "basin", "files", "bytes"])
            writer.writerows(summary)
            writer.writerow(["TOTAL", "", total_files, total_bytes])

    if args.objects_output is not None:
        args.objects_output.parent.mkdir(parents=True, exist_ok=True)
        with args.objects_output.open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["year", "basin", "key", "bytes", "etag", "last_modified"])
            writer.writerows(object_rows)

    if total_bytes > args.max_bytes:
        print(f"ERROR: {total_bytes} exceeds max-bytes={args.max_bytes}")
        return 1
    if args.expect_bytes is not None and total_bytes != args.expect_bytes:
        print(f"ERROR: expected {args.expect_bytes} bytes, observed {total_bytes}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
