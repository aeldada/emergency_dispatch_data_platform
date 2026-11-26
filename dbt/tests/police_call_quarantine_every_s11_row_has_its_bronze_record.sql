-- Every S11 row found its original Bronze record (the join on source_file + file_row
-- returned a row). Together with bronze_positions_are_unique this proves the join
-- returns exactly one Bronze record per Silver row. Returns rows without one.
select quarantine_id, source_file, file_row
from {{ ref('police_call_quarantine') }}
where source_layer = 'silver'
  and record_data is null
