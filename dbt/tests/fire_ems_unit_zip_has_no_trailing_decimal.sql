-- No zip code in silver.fire_ems_unit ends in '.0'.
select rowid, zipcode_of_incident
from {{ ref('fire_ems_unit') }}
where zipcode_of_incident like '%.0'
