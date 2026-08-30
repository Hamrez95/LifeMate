begin;

alter table lifemate.women_calendar_daily_logs
  add column if not exists pain_recorded boolean not null default true;

comment on column lifemate.women_calendar_daily_logs.pain_recorded is
  'True when pain intensity was explicitly recorded by the owner. Allows rich period logs to omit pain without inventing a user observation while preserving legacy rows.';

commit;
