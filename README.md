## Repository layout

```text
emergency_dispatch_data_platform/
├── src/
│   ├── bronze/                 # ingestion: SODA API → S3 Bronze (raw JSON pages + manifests)
│   ├── localwarehouse/         # S3 Bronze → local PostgreSQL `bronze` schema (load_s3_to_postgres.py)
│   ├── config.py               # shared: loads config/config.yaml + secrets from .env
│   ├── soda_client.py          # shared: SODA API client (retries, paging)
│   └── watermark.py            # shared: watermark stores (local + S3)
├── tests/                      # unit tests, no network (pytest)
│   └── integration/
│       └── bronze/             # Stage 2 checks (T2-xx) against real S3 + Postgres; see its README
├── config/                     # config.yaml: public, non-secret settings (datasets, bucket, region)
├── dbt/                        # added in Stage 3
├── bin/
│   └── dbt.sh                  # added in Stage 3
├── docker-compose.yml          # local PostgreSQL container `dispatch_pg` (port 5433)
├── requirements.txt            # runtime dependencies (pinned)
├── requirements-dev.txt        # development/test dependencies
└── .env.example                # template for .env: variable names, no secret values
```

`.env` holds the secrets (SODA token, AWS keys, Postgres and Snowflake credentials).
It is git-ignored and never committed; copy `.env.example` to `.env` and fill it in locally.
