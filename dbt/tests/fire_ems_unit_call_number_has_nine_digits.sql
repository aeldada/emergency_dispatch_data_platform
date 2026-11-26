-- Every call_number in silver.fire_ems_unit is exactly 9 digits.
-- Returns offending rows; passes with 0 rows.
select rowid, call_number
from {{ ref('fire_ems_unit') }}
where call_number !~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}
