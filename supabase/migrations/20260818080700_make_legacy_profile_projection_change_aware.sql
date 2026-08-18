-- Keep legacy Profile compatibility projection from overwriting independently
-- newer canonical Person profile fields during staged AppUser -> Person retirement.
--
-- INSERT remains a full bootstrap. UPDATE projects only Person-facing fields
-- that actually changed in the legacy row; contact/version-only writes therefore
-- cannot roll canonical Person state back to stale legacy values.

create or replace function core.sync_legacy_user_profile()
returns trigger
language plpgsql
set search_path = pg_catalog, core, pg_temp
as $$
declare
  v_person_id uuid;
  v_person_fields_changed boolean;
begin
  v_person_id := core.self_person_id_for_legacy_app_user(new.user_id);
  if v_person_id is null then
    raise exception 'legacy_profile_self_person_missing';
  end if;

  if tg_op = 'INSERT' then
    insert into core.person_profiles(
      person_id, display_name, locale, time_zone, avatar_key,
      profile_photo_path, created_at_utc, updated_at_utc
    )
    values(
      v_person_id, new.display_name, new.locale, new.time_zone, new.avatar_key,
      new.profile_photo_path, new.created_at_utc, new.updated_at_utc
    )
    on conflict(person_id) do update set
      display_name = excluded.display_name,
      locale = excluded.locale,
      time_zone = excluded.time_zone,
      avatar_key = excluded.avatar_key,
      profile_photo_path = excluded.profile_photo_path,
      updated_at_utc = excluded.updated_at_utc;
    return new;
  end if;

  v_person_fields_changed :=
    new.display_name is distinct from old.display_name
    or new.locale is distinct from old.locale
    or new.time_zone is distinct from old.time_zone
    or new.avatar_key is distinct from old.avatar_key
    or new.profile_photo_path is distinct from old.profile_photo_path;

  insert into core.person_profiles(
    person_id, display_name, locale, time_zone, avatar_key,
    profile_photo_path, created_at_utc, updated_at_utc
  )
  values(
    v_person_id, new.display_name, new.locale, new.time_zone, new.avatar_key,
    new.profile_photo_path, new.created_at_utc, new.updated_at_utc
  )
  on conflict(person_id) do update set
    display_name = case
      when new.display_name is distinct from old.display_name
        then excluded.display_name
      else person_profiles.display_name
    end,
    locale = case
      when new.locale is distinct from old.locale then excluded.locale
      else person_profiles.locale
    end,
    time_zone = case
      when new.time_zone is distinct from old.time_zone then excluded.time_zone
      else person_profiles.time_zone
    end,
    avatar_key = case
      when new.avatar_key is distinct from old.avatar_key then excluded.avatar_key
      else person_profiles.avatar_key
    end,
    profile_photo_path = case
      when new.profile_photo_path is distinct from old.profile_photo_path
        then excluded.profile_photo_path
      else person_profiles.profile_photo_path
    end,
    updated_at_utc = case
      when v_person_fields_changed then excluded.updated_at_utc
      else person_profiles.updated_at_utc
    end;

  return new;
end
$$;
