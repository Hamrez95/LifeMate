alter table lifemate.user_profiles
    add column if not exists avatar_key character varying(32)
    not null default 'person_blue';

do $migration$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'ck_user_profiles_avatar_key'
          and conrelid = 'lifemate.user_profiles'::regclass
    ) then
        alter table lifemate.user_profiles
            add constraint ck_user_profiles_avatar_key check (
                avatar_key in (
                    'person_blue',
                    'person_green',
                    'person_purple',
                    'person_orange',
                    'heart_coral',
                    'caregiver_teal'
                )
            );
    end if;
end
$migration$;

comment on column lifemate.user_profiles.avatar_key is
'Non-sensitive allow-listed avatar identifier selected by the profile owner.';
