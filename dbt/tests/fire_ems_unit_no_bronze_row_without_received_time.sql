-- Guard: no Bronze fire/EMS row with a valid call ID lacks a received time.
-- Such a row would silently miss the date filter; how to handle it is not decided yet.
-- Fails (returns rows) as soon as one appears.
select source_file, file_row
from {{ source('bronze', 'fire_ems_raw') }}
where record->>'call_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}
  and (record->>'received_dttm') is null
