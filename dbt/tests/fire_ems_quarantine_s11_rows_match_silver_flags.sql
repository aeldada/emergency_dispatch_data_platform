-- For each timestamp-order rule, the number of quarantine rows equals the number of
-- fire_ems_unit rows whose flag is true. Returns the rules where the counts differ.
{%- set rules = [('S11-P1','is_on_scene_before_received'),('S11-P2','is_on_scene_before_dispatch'),('S11-P3','is_dispatch_before_received'),('S11-P4','is_available_before_dispatch')] %}
with expected as (
    {%- for code, flag in rules %}
    select '{{ code }}' as violation_code, count(*) as n
    from {{ ref('fire_ems_unit') }} where {{ flag }}
    {{ 'union all' if not loop.last }}
    {%- endfor %}
),
actual as (
    select violation_code, count(*) as n
    from {{ ref('fire_ems_quarantine') }}
    where source_layer = 'silver'
    group by violation_code
)
select e.violation_code, e.n as expected_rows, coalesce(a.n, 0) as actual_rows
from expected e
left join actual a on a.violation_code = e.violation_code
where e.n <> coalesce(a.n, 0)
union all
select a.violation_code, 0, a.n
from actual a
where a.violation_code not in (select violation_code from expected)
