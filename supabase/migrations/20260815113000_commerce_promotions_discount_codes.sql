begin;

insert into admin.permissions(code, description, risk_level)
values (
  'commerce.promotions.write',
  'Create and change promotions and discount-code lifecycle.',
  'HIGH_RISK'
)
on conflict (code) do update
set description = excluded.description,
    risk_level = excluded.risk_level;

insert into admin.role_permissions(role_id, permission_id)
select distinct rp.role_id, target.id
from admin.role_permissions rp
join admin.permissions trusted on trusted.id = rp.permission_id
cross join admin.permissions target
where trusted.code = 'commerce.refund'
  and target.code = 'commerce.promotions.write'
on conflict do nothing;

create table if not exists commerce.promotions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid null references commerce.products(id) on delete restrict,
  name character varying(160) not null check (length(trim(name)) between 2 and 160),
  description character varying(1000) null,
  discount_type text not null check (discount_type in ('Percentage', 'FixedAmount')),
  percentage_basis_points integer null check (percentage_basis_points between 1 and 10000),
  fixed_amount_minor bigint null check (fixed_amount_minor > 0),
  currency text null check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'Draft' check (status in ('Draft', 'Active', 'Paused', 'Expired')),
  starts_at_utc timestamptz not null,
  ends_at_utc timestamptz null,
  max_redemptions integer null check (max_redemptions > 0),
  created_by_account_id uuid not null references admin.members(account_id) on delete restrict,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (ends_at_utc is null or ends_at_utc > starts_at_utc),
  check (
    (discount_type = 'Percentage' and percentage_basis_points is not null and fixed_amount_minor is null and currency is null)
    or
    (discount_type = 'FixedAmount' and percentage_basis_points is null and fixed_amount_minor is not null and currency is not null)
  )
);

create index if not exists idx_commerce_promotions_status_time
  on commerce.promotions(status, starts_at_utc desc, id desc);
create index if not exists idx_commerce_promotions_product_time
  on commerce.promotions(product_id, starts_at_utc desc, id desc);

