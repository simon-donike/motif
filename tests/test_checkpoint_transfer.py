import unittest

import torch
from torch import nn

from motif.utils.checkpoints import load_validated_state_dict_transfer


class TransferModule(nn.Module):
    def __init__(self):
        super().__init__()
        self.backbone = nn.Linear(2, 2, bias=False)
        self.sar = nn.Linear(2, 1, bias=False)


class ValidatedCheckpointTransferTest(unittest.TestCase):
    def test_loads_shared_weights_and_allows_declared_source_changes(self):
        module = TransferModule()
        checkpoint_weight = torch.full_like(module.backbone.weight, 3.0)
        state_dict = {
            "backbone.weight": checkpoint_weight,
            "pmw_head.weight": torch.ones(1, 2),
        }

        missing, unexpected = load_validated_state_dict_transfer(
            module,
            state_dict,
            allowed_missing_prefixes=["sar."],
            allowed_unexpected_prefixes=["pmw_head."],
        )

        self.assertEqual(missing, ["sar.weight"])
        self.assertEqual(unexpected, ["pmw_head.weight"])
        torch.testing.assert_close(module.backbone.weight, checkpoint_weight)

    def test_rejects_undeclared_missing_key(self):
        module = TransferModule()
        with self.assertRaisesRegex(RuntimeError, "undeclared missing keys"):
            load_validated_state_dict_transfer(
                module,
                {"backbone.weight": module.backbone.weight.detach().clone()},
            )

    def test_rejects_undeclared_unexpected_key(self):
        module = TransferModule()
        state_dict = module.state_dict()
        state_dict["unknown.weight"] = torch.ones(1)
        with self.assertRaisesRegex(RuntimeError, "undeclared unexpected keys"):
            load_validated_state_dict_transfer(module, state_dict)

    def test_rejects_shape_mismatch(self):
        module = TransferModule()
        state_dict = module.state_dict()
        state_dict["backbone.weight"] = torch.ones(3, 2)
        with self.assertRaisesRegex(RuntimeError, "shape mismatches"):
            load_validated_state_dict_transfer(module, state_dict)


if __name__ == "__main__":
    unittest.main()
