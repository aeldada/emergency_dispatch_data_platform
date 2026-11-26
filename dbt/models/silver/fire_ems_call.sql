{#
  silver.fire_ems_call — one row per fire/EMS call (key: call_number).
  Built from silver.fire_ems_unit (already deduplicated, cast and cleaned).

  Steps, in order:
    1. rank the units of each call to find the first unit:
       the unit with unit_sequence_in_call_dispatch = 1; if the call has none,
       the unit with the earliest dispatch time; if still tied, the lowest rowid
    2. keep the first unit and carry the call-level fields from it
  Call-level fields (call type, priority, location, call times) are the same on
  every unit of a call; a test checks this on every run.
  Dispatch and on-scene times are the first unit's: they define the call's
  response times. Unit-only fields (unit id and type, later unit events,
  the broken-order flags) stay in silver.fire_ems_unit; first_unit_rowid links back.
  No durations here: they are computed in Gold.
#}

with units as (

    select * from {{ ref('fire_ems_unit') }}

),

ranked as (

    select
        units.*,
        row_number() over (
            partition by call_number
            order by case when unit_sequence_in_call_dispatch = 1 then 0 else 1 end,
                     dispatch_utc asc nulls last,
                     rowid asc
        ) as unit_rank
    from units

)

select
    -- identifiers
    call_number,
    incident_number,
    rowid                                as first_unit_rowid,

    -- dates
    call_date,
    watch_date,

    -- call times (same on every unit) and the first unit's dispatch and arrival
    received_dttm, received_utc,
    entry_dttm,    entry_utc,
    dispatch_dttm, dispatch_utc,
    on_scene_dttm, on_scene_utc,

    -- classification
    call_type,
    service_class,
    call_type_group,                     -- carried as delivered, not used
    final_priority,
    call_final_disposition,
    number_of_alarms,

    -- location for reporting
    battalion,
    station_area,
    fire_prevention_district,
    supervisor_district,
    area,
    zipcode_of_incident,

    -- from the first unit
    is_private_unit,
    is_call_to_arrival_order_valid,
    is_dispatch_to_arrival_order_valid

from ranked
where unit_rank = 1
