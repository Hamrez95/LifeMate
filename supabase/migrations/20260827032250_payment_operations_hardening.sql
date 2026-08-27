begin;

-- A provider-facing refund request must become durable async work without
-- pretending that the provider accepted or completed it. The worker receives
-- only the internal operation id and resolves provider configuration server-side.
create or replace function commerce.enqueue_refund_provider_submission()
returns trigger
language plpgsql
set search_path=pg_catalog,commerce,integration,pg_temp
as $$
begin
  if new.status='PendingProvider' then
    insert into integration.outbox_messages(
      aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
    ) values(
      'commerce_refund',new.id,'commerce.refund_provider_submission_requested',
      'commerce-refund-provider:'||new.id::text,
      jsonb_build_object('refundOperationId',new.id),
      'Pending',now()
    ) on conflict(idempotency_key) do nothing;
  end if;
  return new;
end
$$;

drop trigger if exists trg_refund_provider_submission_outbox on commerce.refund_operations;
create trigger trg_refund_provider_submission_outbox
after insert on commerce.refund_operations
for each row execute function commerce.enqueue_refund_provider_submission();

create or replace function commerce.enforce_refund_provider_evidence()
returns trigger
language plpgsql
set search_path=pg_catalog,commerce,pg_temp
as $$
begin
  if new.status='Succeeded' and new.provider_reference_hash is null then
    raise exception 'refund_success_requires_provider_reference';
  end if;
  if new.status='Failed' and (new.provider_error_code is null or length(trim(new.provider_error_code))=0) then
    raise exception 'refund_failure_requires_provider_error_code';
  end if;
  if new.provider_reference_hash is not null and length(new.provider_reference_hash)<>64 then
    raise exception 'refund_provider_reference_hash_invalid';
  end if;
  return new;
end
$$;

drop trigger if exists trg_refund_provider_evidence on commerce.refund_operations;
create trigger trg_refund_provider_evidence
before insert or update of status,provider_reference_hash,provider_error_code
on commerce.refund_operations
for each row execute function commerce.enforce_refund_provider_evidence();

-- Renewal intent is meaningful only while the subscription can still renew.
-- It never changes the paid period or entitlement itself.
create or replace function commerce.enforce_subscription_renewal_intent_state()
returns trigger
language plpgsql
set search_path=pg_catalog,commerce,pg_temp
as $$
begin
  if new.cancel_at_period_end is distinct from old.cancel_at_period_end
     or new.non_renewal_requested_at_utc is distinct from old.non_renewal_requested_at_utc
     or new.cancellation_reason_code is distinct from old.cancellation_reason_code
     or new.cancellation_reason_text is distinct from old.cancellation_reason_text then
    if old.status not in ('Trial','Active','PastDue') then
      raise exception 'subscription_renewal_intent_not_applicable';
    end if;
    if new.cancel_at_period_end and new.current_period_end_utc is null then
      raise exception 'subscription_period_end_required_for_non_renewal';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists trg_subscription_renewal_intent_state on commerce.subscriptions;
create trigger trg_subscription_renewal_intent_state
before update of cancel_at_period_end,non_renewal_requested_at_utc,cancellation_reason_code,cancellation_reason_text
on commerce.subscriptions
for each row execute function commerce.enforce_subscription_renewal_intent_state();

revoke all on function commerce.enqueue_refund_provider_submission() from public;
revoke all on function commerce.enforce_refund_provider_evidence() from public;
revoke all on function commerce.enforce_subscription_renewal_intent_state() from public;

do $$
begin
  if to_regrole('anon') is not null then
    revoke all on function commerce.enqueue_refund_provider_submission() from anon;
    revoke all on function commerce.enforce_refund_provider_evidence() from anon;
    revoke all on function commerce.enforce_subscription_renewal_intent_state() from anon;
  end if;
  if to_regrole('authenticated') is not null then
    revoke all on function commerce.enqueue_refund_provider_submission() from authenticated;
    revoke all on function commerce.enforce_refund_provider_evidence() from authenticated;
    revoke all on function commerce.enforce_subscription_renewal_intent_state() from authenticated;
  end if;
end
$$;

comment on function commerce.enqueue_refund_provider_submission() is
  'Durably queues provider refund work without asserting provider submission or success.';
comment on function commerce.enforce_refund_provider_evidence() is
  'Requires privacy-safe provider evidence before a refund can become terminal Succeeded/Failed.';
comment on function commerce.enforce_subscription_renewal_intent_state() is
  'Prevents renewal-intent mutation on terminal subscriptions and requires a known paid-period end before non-renewal.';

commit;
