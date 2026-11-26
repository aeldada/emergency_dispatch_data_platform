{#
  quarantine.police_call_quarantine — police records that break a data rule.
  One row per record per broken rule. Rebuilt on every run; no history.

  Two parts, combined with union all:
    S1  (source_layer = bronze): every Bronze copy whose cad_number is not exactly
        9 digits (or missing), all years. These rows are not in Silver.
    S11 (source_layer = silver): every silver.police_call row with a broken timestamp
        order, one row per broken pair. These rows stay in Silver; this is a copy.
  record_data is the original Bronze JSON, taken from Bronze by source_file + file_row,
  never rebuilt from Silver values.
  quarantine_id is a hash of source_file, file_row and violation_code, so it is the
  same on every rebuild.
#}

{%- set s11_rules = [
    ('S11-P1', 'is_on_scene_before_received', 'On scene earlier than received'),
    ('S11-P2', 'is_on_scene_before_dispatch', 'On scene earlier than dispatched'),
    ('S11-P3', 'is_dispatch_before_received', 'Dispatched earlier than received'),
] -%}

with bronze as (

    select record, source_file, file_row, loaded_at
    from {{ source('bronze', 'police_raw') }}

),

invalid_id as (

    select
        'S1'                                              as violation_code,
        'Call ID is not exactly {{ var("id_length") }} digits' as violation_description,
        'bronze'                                          as source_layer,
        record->>'cad_number'                             as record_id,
        null::text                                        as source_record_id,
        source_file,
        file_row,
        loaded_at                                         as load_timestamp,
        record                                            as record_data
    from bronze
    where not coalesce(record->>'cad_number' ~ {{ "'^[0-9]{" ~ var('id_length') ~ "}$'" }}, false)

),

broken_order as (

    {%- for code, flag, text in s11_rules %}
    select
        '{{ code }}'                                      as violation_code,
        '{{ text }}'                                      as violation_description,
        'silver'                                          as source_layer,
        s.cad_number                                      as record_id,
        null::text                                        as source_record_id,
        s.source_file,
        s.file_row,
        s.bronze_loaded_at                                as load_timestamp,
        b.record                                          as record_data
    from {{ ref('police_call') }} s
    left join bronze b
           on b.source_file = s.source_file
          and b.file_row    = s.file_row
    where s.{{ flag }}
    {{ 'union all' if not loop.last }}
    {%- endfor %}

),

combined as (

    select * from invalid_id
    union all
    select * from broken_order

)

select
    md5(source_file || ':' || file_row::text || ':' || violation_code) as quarantine_id,
    record_id,
    source_record_id,
    source_layer,
    violation_code,
    violation_description,
    source_file,
    file_row,
    load_timestamp,
    current_timestamp                                     as quarantined_at,
    record_data
from combined
