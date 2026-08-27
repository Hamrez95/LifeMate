-- #497: one canonical preview entry point dispatches only to reviewed adapters.

create or replace function analytics.preview_research_dataset(
  p_actor uuid,
  p_dataset_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path=analytics,admin,pg_temp
as $$
declare v_kind varchar;
begin
  if not admin.account_is_active_founder(p_actor) then
    raise exception using errcode='42501',message='research_founder_required';
  end if;
  select dataset_kind into v_kind from analytics.dataset_definitions where id=p_dataset_id;
  if v_kind is null then raise exception using errcode='P0002',message='research_dataset_not_found'; end if;
  if v_kind='HealthObservationAggregate' then
    return analytics.preview_research_health_observations(p_actor,p_dataset_id,p_jurisdiction);
  end if;
  raise exception using errcode='0A000',message='research_dataset_adapter_unavailable';
end $$;

revoke all on function analytics.preview_research_dataset(uuid,uuid,varchar) from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function analytics.preview_research_dataset(uuid,uuid,varchar) to lifemate_admin_runtime;
  end if;
end $$;
