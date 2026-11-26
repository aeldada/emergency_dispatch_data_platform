-- Every Bronze position (source_file + file_row) occurs once.
-- Why: quarantine fetches the original JSON of a Silver row from Bronze by this position,
-- and quarantine_id is a hash of it. Nothing in the database enforces it (no unique index);
-- the loader's design makes duplicates impossible. A duplicate would attach two Bronze
-- records to one Silver row and give two quarantine rows the same ID.
-- Returns every position that occurs more than once.
select 'fire_ems_raw' as bronze_table, source_file, file_row, count(*) as copies
from {{ source('bronze', 'fire_ems_raw') }}
group by source_file, file_row
having count(*) > 1
union all
select 'police_raw', source_file, file_row, count(*)
from {{ source('bronze', 'police_raw') }}
group by source_file, file_row
having count(*) > 1
