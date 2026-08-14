-- Provider-agnostic bridge resolvers are staged in their own migration so
-- subsequent PL/pgSQL trigger functions compile against already-existing
-- functions on a fresh PostgreSQL restore.
create or replace function identity.account_id_for_legacy_app_user(p_app_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, identity, pg_temp
as $$
  select a.id
  from identity.accounts a
  where a.legacy_app_user_id = p_app_user_id
    and a.status <> 'Deleted'
  order by a.created_at_utc,a.id
  limit 1
$$;

create or replace function core.self_person_id_for_legacy_app_user(p_app_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, identity, core, pg_temp
as $$
  select l.person_id
  from identity.accounts a
  join core.account_person_links l
    on l.account_id=a.id
   and l.link_type='Self'
   and l.status='Active'
  where a.legacy_app_user_id=p_app_user_id
    and a.status <> 'Deleted'
  order by l.created_at_utc,l.person_id
  limit 1
$$;

revoke all on function identity.account_id_for_legacy_app_user(uuid) from public;
revoke all on function core.self_person_id_for_legacy_app_user(uuid) from public;
grant execute on function identity.account_id_for_legacy_app_user(uuid)
  to lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function core.self_person_id_for_legacy_app_user(uuid)
  to lifemate_edge_runtime,lifemate_worker_runtime;
