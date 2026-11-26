-- silver.police_call has exactly one row per distinct cad_number in Bronze
-- that is 9 digits and was received on or after the start date (newest version).
-- Returns one row with both counts if they differ.
with expected as (
    select count(*) as n
    from (
        select distinct on (record->>'cad_number') record
        from {{ source('bronze', 'police_raw') }}
        where record->>'cad_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}
        order by record->>'cad_number',
                 (record->>'data_loaded_at')::timestamp desc, loaded_at desc, file_row desc
    ) newest
    where (record->>'received_datetime')::timestamp >= '{{ var("silver_start_date") }}'::date
),
actual as (
    select count(*) as n from {{ ref('police_call') }}
)
select expected.n as expected_rows, actual.n as actual_rows
from expected, actual
where expected.n <> actual.n
