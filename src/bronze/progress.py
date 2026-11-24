"""Backfill progress ("how far did the backfill get?") per source, stored in S3 next to the watermark.

used only during the full-history backfill, the first run when no watermark exists yet. 
It records which months are already finished.

It only lets an interrupted backfill resume. It never decides incremental vs
backfill mode: only the watermark does that. 
"""

import json
import boto3
from datetime import datetime, timezone


class S3BackfillProgress:
    def __init__(self, bucket, prefix="state/"):
        self.s3 = boto3.client("s3")          # credentials from the default chain (PR-01)
        self.bucket = bucket
        self.prefix = prefix

    def _key(self, source):
        return f"{self.prefix}backfill_progress_{source}.json"

    def read(self, source):
        """Return the progress record, or None if no backfill has started."""
        try:
            obj = self.s3.get_object(Bucket=self.bucket, Key=self._key(source))
        except self.s3.exceptions.NoSuchKey:
            return None
        return json.loads(obj["Body"].read())

    def write(self, source, record):
        """Save the progress record with an updated_at timestamp (UTC)."""
        record = dict(record,
                      updated_at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
        self.s3.put_object(
            Bucket=self.bucket,
            Key=self._key(source),
            Body=json.dumps(record).encode("utf-8"),
            ContentType="application/json",
        )
