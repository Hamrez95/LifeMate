begin;

create table if not exists commerce.refund_requests (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references commerce.transactions(id) on delete restrict,
  requested_by_account_id uuid not null references admin.members(account_id) on delete restrict,
  status text not null default 'PendingReview' check (status in (
    'PendingReview', 'Approved', 'Rejected', 'Cancelled', 'Submitted', 'Succeeded', 'Failed'
  )),
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  reason character varying(1000) not null check (length(trim(reason)) between 10 and 1000),
  requested_at_utc timestamptz not null default now(),
  reviewed_by_account_id uuid null references admin.members(account_id) on delete restrict,
  reviewed_at_utc timestamptz null,
  resolution_reason character varying(1000) null,
  updated_at_utc timestamptz not null default now(),
  check (
    (reviewed_at_utc is null and reviewed_by_account_id is null)
    or (reviewed_at_utc is not null and reviewed_by_account_id is not null)
  )
);

create index if not exists idx_commerce_refund_requests_transaction_time
  on commerce.refund_requests (transaction_id, requested_at_utc desc, id desc);

create unique index if not exists uq_commerce_refund_requests_active_transaction
  on commerce.refund_requests (transaction_id)
  where status in ('PendingReview', 'Approved', 'Submitted');

comment on table commerce.refund_requests is
  'Human-review refund workflow requests. Creating a request does not execute a provider refund or change normalized transaction state.';

revoke all on commerce.refund_requests from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on commerce.refund_requests from anon';
  end if;

  if to_regrole('authenticated') is not null then
    execute 'revoke all on commerce.refund_requests from authenticated';
  end if;
end
$$;

grant select on commerce.refund_requests to lifemate_admin_runtime;