create table if not exists commerce.discount_codes (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references commerce.promotions(id) on delete restrict,
  code character varying(64) not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{2,63}$'),
  status text not null default 'Active' check (status in ('Active', 'Disabled')),
  max_redemptions integer null check (max_redemptions > 0),
  redemption_count integer not null default 0 check (redemption_count >= 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (max_redemptions is null or redemption_count <= max_redemptions)
);

create unique index if not exists uq_commerce_discount_codes_code
  on commerce.discount_codes(lower(code));
create index if not exists idx_commerce_discount_codes_promotion_status
  on commerce.discount_codes(promotion_id, status, created_at_utc desc, id desc);

comment on table commerce.promotions is
  'Commercial discount rules. Promotion lifecycle is distinct from individual redeemable discount codes.';
comment on table commerce.discount_codes is
  'Redeemable public-facing codes attached to a promotion. Codes carry no payment credentials or provider references.';

revoke all on commerce.promotions from public;
revoke all on commerce.discount_codes from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on commerce.promotions from anon';
    execute 'revoke all on commerce.discount_codes from anon';
  end if;

  if to_regrole('authenticated') is not null then
    execute 'revoke all on commerce.promotions from authenticated';
    execute 'revoke all on commerce.discount_codes from authenticated';
  end if;
end
$$;

grant select on commerce.promotions to lifemate_admin_runtime;
grant select on commerce.discount_codes to lifemate_admin_runtime;

create or replace function admin.create_commerce_promotion(
  p_actor_account_id uuid,
  p_product_id uuid,
  p_name character varying,
  p_description character varying,
  p_discount_type text,
  p_percentage_basis_points integer,
  p_fixed_amount_minor bigint,
  p_currency text,
  p_starts_at_utc timestamptz,
  p_ends_at_utc timestamptz,
  p_max_redemptions integer,
  p_primary_code character varying,
  p_code_max_redemptions integer,
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
  v_operation constant character varying := 'commerce.promotion.create';
  v_existing admin.idempotency_keys%rowtype;
  v_promotion_id uuid;
  v_code_id uuid;
  v_response jsonb;
  v_code character varying(64) := upper(trim(p_primary_code));
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.promotions.write') then
    return jsonb_build_object(
      'httpStatus', 403,
      'code', 'permission_denied',
      'message', 'The required permission is not granted.',
      'replayed', false
    );
  end if;

  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus', 400, 'code', 'promotion_reason_invalid', 'message', 'A reason between 10 and 1000 characters is required.', 'replayed', false);
  end if;

  if p_name is null or length(trim(p_name)) < 2 or length(trim(p_name)) > 160 then
    return jsonb_build_object('httpStatus', 400, 'code', 'promotion_name_invalid', 'message', 'Promotion name is invalid.', 'replayed', false);
  end if;

  if v_code is null or v_code !~ '^[A-Z0-9][A-Z0-9._-]{2,63}$' then
    return jsonb_build_object('httpStatus', 400, 'code', 'discount_code_invalid', 'message', 'Discount code is invalid.', 'replayed', false);
  end if;

  if p_starts_at_utc is null or (p_ends_at_utc is not null and p_ends_at_utc <= p_starts_at_utc) then
    return jsonb_build_object('httpStatus', 400, 'code', 'promotion_window_invalid', 'message', 'Promotion time window is invalid.', 'replayed', false);
  end if;

  if p_discount_type = 'Percentage' then
    if p_percentage_basis_points is null or p_percentage_basis_points < 1 or p_percentage_basis_points > 10000 or p_fixed_amount_minor is not null or p_currency is not null then
      return jsonb_build_object('httpStatus', 400, 'code', 'promotion_discount_invalid', 'message', 'Percentage discount configuration is invalid.', 'replayed', false);
    end if;
  elsif p_discount_type = 'FixedAmount' then
    if p_fixed_amount_minor is null or p_fixed_amount_minor <= 0 or p_currency is null or p_currency !~ '^[A-Z]{3}$' or p_percentage_basis_points is not null then
      return jsonb_build_object('httpStatus', 400, 'code', 'promotion_discount_invalid', 'message', 'Fixed-amount discount configuration is invalid.', 'replayed', false);
    end if;
  else
    return jsonb_build_object('httpStatus', 400, 'code', 'promotion_discount_invalid', 'message', 'Discount type is invalid.', 'replayed', false);
  end if;

  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus', 400, 'code', 'idempotency_invalid', 'message', 'Idempotency metadata is invalid.', 'replayed', false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key, 0));

  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_conflict', 'message', 'This Idempotency-Key was already used for a different request.', 'replayed', false);
    end if;
    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed', true);
    end if;
    return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_in_progress', 'message', 'The matching request is still being processed.', 'replayed', false);
  end if;

  insert into admin.idempotency_keys(actor_account_id, operation, idempotency_key, request_hash, status)
  values (p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing');

  if p_product_id is not null and not exists(select 1 from commerce.products where id = p_product_id) then
    v_response := jsonb_build_object('httpStatus', 404, 'code', 'commerce_product_not_found', 'message', 'Commerce product was not found.', 'replayed', false);
  elsif exists(select 1 from commerce.discount_codes where lower(code) = lower(v_code)) then
    v_response := jsonb_build_object('httpStatus', 409, 'code', 'discount_code_conflict', 'message', 'Discount code already exists.', 'replayed', false);
  else
    insert into commerce.promotions(
      product_id, name, description, discount_type, percentage_basis_points,
      fixed_amount_minor, currency, status, starts_at_utc, ends_at_utc,
      max_redemptions, created_by_account_id
    ) values (
      p_product_id, trim(p_name), nullif(trim(coalesce(p_description, '')), ''), p_discount_type,
      p_percentage_basis_points, p_fixed_amount_minor, p_currency, 'Draft', p_starts_at_utc,
      p_ends_at_utc, p_max_redemptions, p_actor_account_id
    ) returning id into v_promotion_id;

    insert into commerce.discount_codes(promotion_id, code, status, max_redemptions)
    values (v_promotion_id, v_code, 'Active', p_code_max_redemptions)
    returning id into v_code_id;

    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id, 'commerce.promotion.create', 'commerce_promotion', v_promotion_id::text,
      'Succeeded', trim(p_reason), p_correlation_id, p_idempotency_key, false,
      jsonb_build_object('discountCodeId', v_code_id, 'discountType', p_discount_type, 'status', 'Draft')
    );

    v_response := jsonb_build_object(
      'httpStatus', 201,
      'code', 'ok',
      'promotionId', v_promotion_id,
      'discountCodeId', v_code_id,
      'promotionStatus', 'Draft',
      'codeStatus', 'Active',
      'replayed', false
    );
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id, 'commerce.promotion.create', 'commerce_promotion', null,
      'Denied', coalesce(v_response->>'message', 'Promotion creation denied'), p_correlation_id,
      p_idempotency_key, false, jsonb_build_object('code', v_response->>'code')
    );
  end if;

  update admin.idempotency_keys
  set status = 'Completed',
      response_status = (v_response->>'httpStatus')::integer,
      response_json = v_response,
      updated_at_utc = now()
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key;

  return v_response;
end
$$;

create or replace function admin.set_commerce_promotion_status(
  p_actor_account_id uuid,
  p_promotion_id uuid,
  p_target_status text,
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
  v_operation character varying := 'commerce.promotion.status.' || lower(coalesce(p_target_status, 'invalid'));
  v_existing admin.idempotency_keys%rowtype;
  v_previous_status text;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.promotions.write') then
    return jsonb_build_object('httpStatus', 403, 'code', 'permission_denied', 'message', 'The required permission is not granted.', 'replayed', false);
  end if;
  if p_target_status not in ('Active', 'Paused') then
    return jsonb_build_object('httpStatus', 400, 'code', 'promotion_status_invalid', 'message', 'Target promotion status is invalid.', 'replayed', false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus', 400, 'code', 'promotion_reason_invalid', 'message', 'A reason between 10 and 1000 characters is required.', 'replayed', false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus', 400, 'code', 'idempotency_invalid', 'message', 'Idempotency metadata is invalid.', 'replayed', false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key, 0));
  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id = p_actor_account_id and operation = v_operation and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_conflict', 'message', 'This Idempotency-Key was already used for a different request.', 'replayed', false);
    end if;
    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed', true);
    end if;
    return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_in_progress', 'message', 'The matching request is still being processed.', 'replayed', false);
  end if;

  insert into admin.idempotency_keys(actor_account_id, operation, idempotency_key, request_hash, status)
  values (p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing');

  select status into v_previous_status from commerce.promotions where id = p_promotion_id for update;
  if not found then
    v_response := jsonb_build_object('httpStatus', 404, 'code', 'commerce_promotion_not_found', 'message', 'Promotion was not found.', 'replayed', false);
  elsif v_previous_status = 'Expired' then
    v_response := jsonb_build_object('httpStatus', 409, 'code', 'promotion_expired', 'message', 'Expired promotion cannot change lifecycle status.', 'replayed', false);
  elsif v_previous_status = p_target_status then
    v_response := jsonb_build_object('httpStatus', 200, 'code', 'ok', 'promotionId', p_promotion_id, 'previousStatus', v_previous_status, 'status', p_target_status, 'replayed', false);
  else
    update commerce.promotions
    set status = p_target_status, updated_at_utc = now()
    where id = p_promotion_id;

    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id, 'commerce.promotion.status.change', 'commerce_promotion', p_promotion_id::text,
      'Succeeded', trim(p_reason), p_correlation_id, p_idempotency_key, false,
      jsonb_build_object('previousStatus', v_previous_status, 'status', p_target_status)
    );

    v_response := jsonb_build_object('httpStatus', 200, 'code', 'ok', 'promotionId', p_promotion_id, 'previousStatus', v_previous_status, 'status', p_target_status, 'replayed', false);
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id, 'commerce.promotion.status.change', 'commerce_promotion', p_promotion_id::text,
      'Denied', coalesce(v_response->>'message', 'Promotion status change denied'), p_correlation_id,
      p_idempotency_key, false, jsonb_build_object('targetStatus', p_target_status, 'code', v_response->>'code')
    );
  end if;

  update admin.idempotency_keys
  set status = 'Completed', response_status = (v_response->>'httpStatus')::integer,
      response_json = v_response, updated_at_utc = now()
  where actor_account_id = p_actor_account_id and operation = v_operation and idempotency_key = p_idempotency_key;

  return v_response;
