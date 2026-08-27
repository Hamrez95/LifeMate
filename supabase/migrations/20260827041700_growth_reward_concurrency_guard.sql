begin;

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
  perform pg_advisory_xact_lock(
    hashtextextended(
      'growth.reward.limit:'||new.beneficiary_account_id::text||':'||new.reward_rule_id::text,
      0
    )
  );

  select max_issues_per_account into v_limit
  from growth.reward_rules
  where id=new.reward_rule_id;

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

revoke all on function growth.enforce_reward_issue_limit()
  from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;

drop trigger if exists trg_growth_reward_issue_limit on growth.reward_events;
create trigger trg_growth_reward_issue_limit
before insert on growth.reward_events
for each row execute function growth.enforce_reward_issue_limit();

comment on function growth.enforce_reward_issue_limit()
is 'Serializes reward insertion by beneficiary/rule so max_issues_per_account remains a hard ceiling under concurrent requests.';

commit;
