begin;

-- #507: an idempotency key represents one immutable logical submission.
-- Reusing it with any user-visible/context field changed must fail closed rather
-- than silently returning the first row. Advocacy consent is exclusive to the
-- Advocacy surface and must never be inferred from ordinary feedback.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='feedback.items'::regclass
      and conname='feedback_advocacy_exclusive_shape'
  ) then
    alter table feedback.items
      add constraint feedback_advocacy_exclusive_shape
      check (kind='Advocacy' or not advocacy_opt_in) not valid;
  end if;
end
$$;
alter table feedback.items validate constraint feedback_advocacy_exclusive_shape;

create or replace function feedback.submit_item(
  p_app_user_id uuid,
  p_kind feedback.item_kind,
  p_product_code text,
  p_app_version text,
  p_build_number text,
  p_nps_score smallint,
  p_message text,
  p_advocacy_opt_in boolean,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,feedback
as $$
declare
  v feedback.items%rowtype;
  v_product_code text := lower(btrim(coalesce(p_product_code, '')));
  v_app_version text := nullif(btrim(p_app_version), '');
  v_build_number text := nullif(btrim(p_build_number), '');
  v_message text := nullif(btrim(p_message), '');
  v_advocacy_opt_in boolean := coalesce(p_advocacy_opt_in, false);
  v_idempotency_key text := btrim(coalesce(p_idempotency_key, ''));
begin
  if p_app_user_id is null then
    raise exception 'app_user_required' using errcode='22023';
  end if;
  if v_product_code !~ '^[a-z][a-z0-9_-]{1,39}$' then
    raise exception 'product_invalid' using errcode='22023';
  end if;
  if char_length(v_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency_key_invalid' using errcode='22023';
  end if;
  if p_kind <> 'Nps' and v_message is null then
    raise exception 'message_required' using errcode='22023';
  end if;
  if p_kind='Nps' and (p_nps_score is null or p_nps_score not between 0 and 10) then
    raise exception 'nps_score_invalid' using errcode='22023';
  end if;
  if p_kind<>'Nps' and p_nps_score is not null then
    raise exception 'nps_score_forbidden' using errcode='22023';
  end if;
  if p_kind='Advocacy' and not v_advocacy_opt_in then
    raise exception 'advocacy_opt_in_required' using errcode='22023';
  end if;
  if p_kind<>'Advocacy' and v_advocacy_opt_in then
    raise exception 'advocacy_opt_in_forbidden' using errcode='22023';
  end if;

  insert into feedback.items(
    app_user_id,kind,product_code,app_version,build_number,nps_score,
    message,advocacy_opt_in,idempotency_key
  ) values (
    p_app_user_id,p_kind,v_product_code,v_app_version,v_build_number,p_nps_score,
    v_message,v_advocacy_opt_in,v_idempotency_key
  )
  on conflict(app_user_id,idempotency_key) do nothing
  returning * into v;

  if v.id is null then
    select * into v
    from feedback.items
    where app_user_id=p_app_user_id
      and idempotency_key=v_idempotency_key;

    if v.id is null
       or v.kind<>p_kind
       or v.product_code<>v_product_code
       or v.app_version is distinct from v_app_version
       or v.build_number is distinct from v_build_number
       or v.nps_score is distinct from p_nps_score
       or v.message is distinct from v_message
       or v.advocacy_opt_in is distinct from v_advocacy_opt_in then
      raise exception 'idempotency_conflict' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'id',v.id,
    'kind',v.kind,
    'status',v.status,
    'productCode',v.product_code,
    'appVersion',v.app_version,
    'buildNumber',v.build_number,
    'npsScore',v.nps_score,
    'message',v.message,
    'advocacyOptIn',v.advocacy_opt_in,
    'createdAt',v.created_at
  );
end
$$;

revoke all on function feedback.submit_item(
  uuid,feedback.item_kind,text,text,text,smallint,text,boolean,text
) from public,anon,authenticated;
grant execute on function feedback.submit_item(
  uuid,feedback.item_kind,text,text,text,smallint,text,boolean,text
) to lifemate_edge_runtime;

commit;
