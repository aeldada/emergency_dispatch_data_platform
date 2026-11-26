-- No row in silver.police_call was received before the start date (local).
select cad_number, received_datetime
from {{ ref('police_call') }}
where received_datetime < '{{ var("silver_start_date") }}'::date
