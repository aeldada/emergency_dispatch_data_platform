-- For every rowid, Silver holds the newest Bronze copy: no other Bronze copy of
-- the same rowid has a later data_loaded_at (copies with the same data_loaded_at
-- are identical, measured). Returns Silver rows that are not the newest.
select s.rowid, s.data_loaded_at as silver_version, max((b.record->>'data_loaded_at')::timestamp) as newest_in_bronze
from {{ ref('fire_ems_unit') }} s
join {{ source('bronze', 'fire_ems_raw') }} b
  on b.record->>'rowid' = s.rowid
group by s.rowid, s.data_loaded_at
having max((b.record->>'data_loaded_at')::timestamp) > s.data_loaded_at
