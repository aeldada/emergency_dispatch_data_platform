-- Records removed for an invalid ID (S1) are really absent from Silver:
-- no Silver row comes from the same Bronze position. Returns the ones that are present.
select q.source_file, q.file_row
from {{ ref('fire_ems_quarantine') }} q
join {{ ref('fire_ems_unit') }} s
  on s.source_file = q.source_file
 and s.file_row    = q.file_row
where q.violation_code = 'S1'
