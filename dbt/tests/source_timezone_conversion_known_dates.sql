-- Fixed examples for the time-zone conversion used in Silver (no table data).
-- Winter: 12:00 local = 20:00 UTC. Summer: 12:00 local = 19:00 UTC.
-- Day after the November change: 12:00 local = 20:00 UTC.
-- Returns the examples that do not match.
with cases(local_ts, expected_utc) as (
    values
        ('2025-01-15 12:00:00'::timestamp, '2025-01-15 20:00:00+00'::timestamptz),
        ('2025-07-01 12:00:00'::timestamp, '2025-07-01 19:00:00+00'::timestamptz),
        ('2025-11-03 12:00:00'::timestamp, '2025-11-03 20:00:00+00'::timestamptz)
)
select local_ts, expected_utc, local_ts at time zone '{{ var("source_timezone") }}' as actual_utc
from cases
where local_ts at time zone '{{ var("source_timezone") }}' <> expected_utc
