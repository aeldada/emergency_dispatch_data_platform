"""Watermark: remembers how far each source has been loaded.

The value is data_loaded_at exactly as the SODA API returned it
(San Francisco local time, no zone marker). It is never converted
and never computed from a UTC clock.
TODO: 
-- Validation check that no data is missing (e.g. a gap in the data_loaded_at values) 
before or afterupdating the watermark(?).
"""

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
import boto3


class LocalWatermarkStore:
    """Stores one JSON file per source in a local folder (tests, offline work).

    Same methods as S3WatermarkStore, so the pipeline does not change.
    """

    def __init__(self, folder):
        self.folder = Path(folder)
        self.folder.mkdir(parents=True, exist_ok=True)

    def _path(self, source):
        return self.folder / f"watermark_{source}.json"

    def read(self, source):
        """Return the stored watermark, or None if there is none (first run)."""
        path = self._path(source)
        if not path.exists():
            return None
        with open(path) as f:
            return json.load(f)["watermark"]

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


class S3WatermarkStore:
    """Same read/write as LocalWatermarkStore, stored in S3 under state/ (D-27)."""

    def __init__(self, bucket, prefix="state/"):
        self.s3 = boto3.client("s3")          # credentials from the default chain (PR-01)
        self.bucket = bucket
        self.prefix = prefix

    def _key(self, source):
        return f"{self.prefix}watermark_{source}.json"

    def read(self, source):
        """Return the stored watermark, or None if there is none (bootstrap)."""
        try:
            obj = self.s3.get_object(Bucket=self.bucket, Key=self._key(source))
        except self.s3.exceptions.NoSuchKey:
            return None
        return json.loads(obj["Body"].read())["watermark"]

    def write(self, source, value):
        """Save the watermark. Call ONLY after the run's data is safely written."""
        record = {
            "source": source,
            "watermark": value,
            "saved_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        # put_object replaces the object in one step: no temp-file trick needed
        self.s3.put_object(
            Bucket=self.bucket,
            Key=self._key(source),
            Body=json.dumps(record).encode("utf-8"),
            ContentType="application/json",
        )


def window_start(watermark, overlap_days):
    """Return the 'since' value for the next fetch.

    None (no watermark) stays None: the caller runs the bootstrap backfill.
    Otherwise subtract the overlap on the same SF-local clock, no conversion.
    """
    if watermark is None:
        return None
    start = datetime.fromisoformat(watermark) - timedelta(days=overlap_days)
    return start.isoformat(timespec="milliseconds")
