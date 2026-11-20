"""Tests for src/config.py."""

import pytest

from src import config as config_module
from src.config import load_config


@pytest.fixture
def no_dotenv(monkeypatch):
    """Stop load_config from reading the real .env file."""
    monkeypatch.setattr(config_module, "load_dotenv", lambda: None)


def test_loads_real_config(monkeypatch, no_dotenv):
    monkeypatch.setenv("SODA_APP_TOKEN", "test-token")

    config = load_config()

    assert config["datasets"]["fire_ems"]["id"] == "nuek-vuh3"
    assert config["datasets"]["police"]["id"] == "2zdj-bwza"
    assert config["datasets"]["fire_ems"]["overlap_days"] == 2
    assert config["soda"]["app_token"] == "test-token"


def test_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_config(tmp_path / "does_not_exist.yaml")


def test_empty_file_raises(tmp_path):
    empty = tmp_path / "empty.yaml"
    empty.write_text("")

    with pytest.raises(ValueError, match="empty"):
        load_config(empty)


def test_missing_token_raises(monkeypatch, no_dotenv):
    monkeypatch.delenv("SODA_APP_TOKEN", raising=False)

    with pytest.raises(ValueError, match="SODA_APP_TOKEN"):
        load_config()