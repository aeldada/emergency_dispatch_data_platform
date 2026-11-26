-- The three timestamp-order flags and the two order-validity flags agree with the
-- UTC timestamps: broken only when the later step is strictly earlier, NULL when a
-- time is missing, equal times not flagged. Returns rows where any flag disagrees.
select cad_number
from {{ ref('police_call') }}
where is_on_scene_before_received is distinct from (on_scene_utc < received_utc)
   or is_on_scene_before_dispatch is distinct from (on_scene_utc < dispatch_utc)
   or is_dispatch_before_received is distinct from (dispatch_utc < received_utc)
   or is_call_to_arrival_order_valid     is distinct from (case when on_scene_utc is null or received_utc is null then null else on_scene_utc >= received_utc end)
   or is_dispatch_to_arrival_order_valid is distinct from (case when on_scene_utc is null or dispatch_utc is null then null else on_scene_utc >= dispatch_utc end)
