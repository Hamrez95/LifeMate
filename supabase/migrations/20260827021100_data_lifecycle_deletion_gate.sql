begin;

insert into security.retention_policy_versions(
  data_category,purpose_code,retention_days,grace_days,disposition,policy_version,status,legal_basis,effective_at_utc
)
select 'account_identity','deletion',null,0,'Delete',1,'Active','User-requested account deletion; grace is configurable by policy',now()
where not exists (
  select 1 from security.retention_policy_versions
  where data_category='account_identity' and purpose_code='deletion' and status='Active'
);

create or replace function identity.set_account_deletion_eligibility()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,identity,security,pg_temp
as $$
declare
  v_grace integer:=0;
  v_version bigint:=1;
begin
  select p.grace_days,p.policy_version
  into v_grace,v_version
  from security.retention_policy_for('account_identity','deletion') p
  limit 1;

  new.eligible_at_utc:=coalesce(new.eligible_at_utc,new.requested_at_utc + make_interval(days=>coalesce(v_grace,0)));
  if new.retention_policy_version is null or new.retention_policy_version in ('retention-v1','retention-v2') then
    new.retention_policy_version:='retention-v3.'||coalesce(v_version,1)::text;
  end if;
  return new;
end $$;

drop trigger if exists trg_account_deletion_eligibility on identity.account_deletion_requests;
create trigger trg_account_deletion_eligibility
before insert or update of requested_at_utc,eligible_at_utc on identity.account_deletion_requests
for each row execute function identity.set_account_deletion_eligibility();

create or replace function identity.account_deletion_block_until(p_account_id uuid)
returns timestamptz
language plpgsql
security definer
stable
set search_path=pg_catalog,identity,security,pg_temp
as $$
declare
  v_eligible timestamptz;
  v_hold_until timestamptz;
  v_has_indefinite boolean;
begin
  select max(coalesce(eligible_at_utc,requested_at_utc))
  into v_eligible
  from identity.account_deletion_requests
  where account_id=p_account_id and status in ('Requested','Processing');

  select
    bool_or(expires_at_utc is null),
    max(expires_at_utc)
  into v_has_indefinite,v_hold_until
  from security.retention_holds
  where account_id=p_account_id
    and status='Active'
    and (expires_at_utc is null or expires_at_utc>now());

  if coalesce(v_has_indefinite,false) then
    return now()+interval '100 years';
  end if;
  return greatest(coalesce(v_eligible,now()),coalesce(v_hold_until,now()));
end $$;

create or replace function integration.gate_account_deletion_outbox()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,integration,identity,security,pg_temp
as $$
declare v_block_until timestamptz;
begin
  if new.event_type='identity.account_deletion_requested' and new.aggregate_id is not null then
    v_block_until:=identity.account_deletion_block_until(new.aggregate_id);
    new.available_at_utc:=greatest(coalesce(new.available_at_utc,now()),coalesce(v_block_until,now()));
  end if;
  return new;
end $$;

drop trigger if exists trg_gate_account_deletion_outbox on integration.outbox_messages;
create trigger trg_gate_account_deletion_outbox
before insert or update of available_at_utc,status on integration.outbox_messages
for each row execute function integration.gate_account_deletion_outbox();

create or replace function security.refresh_account_deletion_outbox(p_account_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,security,identity,integration,pg_temp
as $$
declare v_block_until timestamptz;
begin
  v_block_until:=identity.account_deletion_block_until(p_account_id);
  update integration.outbox_messages
  set available_at_utc=greatest(now(),coalesce(v_block_until,now()))
  where aggregate_id=p_account_id
    and event_type='identity.account_deletion_requested'
    and status in ('Pending','Failed');
end $$;

create or replace function security.retention_hold_refresh_outbox()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,security,identity,integration,pg_temp
as $$
begin
  perform security.refresh_account_deletion_outbox(coalesce(new.account_id,old.account_id));
  return coalesce(new,old);
end $$;

drop trigger if exists trg_retention_hold_refresh_outbox on security.retention_holds;
create trigger trg_retention_hold_refresh_outbox
after insert or update or delete on security.retention_holds
for each row execute function security.retention_hold_refresh_outbox();

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
  end if;
  return new;
end $$;

drop trigger if exists trg_enforce_account_deletion_gate on identity.account_deletion_requests;
create trigger trg_enforce_account_deletion_gate
before update of status on identity.account_deletion_requests
for each row execute function identity.enforce_account_deletion_gate();

-- Preserve existing promised execution dates while upgrading version evidence.
update identity.account_deletion_requests r
set eligible_at_utc=coalesce(r.eligible_at_utc,r.requested_at_utc),
    retention_policy_version=case
      when r.retention_policy_version in ('retention-v1','retention-v2') then 'retention-v3.1'
      else r.retention_policy_version
    end
where r.status in ('Requested','Processing');

-- Existing unclaimed deletion messages must respect the new gate immediately.
update integration.outbox_messages m
set available_at_utc=greatest(m.available_at_utc,identity.account_deletion_block_until(m.aggregate_id))
where m.event_type='identity.account_deletion_requested'
  and m.status in ('Pending','Failed')
  and m.aggregate_id is not null;

revoke all on function identity.set_account_deletion_eligibility() from public;
revoke all on function identity.account_deletion_block_until(uuid) from public;
revoke all on function integration.gate_account_deletion_outbox() from public;
revoke all on function security.refresh_account_deletion_outbox(uuid) from public;
revoke all on function security.retention_hold_refresh_outbox() from public;
revoke all on function identity.enforce_account_deletion_gate() from public;
grant execute on function identity.account_deletion_block_until(uuid) to lifemate_worker_runtime;

commit;
