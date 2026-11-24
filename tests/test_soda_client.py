"""Tests for src/soda_client.py (step 1: creating the client)."""

from src.soda_client import SodaClient


def test_token_is_sent_as_header():
    client = SodaClient("https://data.sf.gov", "fake-token")

    assert client._session.headers["X-App-Token"] == "fake-token"


def test_trailing_slash_is_removed():
    client = SodaClient("https://data.sf.gov/", "fake-token")

    assert client.base_url == "https://data.sf.gov"
