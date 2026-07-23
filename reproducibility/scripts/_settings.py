"""Load ignored MOTIF reproduction settings without executing shell code."""

from __future__ import annotations

import os
from pathlib import Path

REPRO_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = REPRO_DIR / "config.local.env"


def load_settings() -> dict[str, str]:
    """Return config values, with exported environment variables taking precedence."""
    config_path = Path(os.environ.get("MOTIF_CONFIG_FILE", DEFAULT_CONFIG))
    settings: dict[str, str] = {}
    if config_path.is_file():
        for line_number, raw_line in enumerate(config_path.read_text().splitlines(), start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ValueError(f"Invalid config line {config_path}:{line_number}: {raw_line}")
            key, value = line.split("=", 1)
            key = key.strip()
            if not key.startswith("MOTIF_") or not key.replace("_", "").isalnum():
                raise ValueError(f"Invalid config key {config_path}:{line_number}: {key}")
            settings[key] = value
    settings.update({key: value for key, value in os.environ.items() if key.startswith("MOTIF_")})
    return settings


SETTINGS = load_settings()


def setting(name: str, default: str) -> str:
    """Read a non-empty setting or return its default."""
    return SETTINGS.get(name) or default
