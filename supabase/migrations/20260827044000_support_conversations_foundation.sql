begin;

-- Extend the existing support ticket boundary. Do not create a parallel support
-- identity or ticket model: requester remains identity.accounts -> support.tickets.
alter table support.tickets
  drop constraint if exists tickets_status_check;
alter table support.tickets
  add constraint tickets_status_check
  check (status in ('Open','Pending','InProgress','WaitingOnUser','Resolved','Closed'));

create table if not exists support.messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support.tickets(id) on delete cascade,
  sequence_no bigint generated always as identity,
  sender_kind varchar(16) not null check (sender_kind in ('User','Staff','System')),
  sender_account_id uuid references identity.accounts(id) on delete restrict,
  visibility varchar(16) not null default 'Participants'
    check (visibility in ('Participants','StaffOnly')),
  message_type varchar(24) not null default 'Message'
    check (message_type in ('Message','InternalNote','SystemEvent')),
  body text,
  body_bytes integer generated always as (octet_length(coalesce(body,''))) stored,
  idempotency_key varchar(180),
  request_hash varchar(128),
  created_at_utc timestamptz not null default now(),
  edited_at_utc timestamptz,
  check (body is null or length(trim(body)) between 1 and 4000),
  check (body_bytes <= 16384),
  check (request_hash is null or request_hash ~ '^[0-9a-f]{64,128}$'),
  check (
    (message_type='InternalNote' and sender_kind='Staff' and visibility='StaffOnly')
    or (message_type<>'InternalNote')
  ),
  unique(ticket_id,sequence_no),
  unique(ticket_id,sender_account_id,idempotency_key)
);
create index if not exists ix_support_messages_ticket_order
  on support.messages(ticket_id,sequence_no,id);

comment on column support.messages.body is
  'User/support conversation text. Never copy this field into routine audit, analytics, notification or queue logs; it may contain user-supplied sensitive information.';

create table if not exists support.message_reads (
  ticket_id uuid not null references support.tickets(id) on delete cascade,
  account_id uuid not null references identity.accounts(id) on delete cascade,
  read_through_sequence bigint not null check (read_through_sequence>=0),
  updated_at_utc timestamptz not null default now(),
  primary key(ticket_id,account_id)
);

create table if not exists support.attachments (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support.tickets(id) on delete cascade,
  message_id uuid references support.messages(id) on delete cascade,
  uploader_account_id uuid not null references identity.accounts(id) on delete restrict,
  object_key_hash char(64) not null check (object_key_hash ~ '^[0-9a-f]{64}$'),
  storage_object_key_ciphertext bytea,
  storage_object_key_nonce_b64 varchar(64),
  encryption_key_version smallint check (encryption_key_version between 1 and 32767),
  content_type varchar(80) not null check (content_type in (
    'image/jpeg','image/png','image/webp','application/pdf','text/plain'
  )),
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  content_sha256 char(64) not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  scan_status varchar(24) not null default 'Pending'
    check (scan_status in ('Pending','Clean','Rejected','Error')),
  status varchar(24) not null default 'PendingUpload'
    check (status in ('PendingUpload','Scanning','Available','Quarantined','Deleted','Expired')),
  expires_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (
    (storage_object_key_ciphertext is null and storage_object_key_nonce_b64 is null and encryption_key_version is null)
    or
    (storage_object_key_ciphertext is not null and storage_object_key_nonce_b64 is not null and encryption_key_version is not null)
  )
);
create index if not exists ix_support_attachments_ticket
  on support.attachments(ticket_id,created_at_utc,id);
create index if not exists ix_support_attachments_scan
  on support.attachments(scan_status,status,created_at_utc,id)
  where status in ('PendingUpload','Scanning','Quarantined');

comment on table support.attachments is
  'Private support attachment metadata only. No public URL is persisted; object keys are protected outside browser-visible data and files become downloadable only after a Clean scan result.';

create table if not exists support.escalations (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support.tickets(id) on delete cascade,
  requested_by_account_id uuid not null references identity.accounts(id) on delete restrict,
  target_role_code varchar(64) not null references admin.roles(code) on delete restrict,
  reason_safe varchar(1000) not null check (length(trim(reason_safe)) between 10 and 1000),
  status varchar(24) not null default 'Open' check (status in ('Open','Accepted','Closed','Cancelled')),
  accepted_by_account_id uuid references identity.accounts(id) on delete restrict,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);
create index if not exists ix_support_escalations_queue
  on support.escalations(status,target_role_code,created_at_utc,id);

