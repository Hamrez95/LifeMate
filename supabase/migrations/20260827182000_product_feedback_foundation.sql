begin;

create schema if not exists feedback;
revoke all on schema feedback from public, anon, authenticated;

do $$ begin
  create type feedback.item_kind as enum ('Feedback','Nps','BugReport','FeatureRequest','Advocacy');
exception when duplicate_object then null; end $$;

do $$ begin
  create type feedback.item_status as enum ('Submitted','Acknowledged','Triaged','Resolved');
exception when duplicate_object then null; end $$;

create table if not exists feedback.items (
  id uuid primary key default gen_random_uuid(),
  app_user_id uuid not null,
  kind feedback.item_kind not null,
  status feedback.item_status not null default 'Submitted',
  product_code text not null check (product_code ~ '^[a-z][a-z0-9_-]{1,39}$'),
  app_version text null check (app_version is null or app_version ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$'),
  build_number text null check (build_number is null or build_number ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,39}$'),
  nps_score smallint null check (nps_score between 0 and 10),
  message text null check (message is null or char_length(message) between 1 and 2000),
  advocacy_opt_in boolean not null default false,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 128),
  linked_support_ticket_id uuid null,
  linked_product_issue_ref text null check (linked_product_issue_ref is null or char_length(linked_product_issue_ref) <= 160),
  acknowledged_at timestamptz null,
  triaged_at timestamptz null,
  resolved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint feedback_nps_shape check ((kind = 'Nps') = (nps_score is not null)),
  constraint feedback_advocacy_shape check (kind <> 'Advocacy' or advocacy_opt_in),
  constraint feedback_idempotency_unique unique (app_user_id, idempotency_key)
);

create index if not exists feedback_items_owner_created_idx
  on feedback.items (app_user_id, created_at desc);
create index if not exists feedback_items_queue_idx
  on feedback.items (status, kind, created_at desc);
create index if not exists feedback_items_product_idx
  on feedback.items (product_code, created_at desc);

alter table feedback.items enable row level security;
alter table feedback.items force row level security;
revoke all on feedback.items from public, anon, authenticated;

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
set search_path = pg_catalog, feedback
as $$
declare
  v_item feedback.items%rowtype;
begin
  if p_app_user_id is null then raise exception 'app_user_required' using errcode = '22023'; end if;
  if p_product_code !~ '^[a-z][a-z0-9_-]{1,39}$' then raise exception 'product_invalid' using errcode = '22023'; end if;
  if p_idempotency_key is null or char_length(btrim(p_idempotency_key)) not between 8 and 128 then
    raise exception 'idempotency_key_invalid' using errcode = '22023';
  end if;
  if p_message is not null and char_length(btrim(p_message)) not between 1 and 2000 then
    raise exception 'message_invalid' using errcode = '22023';
  end if;
  if p_kind = 'Nps' and (p_nps_score is null or p_nps_score not between 0 and 10) then
    raise exception 'nps_score_invalid' using errcode = '22023';
  end if;
  if p_kind <> 'Nps' and p_nps_score is not null then
    raise exception 'nps_score_forbidden' using errcode = '22023';
  end if;
  if p_kind = 'Advocacy' and not coalesce(p_advocacy_opt_in, false) then
    raise exception 'advocacy_opt_in_required' using errcode = '22023';
  end if;

  insert into feedback.items (
    app_user_id, kind, product_code, app_version, build_number, nps_score,
    message, advocacy_opt_in, idempotency_key
  ) values (
    p_app_user_id, p_kind, lower(p_product_code), nullif(btrim(p_app_version), ''),
    nullif(btrim(p_build_number), ''), p_nps_score, nullif(btrim(p_message), ''),
    coalesce(p_advocacy_opt_in, false), btrim(p_idempotency_key)
  )
  on conflict (app_user_id, idempotency_key) do nothing
  returning * into v_item;

  if v_item.id is null then
    select * into v_item from feedback.items
    where app_user_id = p_app_user_id and idempotency_key = btrim(p_idempotency_key);

    if v_item.kind <> p_kind
       or v_item.product_code <> lower(p_product_code)
       or coalesce(v_item.app_version, '') <> coalesce(nullif(btrim(p_app_version), ''), '')
       or coalesce(v_item.build_number, '') <> coalesce(nullif(btrim(p_build_number), ''), '')
       or v_item.nps_score is distinct from p_nps_score
       or coalesce(v_item.message, '') <> coalesce(nullif(btrim(p_message), ''), '')
       or v_item.advocacy_opt_in is distinct from coalesce(p_advocacy_opt_in, false) then
      raise exception 'idempotency_conflict' using errcode = '23505';
    end if;
  end if;

  return jsonb_build_object(
    'id', v_item.id,
    'kind', v_item.kind,
    'status', v_item.status,
    'productCode', v_item.product_code,
    'appVersion', v_item.app_version,
    'buildNumber', v_item.build_number,
    'npsScore', v_item.nps_score,
    'message', v_item.message,
    'advocacyOptIn', v_item.advocacy_opt_in,
    'createdAt', v_item.created_at
  );
end;
$$;

revoke all on function feedback.submit_item(uuid, feedback.item_kind, text, text, text, smallint, text, boolean, text) from public, anon, authenticated;
grant usage on schema feedback to lifemate_edge_runtime;
grant execute on function feedback.submit_item(uuid, feedback.item_kind, text, text, text, smallint, text, boolean, text) to lifemate_edge_runtime;

create or replace view admin.product_feedback_queue_v1
with (security_invoker = true)
as
select
  id,
  kind::text as kind,
  status::text as status,
  product_code,
  app_version,
  build_number,
  nps_score,
  advocacy_opt_in,
  linked_support_ticket_id,
  linked_product_issue_ref,
  created_at,
  acknowledged_at,
  triaged_at,
  resolved_at
from feedback.items;

revoke all on admin.product_feedback_queue_v1 from public, anon, authenticated;

create or replace view admin.product_feedback_trends_v1
with (security_invoker = true)
as
select
  date_trunc('day', created_at) as day,
  product_code,
  kind::text as kind,
  count(*)::bigint as submissions,
  case when kind = 'Nps' then round(avg(nps_score)::numeric, 2) else null end as average_nps
from feedback.items
group by 1, 2, 3;

revoke all on admin.product_feedback_trends_v1 from public, anon, authenticated;

commit;
