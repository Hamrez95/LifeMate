-- #496: internal support escalation / linked-report metadata.
-- Escalation changes workflow ownership only; it never grants health/access permissions.

create table if not exists support.ticket_escalations (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support.tickets(id) on delete cascade,
  requested_by_account_id uuid not null references admin.members(account_id) on delete restrict,
  target_role_id uuid not null references admin.roles(id) on delete restrict,
  status character varying(20) not null default 'Pending'
    check (status in ('Pending','Acknowledged','Resolved','Cancelled')),
  safe_reason character varying(800) not null
    check (length(trim(safe_reason)) between 5 and 800),
  created_at_utc timestamp with time zone not null default now(),
  acknowledged_at_utc timestamp with time zone,
  resolved_at_utc timestamp with time zone
);
comment on column support.ticket_escalations.safe_reason is
  'Privacy-minimized operational reason only; do not copy raw health/contact payloads.';
create index if not exists ix_support_ticket_escalations_queue
  on support.ticket_escalations(target_role_id,status,created_at_utc desc,id);
create index if not exists ix_support_ticket_escalations_ticket
  on support.ticket_escalations(ticket_id,created_at_utc desc,id);

create table if not exists support.ticket_links (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support.tickets(id) on delete cascade,
  link_kind character varying(24) not null
    check (link_kind in ('ProductIssue','EngineeringIssue','Incident','Other')),
  reference_code character varying(180) not null
    check (length(trim(reference_code)) between 1 and 180),
  created_by_account_id uuid not null references admin.members(account_id) on delete restrict,
  created_at_utc timestamp with time zone not null default now(),
  unique(ticket_id,link_kind,reference_code)
);
comment on column support.ticket_links.reference_code is
  'Opaque internal issue/incident reference; not a browser-fetchable arbitrary URL.';

alter table support.ticket_escalations enable row level security;
alter table support.ticket_escalations force row level security;
alter table support.ticket_links enable row level security;
alter table support.ticket_links force row level security;

drop policy if exists lifemate_admin_runtime_select on support.ticket_escalations;
create policy lifemate_admin_runtime_select on support.ticket_escalations
  for select to lifemate_admin_runtime using (true);
drop policy if exists lifemate_admin_runtime_select on support.ticket_links;
create policy lifemate_admin_runtime_select on support.ticket_links
  for select to lifemate_admin_runtime using (true);

create or replace function admin.create_support_escalation(
  p_actor_account_id uuid,
  p_ticket_id uuid,
  p_target_role_code character varying,
  p_safe_reason character varying,
  p_correlation_id uuid
) returns uuid
language plpgsql
security definer
set search_path = admin,support,pg_temp
as $$
declare
  v_role_id uuid;
  v_escalation_id uuid;
  v_reason text := trim(coalesce(p_safe_reason,''));
begin
  if not admin.account_has_permission(p_actor_account_id,'support.write') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if not exists(select 1 from support.tickets where id=p_ticket_id) then
    raise exception using errcode='P0002',message='ticket_not_found';
  end if;
  if length(v_reason) < 5 or length(v_reason) > 800 then
    raise exception using errcode='22023',message='support_escalation_reason_invalid';
  end if;
  select id into v_role_id from admin.roles
  where code=lower(trim(p_target_role_code)) and status='Active';
  if not found then
    raise exception using errcode='22023',message='support_escalation_role_invalid';
  end if;

  insert into support.ticket_escalations(
    ticket_id,requested_by_account_id,target_role_id,safe_reason
  ) values(p_ticket_id,p_actor_account_id,v_role_id,v_reason)
  returning id into v_escalation_id;

  update support.tickets set last_activity_at_utc=now(),updated_at_utc=now()
  where id=p_ticket_id;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'support.ticket.escalated','support_ticket',p_ticket_id::text,
    'Succeeded','Support ticket escalated to another staff role',p_correlation_id,false,
    jsonb_build_object('escalationId',v_escalation_id,'targetRoleCode',lower(trim(p_target_role_code)))
  );
  return v_escalation_id;
end
$$;

create or replace function admin.link_support_ticket_reference(
  p_actor_account_id uuid,
  p_ticket_id uuid,
  p_link_kind character varying,
  p_reference_code character varying,
  p_correlation_id uuid
) returns uuid
language plpgsql
security definer
set search_path = admin,support,pg_temp
as $$
declare
  v_link_id uuid;
  v_reference text := trim(coalesce(p_reference_code,''));
begin
  if not admin.account_has_permission(p_actor_account_id,'support.write') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if not exists(select 1 from support.tickets where id=p_ticket_id) then
    raise exception using errcode='P0002',message='ticket_not_found';
  end if;
  if p_link_kind not in ('ProductIssue','EngineeringIssue','Incident','Other')
     or length(v_reference) < 1 or length(v_reference) > 180 then
    raise exception using errcode='22023',message='support_link_invalid';
  end if;
  if v_reference ~* '^https?://' then
    raise exception using errcode='22023',message='support_link_url_forbidden';
  end if;

  insert into support.ticket_links(
    ticket_id,link_kind,reference_code,created_by_account_id
  ) values(p_ticket_id,p_link_kind,v_reference,p_actor_account_id)
  on conflict(ticket_id,link_kind,reference_code) do update
    set reference_code=excluded.reference_code
  returning id into v_link_id;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'support.ticket.reference.linked','support_ticket',p_ticket_id::text,
    'Succeeded','Support ticket linked to internal reference',p_correlation_id,false,
    jsonb_build_object('linkId',v_link_id,'linkKind',p_link_kind,'referenceCode',v_reference)
  );
  return v_link_id;
end
$$;

revoke all on support.ticket_escalations,support.ticket_links from public;
revoke all on function admin.create_support_escalation(uuid,uuid,character varying,character varying,uuid) from public;
revoke all on function admin.link_support_ticket_reference(uuid,uuid,character varying,character varying,uuid) from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on support.ticket_escalations from %I',v_role);
      execute format('revoke all on support.ticket_links from %I',v_role);
    end if;
  end loop;
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant select on support.ticket_escalations,support.ticket_links to lifemate_admin_runtime;
    grant execute on function admin.create_support_escalation(uuid,uuid,character varying,character varying,uuid)
      to lifemate_admin_runtime;
    grant execute on function admin.link_support_ticket_reference(uuid,uuid,character varying,character varying,uuid)
      to lifemate_admin_runtime;
  end if;
end
$$;
