-- ADM-SUP-001: canonical support ticket queue metadata and approved Admin API read model.
-- Raw conversations, attachments and health payloads deliberately do not live in this table.

create schema if not exists support;

create table if not exists support.tickets (
    id uuid primary key default gen_random_uuid(),
    ticket_number bigint generated always as identity unique,
    requester_account_id uuid not null references identity.accounts(id) on delete restrict,
    product_code character varying(64),
    category character varying(64) not null default 'general'
        check (category ~ '^[a-z0-9_-]{1,64}$'),
    status character varying(24) not null default 'Open'
        check (status in ('Open','Pending','WaitingOnUser','Resolved','Closed')),
    priority character varying(16) not null default 'Normal'
        check (priority in ('Low','Normal','High','Urgent')),
    queue_summary_redacted character varying(280),
    assigned_admin_account_id uuid references admin.members(account_id) on delete restrict,
    first_response_due_at_utc timestamp with time zone,
    resolution_due_at_utc timestamp with time zone,
    last_activity_at_utc timestamp with time zone not null default now(),
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    check (first_response_due_at_utc is null or first_response_due_at_utc >= created_at_utc),
    check (resolution_due_at_utc is null or resolution_due_at_utc >= created_at_utc)
);

comment on column support.tickets.queue_summary_redacted is
  'Optional queue-safe summary. Must be redacted upstream and must never contain raw health/Women Health payloads.';

create index if not exists ix_support_tickets_queue
    on support.tickets(status, priority, last_activity_at_utc desc, id);
create index if not exists ix_support_tickets_requester
    on support.tickets(requester_account_id, last_activity_at_utc desc);
create index if not exists ix_support_tickets_assignee
    on support.tickets(assigned_admin_account_id, status, last_activity_at_utc desc)
    where assigned_admin_account_id is not null;
create index if not exists ix_support_tickets_sla
    on support.tickets(resolution_due_at_utc, first_response_due_at_utc)
    where status not in ('Resolved','Closed');

alter table support.tickets enable row level security;
alter table support.tickets force row level security;

drop policy if exists lifemate_admin_runtime_select on support.tickets;
create policy lifemate_admin_runtime_select
on support.tickets for select to lifemate_admin_runtime
using (true);

create or replace view admin.support_ticket_queue_v1
with (security_invoker = true)
as
select
    t.id as ticket_id,
    t.ticket_number,
    t.requester_account_id,
    requester_profile.display_name as requester_display_name,
    t.product_code,
    t.category,
    t.status,
    t.priority,
    t.queue_summary_redacted,
    t.assigned_admin_account_id,
    assignee_profile.display_name as assignee_display_name,
    t.first_response_due_at_utc,
    t.resolution_due_at_utc,
    case
      when t.status in ('Resolved','Closed') then 'Completed'
      when t.first_response_due_at_utc is not null and t.first_response_due_at_utc < now() then 'Breached'
      when t.resolution_due_at_utc is not null and t.resolution_due_at_utc < now() then 'Breached'
      when coalesce(t.first_response_due_at_utc, t.resolution_due_at_utc) is not null
       and least(
          coalesce(t.first_response_due_at_utc, 'infinity'::timestamptz),
          coalesce(t.resolution_due_at_utc, 'infinity'::timestamptz)
       ) <= now() + interval '2 hours' then 'DueSoon'
      else 'OnTrack'
    end as sla_state,
    case
      when t.status in ('Resolved','Closed') then null
      else nullif(
        least(
          coalesce(t.first_response_due_at_utc, 'infinity'::timestamptz),
          coalesce(t.resolution_due_at_utc, 'infinity'::timestamptz)
        ),
        'infinity'::timestamptz
      )
    end as next_due_at_utc,
    t.last_activity_at_utc,
    t.created_at_utc,
    t.updated_at_utc
from support.tickets t
left join core.account_person_links requester_link
  on requester_link.account_id = t.requester_account_id
 and requester_link.link_type = 'Self'
 and requester_link.status = 'Active'
left join core.person_profiles requester_profile
  on requester_profile.person_id = requester_link.person_id
left join core.account_person_links assignee_link
  on assignee_link.account_id = t.assigned_admin_account_id
 and assignee_link.link_type = 'Self'
 and assignee_link.status = 'Active'
left join core.person_profiles assignee_profile
  on assignee_profile.person_id = assignee_link.person_id;

revoke all on schema support from public;
revoke all on support.tickets from public;
revoke all on admin.support_ticket_queue_v1 from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname = v_role) then
      execute format('revoke all on schema support from %I', v_role);
      execute format('revoke all on support.tickets from %I', v_role);
      execute format('revoke all on admin.support_ticket_queue_v1 from %I', v_role);
    end if;
  end loop;
end
$$;

grant usage on schema support to lifemate_admin_runtime;
grant select on support.tickets to lifemate_admin_runtime;
grant select on admin.support_ticket_queue_v1 to lifemate_admin_runtime;

comment on view admin.support_ticket_queue_v1 is
  'Approved privacy-minimized LifeMate Command Center support queue read model (v1).';
