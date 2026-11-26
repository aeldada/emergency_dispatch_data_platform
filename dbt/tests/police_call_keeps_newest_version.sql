-- For every cad_number, Silver holds the newest Bronze copy: no other Bronze copy
-- of the same cad_number has a later data_loaded_at. Returns rows that are not the newest.
select s.cad_number, s.data_loaded_at as silver_version,
       max((b.record->>'data_loaded_at')::timestamp) as newest_in_bronze
from {{ ref('police_call') }} s
join {{ source('bronze', 'police_raw') }} b
  on b.record->>'cad_number' = s.cad_number
group by s.cad_number, s.data_loaded_at
having max((b.record->>'data_loaded_at')::timestamp) > s.data_loaded_at
