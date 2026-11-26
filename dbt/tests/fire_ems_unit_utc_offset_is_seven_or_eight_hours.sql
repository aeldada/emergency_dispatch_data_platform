-- San Francisco is 8 hours behind UTC in winter and 7 in summer, so every
-- received time must convert to UTC with an offset of exactly 7 or 8 hours.
select rowid, received_dttm, received_utc
from {{ ref('fire_ems_unit') }}
where extract(epoch from (received_utc - (received_dttm at time zone 'UTC'))) / 3600 not in (7, 8)
