begin;

-- SECURITY DEFINER routines remain the only runtime path. Schema USAGE allows the
-- restricted role to resolve those functions; no table privileges are granted.
do $$
begin
  if exists (select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant usage on schema consent to lifemate_edge_runtime;
  end if;
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke usage on schema consent from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke usage on schema consent from authenticated;
  end if;
end
$$;

commit;
