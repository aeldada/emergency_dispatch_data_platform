"""Ingestion: SODA API → S3 Bronze, per source (D-47).

Mode is decided ONLY by the watermark:
  watermark exists → incremental (since = watermark − overlap)
  watermark None   → backfill month by month + undated rows, resumable;
                     the watermark is written only when ALL of it is done.
Test scope: --months YYYY-MM ... runs those months only; it writes raw files
and month manifests but never touches backfill progress or the watermark.

Run from the repo root:
  python -m src.bronze.ingest
  python -m src.bronze.ingest --source police --months 2025-01
"""

import argparse
from datetime import datetime, timezone
from src.bronze.progress import S3BackfillProgress
from src.bronze.writer import S3BronzeWriter
from src.config import load_config
from src.soda_client import SodaClient
from src.watermark import S3WatermarkStore, window_start


def later(a, b):
    """The later of two data_loaded_at strings (None-safe)."""
    if a is None:
        return b
    if b is None:
        return a
    return max(a, b)


def newest_in(rows):
    """Newest data_loaded_at in a page, or None if no row has one."""
    stamps = [r["data_loaded_at"] for r in rows if r.get("data_loaded_at")]
    return max(stamps) if stamps else None


def next_month(month):
    """'2025-12' -> '2026-01'."""
    y, m = map(int, month.split("-"))
    return f"{y + 1}-01" if m == 12 else f"{y}-{m + 1:02d}"


def months_from(start, end):
    """Inclusive list of months 'YYYY-MM' from start to end."""
    out, m = [], start
    while m <= end:
        out.append(m)
        m = next_month(m)
    return out


def month_where(col, month):
    """SoQL filter for one calendar month on the call-date column."""
    return f"{col} >= '{month}-01T00:00:00' AND {col} < '{next_month(month)}-01T00:00:00'"


def fetch_and_write(client, writer, ds, where, order, prefix, window):
    """Fetch all pages for one window and write them; return (pages, newest)."""
    pages, newest = 0, None
    for rows in client.fetch_where(ds["id"], where, order):
        pages += 1
        writer.write_page(rows, prefix, pages, window)
        newest = later(newest, newest_in(rows))
    return pages, newest


def run_incremental(name, ds, client, wm_store, writer, run_id, load_date, old):
    """Daily path: since = watermark − overlap → pages → manifest → watermark."""
    since = window_start(old, ds["overlap_days"])
    newest = old
    pages = 0
    for rows in client.fetch_since(ds["id"], since, ds["key"]):
        pages += 1
        writer.write_page(rows, f"load_date={load_date}/run_{run_id}", pages, since)
        newest = later(newest, newest_in(rows))

    key, rows = writer.flush_manifest(f"run_{run_id}.jsonl")   # manifest first …
    wm_store.write(name, newest)                               # … then the watermark
    print(f"{name}: INCREMENTAL since {since} | pages {pages} | rows {rows} | "
          f"watermark {old} -> {newest} | {key}")


def run_backfill(name, ds, client, wm_store, progress, writer, run_id, test_months):
    """Bootstrap path (watermark None), or a test run limited to some months."""
    col, order = ds["date_column"], ds["key"]
    current = datetime.now(timezone.utc).strftime("%Y-%m")

    # Test scope: write raw files + month manifests, but no progress, no watermark.
    if test_months:
        for m in test_months:
            pages, _ = fetch_and_write(client, writer, ds, month_where(col, m), order,
                                       f"backfill/month={m}", m)
            key, rows = writer.flush_manifest(f"backfill/month={m}.jsonl")
            print(f"{name}: TEST month {m} | pages {pages} | rows {rows} | {key} "
                  f"| progress/watermark untouched")
        return

    # Full backfill: resume from progress if a previous run stopped part-way.
    prog = progress.read(name) or {
        "source": name,
        "backfill_start": ds["backfill_start"],
        "last_completed_month": None,
        "null_dates_completed": False,
        "newest_loaded_at": None,
        "status": "running",
    }
    prog["run_id"] = run_id
    start = (next_month(prog["last_completed_month"]) if prog["last_completed_month"]
             else ds["backfill_start"])

    for m in months_from(start, current):
        pages, newest = fetch_and_write(client, writer, ds, month_where(col, m), order,
                                        f"backfill/month={m}", m)
        key, rows = writer.flush_manifest(f"backfill/month={m}.jsonl")
        # A month counts as complete only after its pages AND manifest are written.
        prog["last_completed_month"] = m
        prog["newest_loaded_at"] = later(prog["newest_loaded_at"], newest)
        progress.write(name, prog)
        print(f"{name}: month {m} | pages {pages} | rows {rows}")

    # Rows without a call date belong to no month: fetch them once (X06, P17).
    if not prog["null_dates_completed"]:
        pages, newest = fetch_and_write(client, writer, ds, f"{col} IS NULL", order,
                                        "backfill/undated", "undated")
        key, rows = writer.flush_manifest("backfill/undated.jsonl")
        prog["null_dates_completed"] = True
        prog["newest_loaded_at"] = later(prog["newest_loaded_at"], newest)
        progress.write(name, prog)
        print(f"{name}: undated | pages {pages} | rows {rows}")

    # Only now is the full history loaded: write the watermark, mark complete.
    wm_store.write(name, prog["newest_loaded_at"])
    prog["status"] = "complete"
    progress.write(name, prog)
    print(f"{name}: BACKFILL COMPLETE | watermark -> {prog['newest_loaded_at']}")


def main():
    parser = argparse.ArgumentParser(description="SODA API → S3 Bronze ingestion")
    parser.add_argument("--source", help="only this dataset (e.g. police)")
    parser.add_argument("--months", nargs="+", help="TEST: only these months (YYYY-MM)")
    args = parser.parse_args()

    config = load_config()                                     # also loads .env
    bucket = config["aws"]["bucket"]
    client = SodaClient(config["soda"]["base_url"], config["soda"]["app_token"])
    wm_store = S3WatermarkStore(bucket, config["state"]["s3_prefix"])
    progress = S3BackfillProgress(bucket, config["state"]["s3_prefix"])

    now = datetime.now(timezone.utc)
    run_id, load_date = now.strftime("%Y%m%dT%H%MZ"), now.strftime("%Y-%m-%d")

    for name, ds in config["datasets"].items():
        if args.source and name != args.source:
            continue
        writer = S3BronzeWriter(bucket, name, run_id, load_date)
        old = wm_store.read(name)
        if old is not None and not args.months:
            run_incremental(name, ds, client, wm_store, writer, run_id, load_date, old)
        else:
            run_backfill(name, ds, client, wm_store, progress, writer, run_id, args.months)


if __name__ == "__main__":
    main()
