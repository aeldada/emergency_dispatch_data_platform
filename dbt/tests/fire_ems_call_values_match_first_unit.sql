-- Every carried column in silver.fire_ems_call equals the value on its first unit's row.
-- Returns calls where any value differs.
{%- set cols = ['call_number', 'incident_number', 'call_date', 'watch_date',
                'received_dttm', 'received_utc', 'entry_dttm', 'entry_utc',
                'dispatch_dttm', 'dispatch_utc', 'on_scene_dttm', 'on_scene_utc',
                'call_type', 'service_class', 'call_type_group', 'final_priority',
                'call_final_disposition', 'number_of_alarms', 'battalion', 'station_area',
                'fire_prevention_district', 'supervisor_district', 'area', 'zipcode_of_incident',
                'is_private_unit', 'is_call_to_arrival_order_valid', 'is_dispatch_to_arrival_order_valid'] %}
select c.call_number
from {{ ref('fire_ems_call') }} c
join {{ ref('fire_ems_unit') }} u on u.rowid = c.first_unit_rowid
where
    {%- for col in cols %}
    c.{{ col }} is distinct from u.{{ col }} {{ 'or' if not loop.last }}
    {%- endfor %}
