-- silver.fire_ems_unit has exactly one row per distinct rowid in Bronze
-- that has a valid call ID and was received on or after the start date.
-- Returns one row with both counts if they differ.
with expected as (
    select count(*) as n
    from (
        select distinct on (record->>'rowid') record
        from {{ source('bronze', 'fire_ems_raw') }}
        where record->>'call_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}
        order by record->>'rowid',
                 (record->>'data_loaded_at')::timestamp desc, loaded_at desc, file_row desc
    ) newest
    where (record->>'received_dttm')::timestamp >= '{{ var("silver_start_date") }}'::date
),
actual as (
    select count(*) as n from {{ ref('fire_ems_unit') }}
)
select expected.n as expected_rows, actual.n as actual_rows
from expected, actual
where expected.n <> actual.n
