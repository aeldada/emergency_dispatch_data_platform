{#
  silver.police_call — one row per police call (key: cad_number).

  Steps, in order:
    1. keep only rows whose cad_number is exactly 9 digits (all years, before any filter)
    2. keep the newest version of each cad_number
       (newest data_loaded_at, then newest Bronze load time, then highest row in file)
    3. keep calls received on or after silver_start_date (local date)
    4. cast types; each timestamp keeps its local value and gains a UTC column
    5. clean codes: priority, area
    6. timestamp-order flags (a later step recorded earlier than the step before it)
  All onview_flag kinds are kept (N = 911 call, Y = officer-initiated, HSOC = 311 referral).
  Not carried: the two notes columns, pd_incident_report and the three intersection
  columns (free text and fine-grained location, not needed downstream).
#}

{%- set tz = var('source_timezone') -%}
{%- set ts_cols = ['received_datetime', 'entry_datetime', 'dispatch_datetime',
                   'enroute_datetime', 'onscene_datetime', 'close_datetime'] -%}

with bronze as (

    select record, source_file, file_row, loaded_at
    from {{ source('bronze', 'police_raw') }}

),

valid_id as (

    -- rows with an invalid call ID never reach Silver
    select *
    from bronze
    where record->>'cad_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}

),

newest_version as (

    select *
    from (
        select
            valid_id.*,
            row_number() over (
                partition by record->>'cad_number'
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
    where (record->>'received_datetime')::timestamp >= '{{ var("silver_start_date") }}'::date

),

typed as (

    select
        -- identifiers
        record->>'cad_number'                                   as cad_number,
        record->>'dup_cad_number'                               as dup_cad_number,     -- linked duplicate call, as delivered
        record->>'agency'                                       as agency,
        record->>'onview_flag'                                  as onview_flag,

        -- call description
        record->>'call_type_original'                           as call_type_original,
        record->>'call_type_original_desc'                      as call_type_original_desc,
        record->>'call_type_final'                              as call_type_final,
        record->>'call_type_final_desc'                         as call_type_final_desc,
        record->>'priority_original'                            as priority_original,
        record->>'priority_final'                               as priority_final_raw,
        record->>'disposition'                                  as disposition,        -- kept, not used in metrics
        (record->>'sensitive_call')::boolean                    as sensitive_call,

        -- timestamps: local value as delivered + UTC instant
        {%- for c in ts_cols %}
        (record->>'{{ c }}')::timestamp                         as {{ c }},
        ((record->>'{{ c }}')::timestamp at time zone '{{ tz }}') as {{ c | replace('_datetime', '') | replace('onscene', 'on_scene') }}_utc,
        {%- endfor %}

        -- location (neighbourhood level and coarser only)
        record->>'police_district'                              as police_district,
        record->>'supervisor_district'                          as supervisor_district,
        record->>'analysis_neighborhood'                        as area_raw,

        -- source metadata
        (record->>'data_as_of')::timestamp                      as data_as_of,
        (record->>'data_loaded_at')::timestamp                  as data_loaded_at,
        record->>'data_updated_at'                              as data_updated_at,    -- meaning not documented; not used
        record->>'source_filename'                              as source_filename,    -- publisher's extract file

        -- Bronze position, for tracing a row back to its S3 file
        source_file,
        file_row,
        loaded_at                                               as bronze_loaded_at

    from in_period

)

select
    cad_number, dup_cad_number, agency, onview_flag,
    call_type_original, call_type_original_desc, call_type_final, call_type_final_desc,
    priority_original,
    case
        when priority_final_raw is null then null   -- missing priority: handling not decided; a test reports it
        when priority_final_raw in (
            {%- for p in var('police_priorities') %}'{{ p }}'{{ ',' if not loop.last }}{% endfor -%}
        ) then priority_final_raw
        else 'Other'
    end                                                     as priority_final,
    disposition, sensitive_call,
    {%- for c in ts_cols %}
    {{ c }}, {{ c | replace('_datetime', '') | replace('onscene', 'on_scene') }}_utc,
    {%- endfor %}
    police_district, supervisor_district,
    coalesce(nullif(nullif(trim(area_raw), ''), 'None'), 'Unknown') as area,

    -- timestamp-order checks: true = broken, false = in order, NULL = a time is missing.
    -- Equal times are allowed (strictly earlier only). Compared in UTC.
    -- UTC name on_scene_utc matches fire_ems_unit (source column is onscene_datetime).
    -- close_datetime is not checked: it refers to the last unit, the others to the first.
    on_scene_utc < received_utc                              as is_on_scene_before_received,
    on_scene_utc < dispatch_utc                              as is_on_scene_before_dispatch,
    dispatch_utc < received_utc                             as is_dispatch_before_received,

    -- order validity per response-time metric: true / false / NULL (cannot check).
    not (on_scene_utc < received_utc)                        as is_call_to_arrival_order_valid,
    not (on_scene_utc < dispatch_utc)                        as is_dispatch_to_arrival_order_valid,

    data_as_of, data_loaded_at, data_updated_at, source_filename,
    source_file, file_row, bronze_loaded_at

from typed
