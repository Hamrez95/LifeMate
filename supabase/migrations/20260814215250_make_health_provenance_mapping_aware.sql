-- Health observation provenance records the acting Account, not the legacy
-- AppUser UUID. The earlier rollout trigger copied owner_user_id directly into
-- recorded_by_account_id, which breaks once Account and AppUser IDs diverge.
-- Keep legacy writers compatible by resolving through the explicit identity
-- bridge and fail closed if a supplied legacy actor has no mapped Account.
create or replace function lifemate.populate_health_observation_provenance()
returns trigger
language plpgsql
set search_path = pg_catalog, identity, ecosystem, lifemate, pg_temp
as $$
declare
  v_application_code text;
begin
  if new.recorded_by_account_id is null and new.owner_user_id is not null then
    new.recorded_by_account_id :=
      identity.account_id_for_legacy_app_user(new.owner_user_id);

    if new.recorded_by_account_id is null then
      raise exception 'legacy_health_actor_account_missing';
    end if;
  end if;

  if new.source_application_id is null then
    v_application_code := lower(
      coalesce(nullif(btrim(new.source_provider), ''), 'wellmate')
    );

    select id
      into new.source_application_id
      from ecosystem.applications
     where code = v_application_code
       and status = 'Active'
     limit 1;

    -- The only historical writer at rollout was WellMate. Preserve that
    -- compatibility fallback without changing provenance for explicit writers.
    if new.source_application_id is null and new.owner_user_id is not null then
      select id
        into new.source_application_id
        from ecosystem.applications
       where code = 'wellmate'
         and status = 'Active'
       limit 1;
    end if;
  end if;

  return new;
end
$$;

revoke execute on function lifemate.populate_health_observation_provenance()
  from public;
