"""Load project configuration from config/config.yaml and .env.

Public settings come from the YAML file (committed to Git).
Secrets come from .env (ignored by Git) and are never printed.
"""

import os
from pathlib import Path

import yaml
from dotenv import load_dotenv

# repo_root/config/config.yaml, independent of the current working folder
DEFAULT_PATH = Path(__file__).resolve().parent.parent / "config" / "config.yaml"


def load_config(path=DEFAULT_PATH):
    """Return the project config as a dict, including the SODA app token."""
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")

    with open(path) as f:
        config = yaml.safe_load(f)

    if config is None:
        raise ValueError(f"Config file is empty: {path}")

    load_dotenv()
    token = os.getenv("SODA_APP_TOKEN")
    if not token:
        raise ValueError("SODA_APP_TOKEN is missing or empty. Set it in .env")

    config["soda"]["app_token"] = token
    return config