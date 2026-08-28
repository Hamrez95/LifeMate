-- #107/#106 Durable server-side notification dedup.
-- Notification guidance IDs are metadata only. They contain no mood value,
-- symptom, note, pain, diagnosis, fertility data, or rendered notification copy.

-- Keep the earliest receipt if pre-existing retries created duplicate rows before
-- this constraint was introduced. Generic in-app guidance is intentionally not
-- affected because it may legitimately reappear after its cooldown window.
with ranked as (
  select id,
         row_number() over (
           partition by relationship_id, caregiver_person_id, patient_person_id, guidance_id
           order by shown_at_utc asc, id asc
         ) as rn
  from lifemate.women_companion_guidance_history
  where guidance_id like 'notify.%'
)
delete from lifemate.women_companion_guidance_history h
using ranked r
where h.id = r.id and r.rn > 1;

-- A retry of the same concrete notification must never create a second receipt.
create unique index if not exists ux_companion_notification_guidance_once
  on lifemate.women_companion_guidance_history(
    relationship_id,
    caregiver_person_id,
    patient_person_id,
    guidance_id
  )
  where guidance_id like 'notify.%';

-- A shared daily check-in may be edited from low mood to low energy (or vice
-- versa). Both IDs end with the same canonical YYYY-MM-DD date. Permit at most
-- one wellbeing notification per relationship/person/day so edits cannot fan
-- out into contradictory notifications.
with ranked as (
  select id,
         row_number() over (
           partition by relationship_id, caregiver_person_id, patient_person_id,
                        right(guidance_id, 10)
           order by shown_at_utc asc, id asc
         ) as rn
  from lifemate.women_companion_guidance_history
  where guidance_id like 'notify.mood.%'
)
delete from lifemate.women_companion_guidance_history h
using ranked r
where h.id = r.id and r.rn > 1;

create unique index if not exists ux_companion_mood_notification_person_day
  on lifemate.women_companion_guidance_history(
    relationship_id,
    caregiver_person_id,
    patient_person_id,
    right(guidance_id, 10)
  )
  where guidance_id like 'notify.mood.%';

comment on index lifemate.ux_companion_notification_guidance_once is
  'Server-side idempotency boundary for concrete companion notifications.';
comment on index lifemate.ux_companion_mood_notification_person_day is
  'At most one explicitly shared wellbeing notification per relationship/person/day.';
