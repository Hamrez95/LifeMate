begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('feedback.read','product','SENSITIVE',true,'Read bounded product feedback, NPS and advocacy signals'),
('feedback.write','product','HIGH_RISK',true,'Triage and link product feedback through the audited lifecycle')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join (values ('feedback.read'),('feedback.write')) p(code)
where r.code in ('founder','super_admin','product','support')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'feedback.read'
from admin.roles r
where r.code in ('marketing','analytics')
on conflict do nothing;

create or replace function feedback.admin_transition_item(
  p_actor_account_id uuid,
  p_item_id uuid,
  p_expected_status feedback.item_status,
  p_action text,
  p_reason text,
  p_support_ticket_id uuid default null,
  p_product_issue_ref text default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,feedback,admin,support
as $$
declare
  v feedback.items%rowtype;
  v_next feedback.item_status;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'feedback.write') then
    raise exception 'feedback_permission_denied' using errcode='42501';
  end if;
  if nullif(btrim(p_reason),'') is null or char_length(btrim(p_reason)) not between 3 and 500 then
    raise exception 'feedback_reason_invalid' using errcode='22023';
  end if;
  select * into v from feedback.items where id=p_item_id for update;
  if v.id is null then raise exception 'feedback_not_found' using errcode='P0002'; end if;
  if v.status is distinct from p_expected_status then raise exception 'feedback_status_conflict' using errcode='40001'; end if;

  v_next:=v.status;
  if p_action='Acknowledge' then
    if v.status<>'Submitted' then raise exception 'feedback_transition_invalid' using errcode='22023'; end if;
    v_next:='Acknowledged';
  elsif p_action='Triage' then
    if v.status not in ('Submitted','Acknowledged') then raise exception 'feedback_transition_invalid' using errcode='22023'; end if;
    v_next:='Triaged';
  elsif p_action='Resolve' then
    if v.status<>'Triaged' then raise exception 'feedback_transition_invalid' using errcode='22023'; end if;
    v_next:='Resolved';
  elsif p_action='LinkSupport' then
    if p_support_ticket_id is null then raise exception 'feedback_support_link_required' using errcode='22023'; end if;
    if not exists(select 1 from support.tickets where id=p_support_ticket_id) then
      raise exception 'feedback_support_ticket_not_found' using errcode='P0002';
    end if;
  elsif p_action='LinkProductIssue' then
    if p_product_issue_ref is null or char_length(btrim(p_product_issue_ref)) not between 1 and 160
       or btrim(p_product_issue_ref) ~* '^(https?://|www\.)' then
      raise exception 'feedback_product_issue_invalid' using errcode='22023';
    end if;
  else
    raise exception 'feedback_action_invalid' using errcode='22023';
  end if;

  update feedback.items set
    status=v_next,
    linked_support_ticket_id=case when p_action='LinkSupport' then p_support_ticket_id else linked_support_ticket_id end,
    linked_product_issue_ref=case when p_action='LinkProductIssue' then btrim(p_product_issue_ref) else linked_product_issue_ref end,
    acknowledged_at=case when v_next='Acknowledged' then coalesce(acknowledged_at,now()) else acknowledged_at end,
    triaged_at=case when v_next='Triaged' then coalesce(triaged_at,now()) else triaged_at end,
    resolved_at=case when v_next='Resolved' then coalesce(resolved_at,now()) else resolved_at end,
    updated_at=now()
  where id=p_item_id;

  insert into feedback.item_audit(item_id,actor_account_id,action,previous_status,next_status,reason)
  values(p_item_id,p_actor_account_id,p_action,v.status,v_next,btrim(p_reason));

  return jsonb_build_object('itemId',p_item_id,'previousStatus',v.status,'status',v_next,'action',p_action);
end $$;

