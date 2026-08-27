alter table lifemate.women_calendar_profiles
  add column if not exists cycle_length_known boolean null,
  add column if not exists period_length_known boolean null,
  add column if not exists regularity varchar(16) null;

alter table lifemate.women_calendar_profiles
  drop constraint if exists ck_women_calendar_regularity;

alter table lifemate.women_calendar_profiles
  add constraint ck_women_calendar_regularity
  check (
    regularity is null
    or regularity in ('Regular', 'Irregular', 'Unknown')
  );

-- Existing profiles pre-date explicit V3 uncertainty metadata. Their stored
-- numeric values remain authoritative, while regularity stays unknown rather
-- than being inferred from health data.
update lifemate.women_calendar_profiles
set cycle_length_known = true,
    period_length_known = true,
    regularity = coalesce(regularity, 'Unknown')
where cycle_length_known is null
   or period_length_known is null
   or regularity is null;

comment on column lifemate.women_calendar_profiles.cycle_length_known is
  'Whether cycle_length was explicitly known by the owner. False means the numeric compatibility value must not be presented as user-known truth.';
comment on column lifemate.women_calendar_profiles.period_length_known is
  'Whether period_length was explicitly known by the owner. False represents the V3 unsure choice.';
comment on column lifemate.women_calendar_profiles.regularity is
  'Owner-reported cycle regularity only. Never inferred as fertility or healthcare authorization.';
