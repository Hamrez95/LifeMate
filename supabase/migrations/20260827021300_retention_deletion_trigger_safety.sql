begin;

create or replace function identity.account_deletion_execution_eligibility(p_request_id uuid)
returns table(eligible boolean,code character varying,next_eligible_at_utc timestamptz)
language plpgsql
security definer
stable
set search_path=pg_catalog,identity,security,pg_temp
as $$
declare
  v_request identity.account_deletion_requests%rowtype;
  v_hold_until timestamptz;
  v_has_indefinite boolean;
begin
  select * into v_request
  from identity.account_deletion_requests
  where id=p_request_id;

  if not found then
    return query select false,'deletion_request_not_found'::varchar,null::timestamptz;
    return;
  end if;
  if v_request.status='Completed' then
    return query select false,'deletion_already_completed'::varchar,null::timestamptz;
    return;
  end if;
  if v_request.status not in ('Requested','Processing') then
    return query select false,'deletion_request_not_processable'::varchar,null::timestamptz;
    return;
  end if;

  select
    bool_or(expires_at_utc is null),
    max(expires_at_utc)
  into v_has_indefinite,v_hold_until
  from security.retention_holds
  where account_id=v_request.account_id
    and status='Active'
    and (expires_at_utc is null or expires_at_utc>now());

  if coalesce(v_has_indefinite,false) then
    return query select false,'retention_hold_active'::varchar,null::timestamptz;
    return;
  end if;
  if v_hold_until is not null and v_hold_until>now() then
    return query select false,'retention_hold_active'::varchar,v_hold_until;
    return;
  end if;
  if coalesce(v_request.eligible_at_utc,v_request.requested_at_utc)>now() then
    return query select false,'deletion_grace_active'::varchar,coalesce(v_request.eligible_at_utc,v_request.requested_at_utc);
    return;
  end if;

  return query select true,'eligible'::varchar,null::timestamptz;
end $$;

create or replace function identity.enforce_account_deletion_gate()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,identity,security,pg_temp
as $$
declare
  v_eligible record;
begin
  if new.status='Processing' then
    select * into v_eligible from identity.account_deletion_execution_eligibility(new.id);
    if v_eligible.eligible is distinct from true then
      raise exception '%',coalesce(v_eligible.code,'deletion_not_eligible');
    end if;
    new.last_attempt_at_utc:=now();
    new.attempt_count:=old.attempt_count+1;
    new.next_attempt_at_utc:=null;
  end if;
  return new;
end $$;

revoke all on function identity.account_deletion_execution_eligibility(uuid) from public;
revoke all on function identity.enforce_account_deletion_gate() from public;
grant execute on function identity.account_deletion_execution_eligibility(uuid) to lifemate_worker_runtime;

commit;
