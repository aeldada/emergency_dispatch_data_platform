-- T4a-07: every call_type in the seed exists in Bronze (catches typos in the CSV).
-- Returns seed rows with no Bronze match; passes when it returns 0 rows.
select s.call_type
from {{ ref('call_type_class') }} s
where not exists (
    select 1
    from {{ source('bronze', 'fire_ems_raw') }} b
    where b.record->>'call_type' = s.call_type
)
