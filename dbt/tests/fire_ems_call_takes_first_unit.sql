-- The chosen unit follows the rule: a unit with dispatch sequence 1 when the call has one;
-- otherwise a unit with the call's earliest dispatch time.
-- Returns calls where the chosen unit breaks the rule.
with per_call as (
    select call_number,
           bool_or(unit_sequence_in_call_dispatch = 1) as has_sequence_one,
           min(dispatch_utc)                           as earliest_dispatch
    from {{ ref('fire_ems_unit') }}
    group by call_number
)
select c.call_number, u.rowid, u.unit_sequence_in_call_dispatch, u.dispatch_utc
from {{ ref('fire_ems_call') }} c
join {{ ref('fire_ems_unit') }} u on u.rowid = c.first_unit_rowid
join per_call p on p.call_number = c.call_number
where u.call_number <> c.call_number
   or (p.has_sequence_one and u.unit_sequence_in_call_dispatch is distinct from 1)
   or (not coalesce(p.has_sequence_one, false)
       and u.dispatch_utc is distinct from p.earliest_dispatch)
