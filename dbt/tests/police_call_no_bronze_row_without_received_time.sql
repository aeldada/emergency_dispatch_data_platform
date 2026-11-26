-- Guard: no Bronze police row with a valid cad_number lacks a received time.
-- Such a row would silently miss the date filter; how to handle it is not decided yet.
-- Fails (returns rows) as soon as one appears.
select source_file, file_row
from {{ source('bronze', 'police_raw') }}
where record->>'cad_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}
  and (record->>'received_datetime') is null
