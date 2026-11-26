-- The attached JSON belongs to the record it is listed under: the ID inside record_data
-- equals record_id.
-- Why: record_data is fetched from Bronze by position (source_file + file_row). A wrong
-- join condition would attach another record's JSON. Checking the ID inside the JSON
-- uses a different path than the join itself, so such a mistake fails here instead of
-- passing unnoticed. Returns rows where the IDs differ.
select quarantine_id, record_id, record_data->>'rowid' as id_in_record_data
from {{ ref('fire_ems_quarantine') }}
where record_id is distinct from record_data->>'rowid'
