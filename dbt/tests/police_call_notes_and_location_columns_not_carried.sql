-- Free-text notes, the incident report number and the intersection columns are not in Silver.
select column_name
from information_schema.columns
where table_schema = '{{ ref("police_call").schema }}'
  and table_name   = '{{ ref("police_call").identifier }}'
  and column_name in ('call_type_original_notes', 'call_type_final_notes', 'pd_incident_report',
                      'intersection_name', 'intersection_id', 'intersection_point')