create table if not exists support.linked_work_items (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support.tickets(id) on delete cascade,
  provider varchar(24) not null check (provider in ('GitHub','Internal')),
  work_item_kind varchar(24) not null check (work_item_kind in ('Issue','Incident','ProductTask')),
  reference_hash char(64) not null check (reference_hash ~ '^[0-9a-f]{64}$'),
  safe_label varchar(160),
  created_by_account_id uuid not null references identity.accounts(id) on delete restrict,
  created_at_utc timestamptz not null default now(),
  unique(ticket_id,provider,work_item_kind,reference_hash)
);

alter table support.messages enable row level security;
alter table support.message_reads enable row level security;
alter table support.attachments enable row level security;
alter table support.escalations enable row level security;
alter table support.linked_work_items enable row level security;
alter table support.messages force row level security;
alter table support.message_reads force row level security;
alter table support.attachments force row level security;
alter table support.escalations force row level security;
alter table support.linked_work_items force row level security;

revoke all on support.messages,support.message_reads,support.attachments,
  support.escalations,support.linked_work_items from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on support.messages,support.message_reads,support.attachments,support.escalations,support.linked_work_items from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on support.messages,support.message_reads,support.attachments,support.escalations,support.linked_work_items from authenticated';
  end if;
end $$;

-- Runtime roles receive no broad table mutation. Narrow SECURITY DEFINER
-- functions below are the user/staff write boundary.
grant usage on schema support to lifemate_edge_runtime,lifemate_admin_runtime,lifemate_worker_runtime;

create policy support_admin_read_messages on support.messages
  for select to lifemate_admin_runtime using(true);
create policy support_admin_read_reads on support.message_reads
  for select to lifemate_admin_runtime using(true);
create policy support_admin_read_attachments on support.attachments
  for select to lifemate_admin_runtime using(true);
create policy support_admin_read_escalations on support.escalations
  for select to lifemate_admin_runtime using(true);
create policy support_admin_read_linked_items on support.linked_work_items
  for select to lifemate_admin_runtime using(true);
create policy support_worker_read_attachments on support.attachments
  for select to lifemate_worker_runtime using(true);

create policy support_admin_read_tickets_existing on support.tickets
  for select to lifemate_admin_runtime using(true);
create policy support_edge_read_own_tickets on support.tickets
  for select to lifemate_edge_runtime
  using (requester_account_id=identity.account_id_for_legacy_app_user(current_setting('app.current_app_user_id',true)::uuid));

-- The Edge API may select only its caller-owned conversation rows after setting
-- app.current_app_user_id transaction-locally. It still cannot write tables.
create policy support_edge_read_own_messages on support.messages
  for select to lifemate_edge_runtime
  using (exists(
    select 1 from support.tickets t
    where t.id=ticket_id
      and t.requester_account_id=identity.account_id_for_legacy_app_user(current_setting('app.current_app_user_id',true)::uuid)
  ) and visibility='Participants');
create policy support_edge_read_own_reads on support.message_reads
  for select to lifemate_edge_runtime
  using (account_id=identity.account_id_for_legacy_app_user(current_setting('app.current_app_user_id',true)::uuid));
create policy support_edge_read_own_attachments on support.attachments
  for select to lifemate_edge_runtime
  using (exists(
    select 1 from support.tickets t
    where t.id=ticket_id
      and t.requester_account_id=identity.account_id_for_legacy_app_user(current_setting('app.current_app_user_id',true)::uuid)
  ));

grant select on support.tickets,support.messages,support.message_reads,support.attachments to lifemate_edge_runtime;
grant select on support.messages,support.message_reads,support.attachments,support.escalations,support.linked_work_items to lifemate_admin_runtime;
grant select on support.attachments to lifemate_worker_runtime;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('support.escalate','support','HIGH_RISK',true,'Escalate support tickets to an eligible workforce role and link reviewed work items'),
('support.attachments.read','support','SENSITIVE',true,'Access Clean private support attachments through signed server delivery')
on conflict(code) do update set description=excluded.description,updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code from admin.roles r
cross join (values ('support.escalate'),('support.attachments.read')) p(code)
where r.code in ('founder','super_admin','support')
on conflict do nothing;

comment on table support.messages is
  'Canonical ordered support conversation messages attached to support.tickets. Staff-only notes never appear in user conversation reads.';
comment on table support.message_reads is
  'Per-participant monotonic read cursor; no presence/typing state is source of truth.';

commit;
