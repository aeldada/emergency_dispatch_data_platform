-- The S1 rows in quarantine are exactly the Bronze rows whose cad_number is not a valid
-- call ID (not exactly id_length digits, or missing): same number of rows.
-- Returns one row with both counts if they differ.
with expected as (
    select count(*) as n
    from {{ source('bronze', 'police_raw') }}
    where not coalesce(record->>'cad_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}, false)
),
actual as (
    select count(*) as n from {{ ref('police_call_quarantine') }} where violation_code = 'S1'
)
select expected.n as expected_rows, actual.n as actual_rows
from expected, actual
where expected.n <> actual.n
