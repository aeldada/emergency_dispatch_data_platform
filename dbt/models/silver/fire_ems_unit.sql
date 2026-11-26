{#
  silver.fire_ems_unit — one row per fire/EMS unit on a call (key: rowid).

  Steps, in order:
    1. keep only rows whose call_number is exactly 9 digits (all years, before any filter)
    2. keep the newest version of each rowid
       (newest data_loaded_at, then newest Bronze load time, then highest row in file)
    3. keep calls received on or after silver_start_date (local date)
    4. cast types; each timestamp keeps its local value and gains a UTC column
    5. service class from the seed call_type_class
    6. clean codes: battalion, zip code, area
    7. timestamp-order flags (a later step recorded earlier than the step before it)
    8. private-unit flag
  Not carried: address, case_location (fine-grained location, not needed downstream).
#}

{%- set tz = var('source_timezone') -%}
{%- set ts_cols = ['received_dttm', 'entry_dttm', 'dispatch_dttm', 'response_dttm',
                   'on_scene_dttm', 'transport_dttm', 'hospital_dttm', 'available_dttm'] -%}

with bronze as (

    select record, source_file, file_row, loaded_at
    from {{ source('bronze', 'fire_ems_raw') }}

),

valid_id as (

    -- rows with an invalid call ID never reach Silver
    select *
    from bronze
    where record->>'call_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}

),

newest_version as (

    select *
    from (
        select
            valid_id.*,
            row_number() over (
                partition by record->>'rowid'
                order by (record->>'data_loaded_at')::timestamp desc,
                         loaded_at desc,
                         file_row desc
            ) as version_rank
        from valid_id
    ) ranked
    where version_rank = 1

),

in_period as (

    select *
    from newest_version
    where (record->>'received_dttm')::timestamp >= '{{ var("silver_start_date") }}'::date

),

typed as (

    select
        -- identifiers
        record->>'rowid'                                        as rowid,
        record->>'call_number'                                  as call_number,
        record->>'incident_number'                              as incident_number,
        record->>'unit_id'                                      as unit_id,
        record->>'unit_type'                                    as unit_type,
        (record->>'unit_sequence_in_call_dispatch')::integer    as unit_sequence_in_call_dispatch,

        -- call description
        record->>'call_type'                                    as call_type,
        record->>'call_type_group'                              as call_type_group,   -- as delivered, not used yet
        record->>'call_final_disposition'                       as call_final_disposition,
        record->>'original_priority'                            as original_priority,
        record->>'priority'                                     as priority,
        record->>'final_priority'                               as final_priority,
        (record->>'als_unit')::boolean                          as als_unit,
        (record->>'number_of_alarms')::integer                  as number_of_alarms,

        -- dates
        (record->>'call_date')::timestamp::date                 as call_date,
        (record->>'watch_date')::timestamp::date                as watch_date,

        -- timestamps: local value as delivered + UTC instant
        {%- for c in ts_cols %}
        (record->>'{{ c }}')::timestamp                         as {{ c }},
        ((record->>'{{ c }}')::timestamp at time zone '{{ tz }}') as {{ c | replace('_dttm', '') }}_utc,
        {%- endfor %}

        -- location (neighbourhood level and coarser only)
        record->>'battalion'                                    as battalion_raw,
        record->>'station_area'                                 as station_area,
        record->>'box'                                          as box,
        record->>'fire_prevention_district'                     as fire_prevention_district,
        record->>'supervisor_district'                          as supervisor_district,
        record->>'neighborhoods_analysis_boundaries'            as area_raw,
        record->>'zipcode_of_incident'                          as zipcode_raw,
        record->>'city'                                         as city,              -- kept raw, not used

        -- source metadata
        (record->>'data_as_of')::timestamp                      as data_as_of,
        (record->>'data_loaded_at')::timestamp                  as data_loaded_at,

        -- Bronze position, for tracing a row back to its S3 file
        source_file,
        file_row,
        loaded_at                                               as bronze_loaded_at

    from in_period

),

cleaned as (

    select
        typed.*,

        class.service_class                                     as service_class,   -- NULL only if the seed lacks the type (test catches it)

        case when battalion_raw in (
                {%- for b in var('valid_battalions') %}'{{ b }}'{{ ',' if not loop.last }}{% endfor -%}
             ) then battalion_raw else 'Unknown' end            as battalion,

        regexp_replace(zipcode_raw, '\.0$', '')                 as zipcode_of_incident,

        coalesce(nullif(nullif(trim(area_raw), ''), 'None'), 'Unknown') as area,

        unit_type = 'PRIVATE'                                   as is_private_unit

    from typed
    left join {{ ref('call_type_class') }} class
           on class.call_type = typed.call_type

)

select
    rowid, call_number, incident_number, unit_id, unit_type, unit_sequence_in_call_dispatch,
    call_type, service_class, call_type_group, call_final_disposition,
    original_priority, priority, final_priority, als_unit, number_of_alarms,
    call_date, watch_date,
    {%- for c in ts_cols %}
    {{ c }}, {{ c | replace('_dttm', '') }}_utc,
    {%- endfor %}
    battalion, station_area, box, fire_prevention_district, supervisor_district,
    area, zipcode_of_incident, city,
    is_private_unit,

    -- timestamp-order checks: true = broken, false = in order, NULL = a time is missing.
    -- Equal times are allowed (strictly earlier only). Compared in UTC.
    on_scene_utc  < received_utc                            as is_on_scene_before_received,
    on_scene_utc  < dispatch_utc                            as is_on_scene_before_dispatch,
    dispatch_utc  < received_utc                            as is_dispatch_before_received,
    available_utc < dispatch_utc                            as is_available_before_dispatch,

    -- order validity per response-time metric: true / false / NULL (cannot check).
    -- Each metric depends only on its own two timestamps.
    not (on_scene_utc < received_utc)                       as is_call_to_arrival_order_valid,
    not (on_scene_utc < dispatch_utc)                       as is_dispatch_to_arrival_order_valid,

    data_as_of, data_loaded_at,
    source_file, file_row, bronze_loaded_at

from cleaned
