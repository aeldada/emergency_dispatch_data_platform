-- Every cad_number in silver.police_call is exactly 9 digits.
select cad_number
from {{ ref('police_call') }}
where cad_number !~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}
