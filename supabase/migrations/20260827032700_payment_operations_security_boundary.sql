begin;

-- #493 is an Admin control-plane surface. The generic Edge runtime cannot bind
-- the caller-supplied actor UUID to an authenticated subject, so exposing the
-- Admin/User multiplexed renewal function there would permit actor spoofing.
-- A user-owned cancellation flow must use a dedicated auth-bound entrypoint.
revoke execute on function commerce.set_subscription_renewal_intent_v2(
  uuid,character varying,uuid,bigint,boolean,character varying,character varying,
  uuid,character varying,character varying
) from lifemate_edge_runtime;

grant execute on function commerce.set_subscription_renewal_intent_v2(
  uuid,character varying,uuid,bigint,boolean,character varying,character varying,
  uuid,character varying,character varying
) to lifemate_admin_runtime;

-- elevated_access is reserved for the explicit elevated-health/break-glass
-- capability. Ordinary high-risk commerce operations are audited, but are not
-- elevated-health accesses. Normalize these exact actions at the ledger edge so
-- older function bodies cannot misclassify the audit record.
create or replace function admin.enforce_commerce_audit_elevation_semantics()
returns trigger
language plpgsql
security invoker
set search_path=pg_catalog,admin,pg_temp
as $$
begin
  if new.action in (
    'commerce.refund.execute',
    'commerce.reconciliation.open',
    'commerce.reconciliation.correct'
  ) then
    new.elevated_access:=false;
  end if;
  return new;
end
$$;

drop trigger if exists trg_commerce_audit_elevation_semantics on admin.audit_events;
create trigger trg_commerce_audit_elevation_semantics
before insert on admin.audit_events
for each row execute function admin.enforce_commerce_audit_elevation_semantics();

revoke all on function admin.enforce_commerce_audit_elevation_semantics()
  from public,anon,authenticated;

comment on function admin.enforce_commerce_audit_elevation_semantics() is
  'Keeps ordinary high-risk commerce audit events distinct from elevated-health/break-glass access evidence.';

commit;
