alter table lifemate.user_profiles
  add column if not exists wellmate_first_value_state varchar(16) null;

alter table lifemate.user_profiles
  drop constraint if exists ck_user_profiles_wellmate_first_value_state;

alter table lifemate.user_profiles
  add constraint ck_user_profiles_wellmate_first_value_state
  check (
    wellmate_first_value_state is null
    or wellmate_first_value_state in ('Skipped', 'Completed')
  );

comment on column lifemate.user_profiles.wellmate_first_value_state is
  'Optional WellMate first-value presentation state. Separate from notification permission and treatment data.';
