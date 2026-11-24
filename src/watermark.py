"""Watermark: remembers how far each source has been loaded.

The value is data_loaded_at exactly as the SODA API returned it 
( never computed or convrted from/to UTC clock). 
"""

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path


class LocalWatermarkStore:
    """Stores one JSON file per source in a local folder.

    Same methods as the later S3 store, so the pipeline does not change.
    """

    def __init__(self, folder):
        self.folder = Path(folder)
        self.folder.mkdir(parents=True, exist_ok=True)

    def _path(self, source):
        return self.folder / f"watermark_{source}.json"

    def write(self, source, value):
        """Save the watermark. Call ONLY after the run's data is safely written.

        Writes to a temp file first, then renames it, so a crash can never
        leave a half-written watermark file.
        """
        record = {
            "source": source,
            "watermark": value,
            "saved_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        path = self._path(source)
        tmp = path.with_suffix(".json.tmp")
        with open(tmp, "w") as f:
            json.dump(record, f)
        os.replace(tmp, path)  # atomic on the same disk

    def read(self, source):
            """Return the stored watermark, or None if there is none 
            (first run - full load).
            """
            path = self._path(source)
            if not path.exists():
                return None
            with open(path) as f:
                return json.load(f)["watermark"]

def window_start(watermark, overlap_days):
    """Return the 'since' value for the next fetch.

    None (first run) stays None: the caller does a full load / backfill.
    Otherwise subtract the overlap on the same SF-local clock, no conversion.
    """
    if watermark is None:
        return None
    start = datetime.fromisoformat(watermark) - timedelta(days=overlap_days)
    return start.isoformat(timespec="milliseconds")