-- No row in silver.fire_ems_unit was received before the start date (local).
select rowid, received_dttm
from {{ ref('fire_ems_unit') }}
where received_dttm < '{{ var("silver_start_date") }}'::date
