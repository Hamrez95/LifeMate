begin;

alter table lifemate.user_profiles
  add column if not exists profile_photo_path character varying(512);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ck_user_profiles_profile_photo_path'
      and conrelid = 'lifemate.user_profiles'::regclass
  ) then
    alter table lifemate.user_profiles
      add constraint ck_user_profiles_profile_photo_path check (
        profile_photo_path is null
        or profile_photo_path ~
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](jpg|png|webp)$'
      );
  end if;
end $$;

commit;