end
$$;

revoke all on function admin.create_commerce_promotion(
  uuid, uuid, character varying, character varying, text, integer, bigint, text,
  timestamptz, timestamptz, integer, character varying, integer, character varying,
  uuid, character varying, character varying
) from public;
revoke all on function admin.set_commerce_promotion_status(
  uuid, uuid, text, character varying, uuid, character varying, character varying
) from public;

do $$
begin
  if to_regrole('anon') is not null then
    revoke all on function admin.create_commerce_promotion(
      uuid, uuid, character varying, character varying, text, integer, bigint, text,
      timestamptz, timestamptz, integer, character varying, integer, character varying,
      uuid, character varying, character varying
    ) from anon;
    revoke all on function admin.set_commerce_promotion_status(
      uuid, uuid, text, character varying, uuid, character varying, character varying
    ) from anon;
  end if;

  if to_regrole('authenticated') is not null then
    revoke all on function admin.create_commerce_promotion(
      uuid, uuid, character varying, character varying, text, integer, bigint, text,
      timestamptz, timestamptz, integer, character varying, integer, character varying,
      uuid, character varying, character varying
    ) from authenticated;
    revoke all on function admin.set_commerce_promotion_status(
      uuid, uuid, text, character varying, uuid, character varying, character varying
    ) from authenticated;
  end if;
end
$$;

grant execute on function admin.create_commerce_promotion(
  uuid, uuid, character varying, character varying, text, integer, bigint, text,
  timestamptz, timestamptz, integer, character varying, integer, character varying,
  uuid, character varying, character varying
) to lifemate_admin_runtime;
grant execute on function admin.set_commerce_promotion_status(
  uuid, uuid, text, character varying, uuid, character varying, character varying
) to lifemate_admin_runtime;

comment on function admin.create_commerce_promotion(
  uuid, uuid, character varying, character varying, text, integer, bigint, text,
  timestamptz, timestamptz, integer, character varying, integer, character varying,
  uuid, character varying, character varying
) is 'Audited, idempotent creation of a Draft promotion with its primary discount code.';
comment on function admin.set_commerce_promotion_status(
  uuid, uuid, text, character varying, uuid, character varying, character varying
) is 'Audited, idempotent promotion lifecycle transition restricted to Active/Paused.';

commit;
