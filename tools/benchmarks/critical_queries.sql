\set ON_ERROR_STOP on
\timing on

-- Login identity lookup: unique(provider,issuer,provider_subject).
explain (analyze,buffers)
select account_id
from identity.external_identities
where provider='supabase_auth' and issuer='benchmark' and provider_subject='bench-subject-1';

-- Account -> Person.
explain (analyze,buffers)
select person_id,link_type,status
from core.account_person_links
where account_id=md5('acct-1')::uuid and status='Active';

-- Current CareMate relationship list during compatibility.
explain (analyze,buffers)
select id,patient_user_id,status,can_view_women_calendar
from lifemate.care_relationships
where caregiver_user_id=md5('acct-2')::uuid and status='Active'
order by created_at_utc desc,id desc
limit 50;

-- New active grants / scope resolution.
explain (analyze,buffers)
select g.id,g.subject_person_id,s.scope
from security.access_grants g
join security.access_grant_scopes s on s.grant_id=g.id
where g.grantee_account_id=md5('acct-2')::uuid
  and g.status='Active'
  and (g.expires_at_utc is null or g.expires_at_utc>now())
order by g.subject_person_id,g.id
limit 100;

-- Today's doses for a Person.
explain (analyze,buffers)
select id,treatment_plan_id,scheduled_at_utc,status
from lifemate.dose_occurrences
where patient_person_id=md5('acct-1')::uuid
  and scheduled_local_date=current_date
order by scheduled_at_utc,id
limit 100;

-- Pending dose cursor query.
explain (analyze,buffers)
select id,scheduled_at_utc,status
from lifemate.dose_occurrences
where patient_person_id=md5('acct-1')::uuid
  and status='Scheduled'
  and scheduled_at_utc>now()
order by scheduled_at_utc,id
limit 100;

-- Medication history / list.
explain (analyze,buffers)
select id,name,updated_at_utc
from lifemate.medications
where owner_person_id=md5('acct-1')::uuid
order by updated_at_utc desc,id desc
limit 100;

-- Adherence timeline by occurrence.
explain (analyze,buffers)
select id,event_type,resulting_status,recorded_at_utc
from lifemate.dose_adherence_events
where occurrence_id=md5('dose-1')::uuid
order by recorded_at_utc,id
limit 100;

-- Rebuildable dashboard read model.
explain (analyze,buffers)
select scheduled_count,taken_count,missed_count,late_count
from care.daily_adherence_summary
where person_id=md5('acct-1')::uuid and summary_date=current_date;

-- Women-health recent logs (private_notes intentionally not projected here).
explain (analyze,buffers)
select id,logged_on,mood,energy_level,pain_level,share_summary_with_companion
from lifemate.women_calendar_daily_logs
where owner_person_id=md5('acct-1')::uuid
order by logged_on desc,id desc
limit 90;

-- Latest versioned care-sharing consent.
explain (analyze,buffers)
select id,status,granted_at_utc,revoked_at_utc,expires_at_utc
from consent.consent_records
where subject_person_id=md5('acct-1')::uuid and purpose='care_sharing'
order by created_at_utc desc,id desc
limit 1;

-- Audit resource history.
explain (analyze,buffers)
select id,actor_user_id,action,created_at_utc
from lifemate.audit_logs
where resource_type='dose_occurrence' and resource_id=md5('dose-1')::uuid
order by created_at_utc desc,id desc
limit 100;
