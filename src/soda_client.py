"""Fetch rows from the DataSF SODA API.

Datasets: fire/EMS (nuek-vuh3) and police closed calls (2zdj-bwza).
This module only fetches. It does not save anything and does not read .env:
the caller loads the config (src/config.py) and passes the token in.
"""

import time
import requests


class TokenError(Exception):
    """DataSF rejected the app token (HTTP 403). Stop the run, never retry."""


class SodaClient:
    """Client for the SODA API with the app token on every request."""

    def __init__(self, base_url, token, timeout_s=300, retries=6):
        # One reusable connection; the token is sent as a header on every request.
        self._session = requests.Session()
        self._session.headers["X-App-Token"] = token

        # "https://data.sf.gov/" and "https://data.sf.gov" become the same value.
        self.base_url = base_url.rstrip("/")
        self.timeout_s = timeout_s
        self.retries = retries

    def _get(self, url, params):
        """Send one GET request and return the JSON rows.

        Retries on network errors, timeouts, HTTP 429 and HTTP 5xx, waiting
        2 s, 4 s, 8 s ... (max 120 s) between tries. HTTP 403 means the token
        was rejected: raise TokenError at once, no retry.
        """
        for attempt in range(self.retries + 1):
            try:
                response = self._session.get(url, params=params, timeout=self.timeout_s)

                if response.status_code == 403:
                    raise TokenError(f"HTTP 403 from {url}: app token rejected")

                if response.status_code == 429 or response.status_code >= 500:
                    # Server busy or broken: treat like a network error and retry.
                    raise requests.HTTPError(f"HTTP {response.status_code} from {url}")

                response.raise_for_status()  # any other 4xx: a bug on our side, no retry
                return response.json()

            except TokenError:
                raise
            except requests.HTTPError as error:
                status = error.response.status_code if error.response is not None else None
                if status is not None and 400 <= status < 500:
                    raise  # 4xx from raise_for_status(): retrying will not help
                if attempt == self.retries:
                    raise
            except requests.RequestException:
                # Timeout, connection reset (e.g. laptop sleep in V01), DNS ...
                if attempt == self.retries:
                    raise

            time.sleep(min(2 ** attempt * 2, 120))

    def fetch_where(self, dataset_id, where, order, page_size=50000):
        """Yield pages of rows matching a SoQL $where, in a fixed order.

        Each yielded page is a list of dicts (one dict per row).
        """
        url = f"{self.base_url}/resource/{dataset_id}.json"
        offset = 0

        while True:
            rows = self._get(url, {
                "$where": where,
                "$order": order,
                "$limit": page_size,
                "$offset": offset,
            })

            if not rows:
                return
            yield rows

            if len(rows) < page_size:
                return  # last page
            offset += page_size

    def fetch_since(self, dataset_id, since, order_key, page_size=50000):
        """Incremental: rows loaded at or after `since`.

        since:     data_loaded_at value exactly as the API returns it
                   (San Francisco local time, no zone marker; D-46).
        order_key: the dataset's unique key ("rowid" fire/EMS, "cad_number" police);
                   ordering by data_loaded_at plus the key keeps paging stable.
        """
        yield from self.fetch_where(
            dataset_id,
            f"data_loaded_at >= '{since}'",
            f"data_loaded_at, {order_key}",
            page_size,
        )
