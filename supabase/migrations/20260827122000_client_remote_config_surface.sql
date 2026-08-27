begin;

alter table platform.controls
  add column if not exists client_exposed boolean not null default false;

comment on column platform.controls.client_exposed is
  'Explicit allow-list boundary for values safe to return to authenticated mobile clients. Server-only controls remain false.';

insert into platform.controls(
  control_key, control_kind, value_type, default_value, description,
  fail_closed, status, version, client_exposed
) values
  ('client.women_calendar.enabled','FeatureFlag','Boolean','true'::jsonb,
   'Client-side Women Health visibility kill switch. Authorization and consent remain server-side.',
   true,'Active',1,true),
  ('client.care_pairing.enabled','FeatureFlag','Boolean','true'::jsonb,
   'Client-side CareMate pairing visibility kill switch. Relationship authorization remains server-side.',
   true,'Active',1,true)
on conflict (control_key) do update set
  client_exposed=true,
  updated_at_utc=now();

create or replace function platform.client_control_evaluations(
  p_app_user_id uuid,
  p_product varchar,
  p_beta boolean default false
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, platform, identity
as $$
declare
  v_account_id uuid;
  v_result jsonb;
begin
  if p_product not in ('wellmate','caremate') then
    raise exception 'product_invalid' using errcode='22023';
  end if;

  select identity.account_id_for_legacy_app_user(p_app_user_id)
    into v_account_id;
  if v_account_id is null then
    raise exception 'account_not_found' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'key', c.control_key,
      'kind', c.control_kind,
      'valueType', c.value_type,
      'value', coalesce(m.value,
        case
          when c.fail_closed and c.control_kind='FeatureFlag'
               and jsonb_typeof(c.default_value) <> 'boolean'
            then 'false'::jsonb
          else c.default_value
        end),
      'definitionVersion', c.version,
      'source', case when m.id is null then 'default' else 'rule' end,
      'ruleVersion', m.version,
      'failClosed', c.fail_closed
    ) order by c.control_key
  ), '[]'::jsonb)
  into v_result
  from platform.controls c
  left join lateral (
    select r.id, r.value, r.version
    from platform.control_rules r
    where r.control_key=c.control_key
      and r.status='Active'
      and (r.starts_at_utc is null or r.starts_at_utc <= now())
      and (r.ends_at_utc is null or r.ends_at_utc > now())
      and (
        r.target_type='Global'
        or (r.target_type='Product' and r.target_key=p_product)
        or (r.target_type='Beta' and p_beta=true and r.target_key='beta')
        or (r.target_type='Account' and r.target_key=v_account_id::text)
        or (
          r.target_type='Percentage'
          and (
            (('x' || substr(md5(c.control_key || ':' || v_account_id::text),1,8))::bit(32)::bigint % 10000)
            < coalesce(r.rollout_basis_points,0)
          )
        )
      )
      -- Segment targeting is intentionally not trusted from client input. It is
      -- ignored until canonical server-side segment membership exists.
      and r.target_type <> 'Segment'
    order by r.priority, r.id
    limit 1
  ) m on true
  where c.status='Active' and c.client_exposed=true;

  return v_result;
end;
$$;

revoke all on function platform.client_control_evaluations(uuid,varchar,boolean)
  from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function platform.client_control_evaluations(uuid,varchar,boolean) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function platform.client_control_evaluations(uuid,varchar,boolean) from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant usage on schema platform to lifemate_edge_runtime;
    grant execute on function platform.client_control_evaluations(uuid,varchar,boolean)
      to lifemate_edge_runtime;
  end if;
end
$$;

commit;
