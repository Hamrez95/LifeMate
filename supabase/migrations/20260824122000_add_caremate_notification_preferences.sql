alter table lifemate.care_relationships
  add column if not exists caregiver_notifications_enabled boolean not null default true,
  add column if not exists caregiver_missed_alerts_enabled boolean not null default true,
  add column if not exists caregiver_completion_mode character varying(24) not null default 'off',
  add column if not exists caregiver_care_events_enabled boolean not null default true,
  add column if not exists caregiver_daily_summary_enabled boolean not null default false,
  add column if not exists caregiver_daily_summary_local_time time without time zone not null default '20:00',
  add column if not exists caregiver_lock_screen_detail character varying(16) not null default 'limited';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'CK_care_relationships_completion_mode'
  ) then
    alter table lifemate.care_relationships
      add constraint "CK_care_relationships_completion_mode"
      check (caregiver_completion_mode in ('all','important','after_missed','daily_summary','off'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'CK_care_relationships_lock_screen_detail'
  ) then
    alter table lifemate.care_relationships
      add constraint "CK_care_relationships_lock_screen_detail"
      check (caregiver_lock_screen_detail in ('full','limited','hidden'));
  end if;
end $$;
