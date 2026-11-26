-- Guard: no call has two units with dispatch sequence 1. If one appears, the choice between
-- them falls to the tie-break, which may not be the real first unit; how to handle it is not
-- decided yet. Returns such calls.
select call_number, count(*) as units_with_sequence_one
from {{ ref('fire_ems_unit') }}
where unit_sequence_in_call_dispatch = 1
group by call_number
having count(*) > 1