create or replace function admin.request_commerce_transaction_refund(
  p_actor_account_id uuid,
  p_transaction_id uuid,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, commerce, pg_temp
as $$
declare
  v_operation constant character varying := 'commerce.transaction.refund.request';
  v_existing admin.idempotency_keys%rowtype;
  v_transaction_status text;
  v_amount_minor bigint;
  v_currency text;
  v_refund_request_id uuid;
  v_response jsonb;
begin
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object(
      'httpStatus', 400,
      'code', 'refund_reason_invalid',
      'message', 'A refund workflow reason between 10 and 1000 characters is required.',
      'replayed', false
    );
  end if;

  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object(
      'httpStatus', 400,
      'code', 'idempotency_invalid',
      'message', 'Idempotency metadata is invalid.',
      'replayed', false
    );
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key, 0)
  );

  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object(
        'httpStatus', 409,
        'code', 'idempotency_conflict',
        'message', 'This Idempotency-Key was already used for a different request.',
        'replayed', false
      );
    end if;

    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed', true);
    end if;

    return jsonb_build_object(
      'httpStatus', 409,
      'code', 'idempotency_in_progress',
      'message', 'The matching refund workflow request is still being processed.',
      'replayed', false
    );
  end if;

  insert into admin.idempotency_keys(
    actor_account_id,
    operation,
    idempotency_key,
    request_hash,
    status
  ) values (
    p_actor_account_id,
    v_operation,
    p_idempotency_key,
    p_request_hash,
    'Processing'
  );

  if not admin.account_has_permission(p_actor_account_id, 'commerce.refund') then
    v_response := jsonb_build_object(
      'httpStatus', 403,
      'code', 'permission_denied',
      'message', 'The required permission is not granted.',
      'replayed', false
    );

    insert into admin.audit_events(
      actor_account_id,
      action,
      resource_type,
      resource_id,
      result,
      reason,
      correlation_id,
      request_id,
      elevated_access,
      metadata_json
    ) values (
      p_actor_account_id,
      'commerce.transaction.refund.request',
      'commerce_transaction',
      p_transaction_id::text,
      'Denied',
      'Missing commerce.refund permission',
      p_correlation_id,
      p_idempotency_key,
      false,
      jsonb_build_object('workflow', 'HumanReview')
    );

    update admin.idempotency_keys
    set status = 'Completed',
        response_status = 403,
        response_json = v_response,
        updated_at_utc = now()
    where actor_account_id = p_actor_account_id
      and operation = v_operation
      and idempotency_key = p_idempotency_key;

    return v_response;
  end if;

  select normalized_status, amount_minor, currency
    into v_transaction_status, v_amount_minor, v_currency
  from commerce.transactions
  where id = p_transaction_id
  for update;

  if not found then
    v_response := jsonb_build_object(
      'httpStatus', 404,
      'code', 'commerce_transaction_not_found',
      'message', 'Commerce transaction was not found.',
      'replayed', false
    );

    insert into admin.audit_events(
      actor_account_id,
      action,
      resource_type,
      resource_id,
      result,
      reason,
      correlation_id,
      request_id,
      elevated_access,
      metadata_json
    ) values (
      p_actor_account_id,
      'commerce.transaction.refund.request',
      'commerce_transaction',
      p_transaction_id::text,
      'Denied',
      'Transaction not found',
      p_correlation_id,
      p_idempotency_key,
      false,
      jsonb_build_object('workflow', 'HumanReview')
    );

    update admin.idempotency_keys
    set status = 'Completed',
        response_status = 404,
        response_json = v_response,
        updated_at_utc = now()
    where actor_account_id = p_actor_account_id
      and operation = v_operation
      and idempotency_key = p_idempotency_key;

    return v_response;
  end if;

  if v_transaction_status <> 'Succeeded' then
    v_response := jsonb_build_object(
      'httpStatus', 409,
      'code', 'refund_not_eligible',
      'message', 'Only a succeeded transaction can enter the refund review workflow.',
      'transactionId', p_transaction_id,
      'transactionStatus', v_transaction_status,
      'replayed', false
    );

    insert into admin.audit_events(
      actor_account_id,
      action,
      resource_type,
      resource_id,
      result,
      reason,
      correlation_id,
      request_id,
      elevated_access,
      metadata_json
    ) values (
      p_actor_account_id,
      'commerce.transaction.refund.request',
      'commerce_transaction',
      p_transaction_id::text,
      'Denied',
      'Transaction status is not eligible for refund review',
      p_correlation_id,
      p_idempotency_key,
      false,
      jsonb_build_object(
        'workflow', 'HumanReview',
        'transactionStatus', v_transaction_status
      )
    );

    update admin.idempotency_keys
    set status = 'Completed',
        response_status = 409,
        response_json = v_response,
        updated_at_utc = now()
    where actor_account_id = p_actor_account_id
      and operation = v_operation
      and idempotency_key = p_idempotency_key;

    return v_response;
  end if;

  select id into v_refund_request_id
  from commerce.refund_requests
  where transaction_id = p_transaction_id
    and status in ('PendingReview', 'Approved', 'Submitted')
  order by requested_at_utc desc, id desc
  limit 1;

  if found then
    v_response := jsonb_build_object(
      'httpStatus', 409,
      'code', 'refund_workflow_already_active',
      'message', 'An active refund workflow already exists for this transaction.',
      'transactionId', p_transaction_id,
      'refundRequestId', v_refund_request_id,
      'transactionStatus', v_transaction_status,
      'replayed', false
    );

    insert into admin.audit_events(
      actor_account_id,
      action,
      resource_type,
      resource_id,
      result,
      reason,
      correlation_id,
      request_id,
      elevated_access,
      metadata_json
    ) values (
      p_actor_account_id,
      'commerce.transaction.refund.request',
      'commerce_transaction',
      p_transaction_id::text,
      'Denied',
      'Active refund workflow already exists',
      p_correlation_id,
      p_idempotency_key,
      false,
      jsonb_build_object(
        'workflow', 'HumanReview',
        'refundRequestId', v_refund_request_id
      )
    );

    update admin.idempotency_keys
    set status = 'Completed',
        response_status = 409,
        response_json = v_response,
        updated_at_utc = now()
    where actor_account_id = p_actor_account_id
      and operation = v_operation
      and idempotency_key = p_idempotency_key;

    return v_response;
  end if;

  insert into commerce.refund_requests(
    transaction_id,
    requested_by_account_id,
    status,
    amount_minor,
    currency,
    reason
  ) values (
    p_transaction_id,
    p_actor_account_id,
    'PendingReview',
    v_amount_minor,
    v_currency,
    trim(p_reason)
  )
  returning id into v_refund_request_id;

  insert into admin.audit_events(
    actor_account_id,
    action,
    resource_type,
    resource_id,
    result,
    reason,
    correlation_id,
    request_id,
    elevated_access,
    metadata_json
  ) values (
    p_actor_account_id,
    'commerce.transaction.refund.request',
    'commerce_transaction',
    p_transaction_id::text,
    'Succeeded',
    trim(p_reason),
    p_correlation_id,
    p_idempotency_key,
    false,
    jsonb_build_object(
      'workflow', 'HumanReview',
      'refundRequestId', v_refund_request_id,
      'transactionStatus', v_transaction_status,
      'amountMinor', v_amount_minor::text,
      'currency', v_currency
    )
  );

  v_response := jsonb_build_object(
    'httpStatus', 201,
    'code', 'ok',
    'transactionId', p_transaction_id,
    'refundRequestId', v_refund_request_id,
    'status', 'PendingReview',
    'amountMinor', v_amount_minor::text,
    'currency', v_currency,
    'transactionStatus', v_transaction_status,
    'replayed', false
  );

  update admin.idempotency_keys
  set status = 'Completed',
      response_status = 201,
      response_json = v_response,
      updated_at_utc = now()
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key;

  return v_response;
end
$$;

revoke all on function admin.request_commerce_transaction_refund(
  uuid, uuid, character varying, uuid, character varying, character varying
) from public;

do $$
begin
  if to_regrole('anon') is not null then
    revoke all on function admin.request_commerce_transaction_refund(
      uuid, uuid, character varying, uuid, character varying, character varying
    ) from anon;
  end if;

  if to_regrole('authenticated') is not null then
    revoke all on function admin.request_commerce_transaction_refund(
      uuid, uuid, character varying, uuid, character varying, character varying
    ) from authenticated;
  end if;
end
$$;

grant execute on function admin.request_commerce_transaction_refund(
  uuid, uuid, character varying, uuid, character varying, character varying
) to lifemate_admin_runtime;

comment on function admin.request_commerce_transaction_refund(
  uuid, uuid, character varying, uuid, character varying, character varying
) is
  'Audited and idempotent initiation of a human-review refund workflow. It never calls a payment provider or changes normalized transaction state.';

commit;
