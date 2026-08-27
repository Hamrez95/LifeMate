begin;

create or replace function growth.validate_reward_rule_config()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,growth,pg_temp
as $$
declare
  v_expiry timestamptz;
begin
  if new.reward_kind='GiftEntitlement' then
    if coalesce(new.reward_config->>'targetType','') not in ('Product','Offer')
       or coalesce(new.reward_config->>'targetId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(new.reward_config->>'expiresAtUtc','')='' then
      raise exception using errcode='22023',message='Gift entitlement reward config is invalid.';
    end if;
    begin
      v_expiry:=(new.reward_config->>'expiresAtUtc')::timestamptz;
    exception when invalid_datetime_format or datetime_field_overflow then
      raise exception using errcode='22023',message='Gift entitlement reward expiry is invalid.';
    end;
    if v_expiry<=now() then
      raise exception using errcode='22023',message='Gift entitlement reward expiry must be in the future.';
    end if;
  end if;
  return new;
end $$;

revoke all on function growth.validate_reward_rule_config() from public,anon,authenticated;
drop trigger if exists trg_growth_reward_rule_config on growth.reward_rules;
create trigger trg_growth_reward_rule_config
before insert or update of reward_kind,reward_config on growth.reward_rules
for each row execute function growth.validate_reward_rule_config();

alter function growth.execute_reward_issue(uuid,uuid,varchar,uuid,uuid,bigint,varchar,uuid,bigint,varchar,uuid,varchar,varchar)
  set search_path=pg_catalog,growth,admin,commerce,identity,extensions,pg_temp;

revoke all on function growth.preview_reward_issue(uuid,varchar,uuid,uuid,bigint,varchar) from lifemate_edge_runtime;
revoke all on function growth.upsert_reward_rule(uuid,uuid,varchar,varchar,varchar,jsonb,integer,varchar,bigint,varchar,uuid,varchar,varchar) from lifemate_edge_runtime;
revoke all on function growth.review_advocacy_submission(uuid,uuid,bigint,varchar,varchar,uuid,varchar,varchar) from lifemate_edge_runtime;
revoke all on function growth.execute_reward_issue(uuid,uuid,varchar,uuid,uuid,bigint,varchar,uuid,bigint,varchar,uuid,varchar,varchar) from lifemate_edge_runtime;

comment on function growth.validate_reward_rule_config()
is 'Database-side validation for reward configs. Prevents malformed or already-expired GiftEntitlement rules even when application validation is bypassed.';

commit;
