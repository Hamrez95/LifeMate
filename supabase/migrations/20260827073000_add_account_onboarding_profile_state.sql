-- Canonical minimal account onboarding state for LifeMate V3.
--
-- This is presentation/profile state only. It must never be interpreted as a
-- healthcare authorization, consent grant, care relationship or entitlement.
-- Existing profiles are marked complete so established users never receive the
-- new-user onboarding after rollout/reinstall. Profiles created after this
-- migration remain incomplete until the user explicitly completes V3.

alter table lifemate.user_profiles
  add column if not exists presentation_intent varchar(24) null,
  add column if not exists onboarding_completed_at_utc timestamptz null;

alter table lifemate.user_profiles
  drop constraint if exists ck_user_profiles_presentation_intent;

alter table lifemate.user_profiles
  add constraint ck_user_profiles_presentation_intent
  check (
    presentation_intent is null
    or presentation_intent in ('Self', 'Caregiving', 'Both')
  );

-- Backward-compatible rollout: every profile that existed before V3 is treated
-- as already onboarded. New bootstrap rows created after this migration receive
-- the default NULL completion timestamp and therefore enter the minimal flow.
update lifemate.user_profiles
set onboarding_completed_at_utc = coalesce(
  onboarding_completed_at_utc,
  updated_at_utc,
  created_at_utc,
  now()
)
where onboarding_completed_at_utc is null;

comment on column lifemate.user_profiles.presentation_intent is
  'Non-authoritative LifeMate presentation intent (Self/Caregiving/Both). Never grants healthcare access or consent.';

comment on column lifemate.user_profiles.onboarding_completed_at_utc is
  'Server-authoritative completion marker for minimal account onboarding. Existing pre-V3 profiles are backfilled complete; new profiles default incomplete.';
