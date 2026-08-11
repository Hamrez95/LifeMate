-- A synthetic, non-user-data capability table used only to prove that the
-- production Edge runtime is actually operating with its restricted database
-- identity and can exercise SELECT/INSERT/UPDATE/DELETE through RLS.
create table if not exists security.runtime_readiness_probe (
  id uuid primary key,
  marker varchar(80) not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);

insert into security.runtime_readiness_probe(id, marker)
values ('123e4567-e89b-42d3-a456-426614174888'::uuid, 'lifemate-readiness-seed')
on conflict (id) do update set marker=excluded.marker, updated_at_utc=now();

alter table security.runtime_readiness_probe enable row level security;
alter table security.runtime_readiness_probe force row level security;

drop policy if exists lifemate_edge_runtime_access
  on security.runtime_readiness_probe;
create policy lifemate_edge_runtime_access
  on security.runtime_readiness_probe
  for all
  to lifemate_edge_runtime
  using (true)
  with check (true);

revoke all on table security.runtime_readiness_probe from public;
grant select, insert, update, delete
  on security.runtime_readiness_probe
  to lifemate_edge_runtime;

do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on table security.runtime_readiness_probe from anon';
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on table security.runtime_readiness_probe from authenticated';
  end if;
end
$$;

comment on table security.runtime_readiness_probe is
  'Synthetic non-user-data table used by LifeMate readiness checks to exercise restricted runtime DML and RLS.';
