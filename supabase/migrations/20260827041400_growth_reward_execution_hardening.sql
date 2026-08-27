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

create or replace function growth.enforce_reward_issue_limit()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,growth,pg_temp
as $$
declare
  v_limit integer;
  v_count bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('growth.reward.limit:'||new.beneficiary_account_id::text||':'||new.reward_rule_id::text,0));
  select max_issues_per_account into v_limit from growth.reward_rules where id=new.reward_rule_id;
  if v_limit is not null and new.status in ('Pending','Issued') then
    select count(*) into v_count
    from growth.reward_events e
    where e.beneficiary_account_id=new.beneficiary_account_id
      and e.reward_rule_id=new.reward_rule_id
      and e.status in ('Pending','Issued');
    if v_count>=v_limit then
      raise exception using errcode='55000',message='Reward account limit has been reached.';
    end if;
  end if;
  return new;
end $$;

revoke all on function growth.enforce_reward_issue_limit() from public,anon,authenticated;
drop trigger if exists trg_growth_reward_issue_limit on growth.reward_events;
create trigger trg_growth_reward_issue_limit
before insert on growth.reward_events
for each row execute function growth.enforce_reward_issue_limit();

alter function growth.execute_reward_issue(uuid,uuid,varchar,uuid,uuid,bigint,varchar,uuid,bigint,varchar,uuid,varchar,varchar)
  set search_path=pg_catalog,growth,admin,commerce,identity,extensions,pg_temp;

revoke all on function growth.preview_reward_issue(uuid,varchar,uuid,uuid,bigint,varchar) from lifemate_edge_runtime;
revoke all on function growth.upsert_reward_rule(uuid,uuid,varchar,varchar,varchar,jsonb,integer,varchar,bigint,varchar,uuid,varchar,varchar) from lifemate_edge_runtime;
revoke all on function growth.review_advocacy_submission(uuid,uuid,bigint,varchar,varchar,uuid,varchar,varchar) from lifemate_edge_runtime;
revoke all on function growth.execute_reward_issue(uuid,uuid,varchar,uuid,uuid,bigint,varchar,uuid,bigint,varchar,uuid,varchar,varchar) from lifemate_edge_runtime;

comment on function growth.validate_reward_rule_config()
is 'Database-side validation for reward configs. Prevents malformed or already-expired GiftEntitlement rules even when application validation is bypassed.';
comment on function growth.enforce_reward_issue_limit()
is 'Serializes reward insertion per beneficiary/rule so max_issues_per_account remains a hard ceiling under concurrent issuance.';

commit;
