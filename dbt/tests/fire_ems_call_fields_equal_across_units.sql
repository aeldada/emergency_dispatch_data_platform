-- The call table takes call-level fields from the first unit. That is only right if every
-- unit of a call has the same value. Returns calls where any of these fields differs
-- between units (a missing value counts as a value).
{%- set call_fields = ['incident_number', 'call_date', 'watch_date', 'received_dttm', 'entry_dttm',
                       'call_type', 'service_class', 'call_type_group', 'final_priority',
                       'call_final_disposition', 'number_of_alarms', 'battalion', 'station_area',
                       'fire_prevention_district', 'supervisor_district', 'area', 'zipcode_of_incident'] %}
select call_number
    {%- for f in call_fields %},
    count(distinct coalesce({{ f }}::text, '<missing>')) as {{ f }}_values
    {%- endfor %}
from {{ ref('fire_ems_unit') }}
group by call_number
having
    {%- for f in call_fields %}
    count(distinct coalesce({{ f }}::text, '<missing>')) > 1 {{ 'or' if not loop.last }}
    {%- endfor %}
