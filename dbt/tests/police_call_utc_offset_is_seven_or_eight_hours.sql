-- Every received time converts to UTC with an offset of exactly 7 or 8 hours.
select cad_number, received_datetime, received_utc
from {{ ref('police_call') }}
where extract(epoch from (received_utc - (received_datetime at time zone 'UTC'))) / 3600 not in (7, 8)