create or replace function feedback.admin_list_items(
  p_actor_account_id uuid,
  p_status text default null,
  p_kind text default null,
  p_product_code text default null,
  p_app_version text default null,
  p_limit integer default 50,
  p_offset integer default 0
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,feedback,admin
as $$
declare v_items jsonb; v_total bigint;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'feedback.read') then
    raise exception 'feedback_permission_denied' using errcode='42501';
  end if;
  if p_limit not between 1 and 100 or p_offset not between 0 and 10000 then
    raise exception 'feedback_pagination_invalid' using errcode='22023';
  end if;
  if p_status is not null and p_status not in ('Submitted','Acknowledged','Triaged','Resolved') then
    raise exception 'feedback_status_invalid' using errcode='22023';
  end if;
  if p_kind is not null and p_kind not in ('Feedback','Nps','BugReport','FeatureRequest','Advocacy') then
    raise exception 'feedback_kind_invalid' using errcode='22023';
  end if;
  if p_product_code is not null and p_product_code !~ '^[a-z][a-z0-9_-]{1,39}$' then
    raise exception 'feedback_product_invalid' using errcode='22023';
  end if;
  if p_app_version is not null and char_length(p_app_version)>80 then
    raise exception 'feedback_app_version_invalid' using errcode='22023';
  end if;

  select count(*) into v_total from feedback.items i
   where (p_status is null or i.status::text=p_status)
     and (p_kind is null or i.kind::text=p_kind)
     and (p_product_code is null or i.product_code=p_product_code)
     and (p_app_version is null or i.app_version=p_app_version);

  select coalesce(jsonb_agg(jsonb_build_object(
    'itemId',q.id,'kind',q.kind::text,'status',q.status::text,'productCode',q.product_code,
    'appVersion',q.app_version,'buildNumber',q.build_number,'npsScore',q.nps_score,
    'message',q.message,'advocacyOptIn',q.advocacy_opt_in,'linkedSupportTicketId',q.linked_support_ticket_id,
    'linkedProductIssueRef',q.linked_product_issue_ref,'createdAtUtc',q.created_at,
    'acknowledgedAtUtc',q.acknowledged_at,'triagedAtUtc',q.triaged_at,'resolvedAtUtc',q.resolved_at
  ) order by q.created_at desc,q.id desc),'[]'::jsonb) into v_items
  from (
    select * from feedback.items i
     where (p_status is null or i.status::text=p_status)
       and (p_kind is null or i.kind::text=p_kind)
       and (p_product_code is null or i.product_code=p_product_code)
       and (p_app_version is null or i.app_version=p_app_version)
     order by i.created_at desc,i.id desc
     limit p_limit offset p_offset
  ) q;

  return jsonb_build_object('items',v_items,'total',v_total,'limit',p_limit,'offset',p_offset);
end $$;

create or replace function feedback.admin_trends(
  p_actor_account_id uuid,
  p_product_code text default null,
  p_days integer default 30
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,feedback,admin
as $$
declare v_items jsonb;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'feedback.read') then
    raise exception 'feedback_permission_denied' using errcode='42501';
  end if;
  if p_days not between 1 and 365 then raise exception 'feedback_days_invalid' using errcode='22023'; end if;
  if p_product_code is not null and p_product_code !~ '^[a-z][a-z0-9_-]{1,39}$' then
    raise exception 'feedback_product_invalid' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.day desc,q.product_code,q.kind,q.status),'[]'::jsonb)
  into v_items
  from (
    select date_trunc('day',created_at)::date as day,product_code,kind::text as kind,status::text as status,
           count(*)::bigint as item_count,
           count(nps_score)::bigint as nps_response_count,
           case when count(nps_score)>0 then round(avg(nps_score)::numeric,2) else null end as average_nps
    from feedback.items
    where created_at>=now()-make_interval(days=>p_days)
      and (p_product_code is null or product_code=p_product_code)
    group by 1,2,3,4
  ) q;
  return jsonb_build_object('items',v_items,'days',p_days,'privacy',jsonb_build_object('freeTextIncluded',false));
end $$;

create or replace function feedback.admin_transition_item_idempotent(
  p_actor_account_id uuid,
  p_item_id uuid,
  p_expected_status feedback.item_status,
  p_action text,
  p_reason text,
  p_support_ticket_id uuid,
  p_product_issue_ref text,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,feedback,admin
as $$
declare v_inserted integer; v_existing admin.idempotency_keys%rowtype; v_response jsonb;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'feedback.write') then
    raise exception 'feedback_permission_denied' using errcode='42501';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'feedback_idempotency_invalid' using errcode='22023';
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'feedback.item.action',p_idempotency_key,p_request_hash,'Processing')
  on conflict do nothing;
  get diagnostics v_inserted=row_count;

  if v_inserted=0 then
    select * into v_existing from admin.idempotency_keys
    where actor_account_id=p_actor_account_id and operation='feedback.item.action' and idempotency_key=p_idempotency_key
    for update;
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;

  v_response:=feedback.admin_transition_item(
    p_actor_account_id,p_item_id,p_expected_status,p_action,p_reason,p_support_ticket_id,p_product_issue_ref
  ) || jsonb_build_object('httpStatus',200,'code','ok','replayed',false);

  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation='feedback.item.action' and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function feedback.admin_transition_item(uuid,uuid,feedback.item_status,text,text,uuid,text) from public,anon,authenticated;
revoke all on function feedback.admin_list_items(uuid,text,text,text,text,integer,integer) from public,anon,authenticated;
revoke all on function feedback.admin_trends(uuid,text,integer) from public,anon,authenticated;
revoke all on function feedback.admin_transition_item_idempotent(uuid,uuid,feedback.item_status,text,text,uuid,text,character varying,character varying) from public,anon,authenticated;

do $$ begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant usage on schema feedback to lifemate_admin_runtime;
    grant execute on function feedback.admin_list_items(uuid,text,text,text,text,integer,integer) to lifemate_admin_runtime;
    grant execute on function feedback.admin_trends(uuid,text,integer) to lifemate_admin_runtime;
    grant execute on function feedback.admin_transition_item_idempotent(uuid,uuid,feedback.item_status,text,text,uuid,text,character varying,character varying) to lifemate_admin_runtime;
  end if;
end $$;

commit;
