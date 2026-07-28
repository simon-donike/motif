import unittest
from pathlib import Path

from hydra import compose, initialize_config_dir
from omegaconf import OmegaConf


REPO_ROOT = Path(__file__).resolve().parents[1]


class SarConfigurationTest(unittest.TestCase):
    def compose(self, config_name, overrides):
        with initialize_config_dir(
            config_dir=str((REPO_ROOT / "configs").resolve()),
            version_base=None,
        ):
            return OmegaConf.to_container(
                compose(config_name=config_name, overrides=overrides),
                resolve=True,
            )

    def test_training_targets_sar_with_pmw_and_ir_context(self):
        cfg = self.compose(
            "train",
            [
                "experiment=fm_PI_sar",
                "model=motif_12b_d512",
                "setup=local",
                "paths=example",
                "trainer.devices=1",
                "dataloader.batch_size=1",
                "wandb.name=test",
                "run_local=true",
            ],
        )

        self.assertEqual(cfg["lightning_module"]["mask_only_sources"], ["sar"])
        self.assertEqual(cfg["dataset"]["train"]["reference_sources"], ["sar_cband"])
        self.assertEqual(
            cfg["dataset"]["train"]["groups_availability"],
            {
                "sar": {"sources": ["sar_cband"], "availability": [1, 1]},
                "pmw": {"sources": ["pmw"], "availability": [1, 2]},
                "ir": {"sources": ["infrared"], "availability": [1, 1]},
            },
        )
        self.assertEqual(cfg["sources"]["sar"]["cband"]["variables"], ["wind_speed"])
        self.assertEqual(cfg["lr_scheduler"]["max_lr"], 1e-6)

    def test_inference_always_uses_held_out_sar_overpasses(self):
        cfg = self.compose(
            "make_predictions",
            [
                "inference_cfg=fm_sar_PI_dt6",
                "setup=local",
                "paths=example",
                "trainer.devices=1",
                "run_id=test",
                "split=test",
            ],
        )

        self.assertEqual(cfg["lightning_module"]["mask_only_sources"], ["sar_cband"])
        for split in ("val", "test"):
            self.assertEqual(cfg["dataset"][split]["reference_sources"], ["sar_cband"])
            self.assertEqual(cfg["dataset"][split]["dt_min"], -3)
            self.assertEqual(cfg["dataset"][split]["dt_max"], 3)
            self.assertTrue(cfg["dataset"][split]["select_closest"])


if __name__ == "__main__":
    unittest.main()
