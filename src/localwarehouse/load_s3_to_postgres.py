"""Load S3 Bronze JSON files into the local Postgres `bronze` schema.

Source: s3://<aws.bucket>/raw/<source>/**.json, each file one JSON array of records.
Target: bronze.<source>_raw (record jsonb, source_file, file_row, loaded_at),
        same shape as Snowflake BRONZE.<SOURCE>_RAW.

Every copy is kept (backfill + daily runs); Silver deduplicates.
Re-runs use the ledger bronze.loaded_files: a file is skipped only if the
ledger has it with the same S3 ETag. Each file is loaded in ONE transaction:
delete its existing rows, COPY all rows, upsert the ledger row, commit.

Run from the repo root:
  python -m src.localwarehouse.load_s3_to_postgres                 # all sources
  python -m src.localwarehouse.load_s3_to_postgres --source police
"""

import argparse
import json
import logging
import os
import time

import boto3
import psycopg
from dotenv import load_dotenv
from psycopg.types.json import Jsonb

from src.config import load_config

logger = logging.getLogger(__name__)

SOURCES = ("fire_ems", "police")
RAW_PREFIX = "raw/"

DDL = """
CREATE SCHEMA IF NOT EXISTS bronze;

CREATE TABLE IF NOT EXISTS bronze.fire_ems_raw (
    record      jsonb,
    source_file text,
    file_row    int,
    loaded_at   timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS bronze.police_raw (LIKE bronze.fire_ems_raw INCLUDING DEFAULTS);

-- per-file delete on reload must not scan the whole table
CREATE INDEX IF NOT EXISTS fire_ems_raw_source_file_idx ON bronze.fire_ems_raw (source_file);
CREATE INDEX IF NOT EXISTS police_raw_source_file_idx   ON bronze.police_raw (source_file);

CREATE TABLE IF NOT EXISTS bronze.loaded_files (
    source_file text PRIMARY KEY,
    source      text NOT NULL,
    s3_etag     text NOT NULL,
    row_count   int  NOT NULL,
    loaded_at   timestamptz NOT NULL DEFAULT now()
);
"""


def pg_connect():
    """Connect with PG_* from .env (password is never logged)."""
    load_dotenv()
    return psycopg.connect(
        host=os.environ["PG_HOST"],
        port=os.environ["PG_PORT"],
        user=os.environ["PG_USER"],
        password=os.environ["PG_PASSWORD"],
        dbname=os.environ["PG_DATABASE"],
        autocommit=True,
    )


def ensure_schema(conn):
    """Create schema, tables, indexes and ledger if missing (idempotent)."""
    with conn.transaction():
        conn.execute(DDL)


def list_s3_files(s3, bucket, source):
    """Return [(key, etag)] for every .json object under raw/<source>/, sorted by key."""
    files = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=f"{RAW_PREFIX}{source}/"):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".json"):
                files.append((obj["Key"], obj["ETag"].strip('"')))
    return sorted(files)


def ledger_etags(conn, source):
    """{source_file: s3_etag} for one source."""
    rows = conn.execute(
        "SELECT source_file, s3_etag FROM bronze.loaded_files WHERE source = %s", (source,)
    ).fetchall()
    return dict(rows)


def load_file(conn, s3, bucket, source, key, etag):
    """Load one S3 file in one transaction; return its row count."""
    source_file = key[len(RAW_PREFIX):]          # e.g. police/backfill/month=2025-01/page_0001.json
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    records = json.loads(body)
    if not isinstance(records, list):
        raise ValueError(f"{key}: expected a JSON array, got {type(records).__name__}")

    table = f"bronze.{source}_raw"               # source is from SOURCES only
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table} WHERE source_file = %s", (source_file,))
            with cur.copy(f"COPY {table} (record, source_file, file_row) FROM STDIN") as copy:
                for file_row, record in enumerate(records, start=1):
                    copy.write_row((Jsonb(record), source_file, file_row))
            cur.execute(
                """
                INSERT INTO bronze.loaded_files (source_file, source, s3_etag, row_count, loaded_at)
                VALUES (%s, %s, %s, %s, now())
                ON CONFLICT (source_file) DO UPDATE
                   SET source = EXCLUDED.source, s3_etag = EXCLUDED.s3_etag,
                       row_count = EXCLUDED.row_count, loaded_at = EXCLUDED.loaded_at
                """,
                (source_file, source, etag, len(records)),
            )
    return len(records)


def load_source(conn, s3, bucket, source):
    """Load all new or changed files of one source; log per file and a summary."""
    started = time.monotonic()
    files = list_s3_files(s3, bucket, source)
    known = ledger_etags(conn, source)
    loaded = skipped = rows = 0
    for key, etag in files:
        source_file = key[len(RAW_PREFIX):]
        if known.get(source_file) == etag:
            skipped += 1
            logger.info("skipped %s (same etag)", source_file)
            continue
        n = load_file(conn, s3, bucket, source, key, etag)
        loaded += 1
        rows += n
        logger.info("loaded %s rows=%d", source_file, n)
    logger.info(
        "summary %s: files=%d loaded=%d skipped=%d rows_inserted=%d duration=%.1fs",
        source, len(files), loaded, skipped, rows, time.monotonic() - started,
    )
    return {"files": len(files), "loaded": loaded, "skipped": skipped, "rows": rows}


def main(argv=None):
    parser = argparse.ArgumentParser(description="Load S3 Bronze JSON into local Postgres.")
    parser.add_argument("--source", choices=(*SOURCES, "all"), default="all")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

    config = load_config()
    bucket = config["aws"]["bucket"]
    s3 = boto3.client("s3", region_name=config["aws"]["region"])   # default credential chain (PR-01)
    sources = SOURCES if args.source == "all" else (args.source,)

    with pg_connect() as conn:
        ensure_schema(conn)
        for source in sources:
            load_source(conn, s3, bucket, source)


if __name__ == "__main__":
    main()
