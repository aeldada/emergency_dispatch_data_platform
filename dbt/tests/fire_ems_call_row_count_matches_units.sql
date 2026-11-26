-- silver.fire_ems_call has exactly one row per distinct call_number in silver.fire_ems_unit.
-- Returns one row with both counts if they differ.
with expected as (
    select count(distinct call_number) as n from {{ ref('fire_ems_unit') }}
),
actual as (
    select count(*) as n from {{ ref('fire_ems_call') }}
)
select expected.n as expected_rows, actual.n as actual_rows
from expected, actual
where expected.n <> actual.n
