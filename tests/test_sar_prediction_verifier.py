import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import xarray as xr


REPO_ROOT = Path(__file__).resolve().parents[1]
VERIFIER = REPO_ROOT / "reproducibility" / "scripts" / "20_verify_sar_predictions.py"


class SarPredictionVerifierTest(unittest.TestCase):
    def test_accepts_finite_generative_wind_speed_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            predictions_root = Path(temp_dir)
            run_root = predictions_root / "run" / "pred" / "test"
            prediction_dir = run_root / "predictions" / "sar_cband" / "0"
            target_dir = run_root / "targets" / "sar_cband" / "0"
            prediction_dir.mkdir(parents=True)
            target_dir.mkdir(parents=True)

            coords = {
                "realization": [0, 1],
                "integration_step": [0.0, 1.0],
                "lat": (("H", "W"), np.ones((2, 3))),
                "lon": (("H", "W"), np.ones((2, 3))),
                "dt": np.timedelta64(0, "h"),
            }
            prediction = xr.Dataset(
                {
                    "wind_speed": (
                        ("realization", "integration_step", "H", "W"),
                        np.full((2, 2, 2, 3), 25.0),
                    )
                },
                coords=coords,
            )
            prediction.to_netcdf(prediction_dir / "0.nc")
            xr.Dataset({"wind_speed": (("H", "W"), np.full((2, 3), 24.0))}).to_netcdf(
                target_dir / "0.nc"
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(VERIFIER),
                    "run",
                    "pred",
                    "test",
                    "--predictions-root",
                    str(predictions_root),
                ],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("SAR PREDICTION VERIFICATION PASSED", result.stdout)


if __name__ == "__main__":
    unittest.main()
