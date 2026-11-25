"""Bronze writer: saves fetched pages to S3 raw/ and writes manifests.
A manifest is written once per run, and once per month during the backfill. 
It lists:

--the files written (S3 paths)
--the row count per file and in total
--the run and time information

Raw format for now: parsed rows re-serialized as JSON.
"""

import hashlib
import json
import boto3


class S3BronzeWriter:
    """Writes pages for one source in one run; collects manifest lines."""

    def __init__(self, bucket, source, run_id, load_date):
        self.s3 = boto3.client("s3")          # credentials from the default chain (PR-01)
        self.bucket = bucket
        self.source = source
        self.run_id = run_id                  # e.g. "20261123T1520Z"
        self.load_date = load_date            # UTC date of the run, e.g. "2026-11-23"
        self._lines = []

    def write_page(self, rows, prefix, page_no, window):
        """Save one page under raw/<source>/<prefix>/ and remember its manifest line.

        prefix: "load_date=…/run_…" (incremental), "backfill/month=YYYY-MM"
                or "backfill/undated" (D-47).
        window: what was asked for ("since" value, "YYYY-MM" or "undated").
        """
        body = json.dumps(rows).encode("utf-8")
        key = f"raw/{self.source}/{prefix}/page_{page_no:04d}.json"
        self.s3.put_object(Bucket=self.bucket, Key=key, Body=body,
                           ContentType="application/json")
        self._lines.append({
            "source": self.source,
            "run_id": self.run_id,
            "load_date": self.load_date,
            "window": window,
            "file": key,
            "rows": len(rows),
            "bytes": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
        })

    def flush_manifest(self, key):
        """Write the collected lines to manifests/<source>/<key>; return (full key, rows).

        Clears the collected lines, so one writer can produce one manifest per month.
        """
        full_key = f"manifests/{self.source}/{key}"
        body = "".join(json.dumps(line) + "\n" for line in self._lines)
        self.s3.put_object(Bucket=self.bucket, Key=full_key, Body=body.encode("utf-8"),
                           ContentType="application/x-ndjson")
        rows = sum(line["rows"] for line in self._lines)
        self._lines = []
        return full_key, rows
