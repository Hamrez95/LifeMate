-- Account is the stable LifeMate identity principal and must not depend on the
-- temporary legacy AppUser compatibility row. If that row is removed, retain
-- the Account and clear only the compatibility pointer.
do $migration$
begin
  if exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='identity'
      and t.relname='accounts'
      and c.conname='accounts_legacy_app_user_id_fkey'
  ) then
    alter table identity.accounts drop constraint accounts_legacy_app_user_id_fkey;
  end if;

  alter table identity.accounts
    add constraint accounts_legacy_app_user_id_fkey
    foreign key (legacy_app_user_id)
    references lifemate.app_users(id)
    on delete set null;
end
$migration$;

comment on column identity.accounts.legacy_app_user_id is
'Temporary compatibility pointer only. Account remains stable if the legacy AppUser row is removed.';
