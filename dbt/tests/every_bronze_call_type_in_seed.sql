-- T4a-06: every fire/EMS call_type found in Bronze (all years, all copies)
-- has a row in the seed call_type_class. Returns the missing call types;
-- the test passes when it returns 0 rows.
select distinct b.record->>'call_type' as call_type
from {{ source('bronze', 'fire_ems_raw') }} b
left join {{ ref('call_type_class') }} s
       on s.call_type = b.record->>'call_type'
where s.call_type is null
