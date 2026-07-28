import unittest

import numpy as np
import xarray as xr

from preproc.sar.prepare_sar import extract_cyclobs_wind_fields, normalize_seasons


class SarPreprocessingTest(unittest.TestCase):
    def test_normalizes_integer_profile_seasons_for_string_metadata(self):
        self.assertEqual(
            normalize_seasons([1993, 2014, 2015, 2016]),
            {"1993", "2014", "2015", "2016"},
        )

    def test_preserves_none(self):
        self.assertIsNone(normalize_seasons(None))

    def test_current_rejection_flags_mask_rejected_winds_and_identify_land(self):
        ds = xr.Dataset(
            {
                "wind_speed": (
                    ("time", "lat", "lon"),
                    [[[10.0, 20.0, 30.0], [40.0, 50.0, 60.0]]],
                ),
                "rejection_flag": (
                    ("time", "lat", "lon"),
                    [[[0.0, 1.0, 8.0], [16.0, 2.0, 17.0]]],
                ),
            }
        )

        fields, land_mask = extract_cyclobs_wind_fields(ds)

        np.testing.assert_array_equal(
            land_mask,
            [[False, True, False], [False, False, True]],
        )
        np.testing.assert_allclose(
            fields["wind_speed"],
            [[10.0, np.nan, np.nan], [np.nan, np.nan, np.nan]],
            equal_nan=True,
        )

    def test_legacy_mask_flags_remain_supported(self):
        ds = xr.Dataset(
            {
                "wind_speed": (
                    ("time", "lat", "lon"),
                    [[[10.0, 20.0, 30.0, 40.0, 50.0]]],
                ),
                "mask_flag": (
                    ("time", "lat", "lon"),
                    [[[0.0, 1.0, 2.0, 3.0, 4.0]]],
                ),
            }
        )

        fields, land_mask = extract_cyclobs_wind_fields(ds)

        np.testing.assert_array_equal(
            land_mask,
            [[False, True, False, False, False]],
        )
        np.testing.assert_allclose(
            fields["wind_speed"],
            [[10.0, np.nan, np.nan, np.nan, np.nan]],
            equal_nan=True,
        )

    def test_rejects_unknown_mask_schema(self):
        ds = xr.Dataset({"wind_speed": (("time", "lat", "lon"), [[[10.0]]])})

        with self.assertRaisesRegex(KeyError, "neither current"):
            extract_cyclobs_wind_fields(ds)


if __name__ == "__main__":
    unittest.main()
