-- The fine-grained location columns address and case_location are not in Silver.
select column_name
from information_schema.columns
where table_schema = '{{ ref("fire_ems_unit").schema }}'
  and table_name   = '{{ ref("fire_ems_unit").identifier }}'
  and column_name in ('address', 'case_location')
