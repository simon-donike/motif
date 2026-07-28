import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import pandas as pd
from netCDF4 import Dataset


REPO_ROOT = Path(__file__).resolve().parents[1]
VERIFIER = REPO_ROOT / "reproducibility" / "scripts" / "17_verify_sar_preprocessed.py"


class SarVerifierTest(unittest.TestCase):
    def build_fixture(self, root: Path, *, include_ir: bool = True):
        processed = root / "preprocessed"
        prepared = processed / "prepared" / "sar_cband"
        constants = processed / "constants" / "sar_cband"
        prepared.mkdir(parents=True)
        constants.mkdir(parents=True)

        (prepared / "source_metadata.json").write_text(
            json.dumps(
                {
                    "source_name": "sar_cband",
                    "source_type": "sar",
                    "dim": 2,
                    "data_vars": ["wind_speed"],
                    "storm_metadata_vars": [],
                    "charac_vars": {},
                }
            )
        )
        sample_path = prepared / "sample.nc"
        with Dataset(sample_path, "w") as dataset:
            dataset.createDimension("lat", 2)
            dataset.createDimension("lon", 2)
            for name in (
                "wind_speed",
                "latitude",
                "longitude",
                "land_mask",
                "dist_to_center",
            ):
                variable = dataset.createVariable(name, "f4", ("lat", "lon"))
                variable[:] = np.ones((2, 2), dtype=np.float32)

        sar_row = {
            "source_name": "sar_cband",
            "source_type": "sar",
            "sid": "2020AL1",
            "time": "2020-08-01T12:00:00",
            "data_path": str(sample_path),
        }
        pd.DataFrame([sar_row]).to_csv(prepared / "samples_metadata.csv", index=False)
        (constants / "data_means.json").write_text('{"wind_speed": 20.0}\n')
        (constants / "data_stds.json").write_text('{"wind_speed": 5.0}\n')
        (constants / "charac_vars_min_max.json").write_text("{}\n")

        rows = [
            sar_row,
            {
                **sar_row,
                "source_name": "tc_primed_pmw_GMI_GPM",
                "source_type": "pmw",
                "time": "2020-08-01T13:00:00",
            },
        ]
        if include_ir:
            rows.append(
                {
                    **sar_row,
                    "source_name": "tc_primed_ir_tcirar",
                    "source_type": "infrared",
                    "time": "2020-08-01T11:00:00",
                }
            )
        for split in ("train", "val", "test"):
            pd.DataFrame(rows).to_csv(processed / f"{split}.csv", index=False)

    def run_verifier(self, root: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(VERIFIER), "--root", str(root)],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_accepts_complete_collocated_fixture(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.build_fixture(root)
            result = self.run_verifier(root)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("SAR PROCESSED VERIFICATION PASSED", result.stdout)

    def test_rejects_split_without_infrared_context(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.build_fixture(root, include_ir=False)
            result = self.run_verifier(root)
            self.assertEqual(result.returncode, 1)
            self.assertIn("no SAR target with both PMW and IR", result.stdout)


if __name__ == "__main__":
    unittest.main()
