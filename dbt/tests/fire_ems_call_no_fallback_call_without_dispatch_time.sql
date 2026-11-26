-- Guard: every call without a sequence-1 unit has at least one unit with a dispatch time,
-- so the fallback (earliest dispatch) can choose. Otherwise the choice falls to the lowest
-- rowid; how to handle it is not decided yet. Returns such calls.
select call_number
from {{ ref('fire_ems_unit') }}
group by call_number
having not coalesce(bool_or(unit_sequence_in_call_dispatch = 1), false)
   and count(dispatch_utc) = 0
