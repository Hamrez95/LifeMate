begin;

create table if not exists network.circles (
  id uuid primary key default gen_random_uuid(),
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  circle_kind character varying(32) not null default 'women_health_planning',
  name character varying(80) not null,
  icon_key character varying(48),
  status character varying(20) not null default 'active',
  version integer not null default 1,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  closed_at_utc timestamptz,
  constraint ck_network_circle_name check (length(btrim(name)) between 1 and 80),
  constraint ck_network_circle_kind check (
    circle_kind in ('women_health_planning','family','care','pregnancy_support')
  ),
  constraint ck_network_circle_status check (status in ('active','closed')),
  constraint ck_network_circle_version check (version >= 1),
  constraint ck_network_circle_icon check (
    icon_key is null or length(btrim(icon_key)) between 1 and 48
  )
);

create table if not exists network.circle_members (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references network.circles(id) on delete cascade,
  person_id uuid not null references core.persons(id) on delete cascade,
  membership_role character varying(20) not null default 'member',
  membership_status character varying(20) not null default 'active',
  joined_at_utc timestamptz not null default now(),
  left_at_utc timestamptz,
  removed_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_circle_member_role check (membership_role in ('owner','member')),
  constraint ck_circle_member_status check (
    membership_status in ('active','left','removed')
  )
);

create unique index if not exists ux_circle_active_member
  on network.circle_members(circle_id, person_id)
  where membership_status = 'active';
create index if not exists ix_circle_members_person
  on network.circle_members(person_id, membership_status, updated_at_utc desc);

create table if not exists network.circle_invitations (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references network.circles(id) on delete cascade,
  inviter_person_id uuid not null references core.persons(id) on delete cascade,
  invitee_person_id uuid references core.persons(id) on delete cascade,
  invitee_contact_hash character varying(128),
  status character varying(20) not null default 'pending',
  expires_at_utc timestamptz not null,
  accepted_at_utc timestamptz,
  declined_at_utc timestamptz,
  revoked_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_circle_invite_target check (
    (invitee_person_id is not null)::int + (invitee_contact_hash is not null)::int = 1
  ),
  constraint ck_circle_invite_hash check (
    invitee_contact_hash is null or length(invitee_contact_hash) between 32 and 128
  ),
  constraint ck_circle_invite_status check (
    status in ('pending','accepted','declined','revoked','expired')
  ),
  constraint ck_circle_invite_expiry check (expires_at_utc > created_at_utc)
);

create index if not exists ix_circle_invites_person_status
  on network.circle_invitations(invitee_person_id, status, expires_at_utc desc)
  where invitee_person_id is not null;
create index if not exists ix_circle_invites_hash_status
  on network.circle_invitations(invitee_contact_hash, status, expires_at_utc desc)
  where invitee_contact_hash is not null;

create table if not exists network.circle_member_sharing_policies (
  circle_id uuid not null references network.circles(id) on delete cascade,
  person_id uuid not null references core.persons(id) on delete cascade,
  sharing_mode character varying(24) not null default 'none',
  include_period_window boolean not null default false,
  include_phase_context boolean not null default false,
  include_wellbeing_context boolean not null default false,
  version integer not null default 1,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  revoked_at_utc timestamptz,
  primary key(circle_id, person_id),
  constraint ck_circle_sharing_mode check (
    sharing_mode in ('none','planning_only','limited_context')
  ),
  constraint ck_circle_sharing_version check (version >= 1),
  constraint ck_circle_sharing_mode_fields check (
    (sharing_mode <> 'none')
    or (
      include_period_window = false
      and include_phase_context = false
      and include_wellbeing_context = false
    )
  )
);

create table if not exists network.circle_planning_events (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references network.circles(id) on delete cascade,
  created_by_person_id uuid not null references core.persons(id) on delete cascade,
  title character varying(100) not null,
  starts_on date not null,
  ends_on date not null,
  status character varying(20) not null default 'active',
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_circle_event_title check (length(btrim(title)) between 1 and 100),
  constraint ck_circle_event_range check (ends_on >= starts_on),
  constraint ck_circle_event_status check (status in ('active','cancelled'))
);

create index if not exists ix_circle_planning_events_range
  on network.circle_planning_events(circle_id, starts_on, ends_on)
  where status = 'active';

create table if not exists network.circle_audit_events (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references network.circles(id) on delete cascade,
  actor_person_id uuid references core.persons(id) on delete set null,
  action character varying(64) not null,
  subject_person_id uuid references core.persons(id) on delete set null,
  metadata_json jsonb,
  created_at_utc timestamptz not null default now(),
  constraint ck_circle_audit_action check (length(btrim(action)) between 1 and 64)
);

create index if not exists ix_circle_audit_circle_time
  on network.circle_audit_events(circle_id, created_at_utc desc);

alter table network.circles enable row level security;
alter table network.circles force row level security;
alter table network.circle_members enable row level security;
alter table network.circle_members force row level security;
alter table network.circle_invitations enable row level security;
alter table network.circle_invitations force row level security;
alter table network.circle_member_sharing_policies enable row level security;
alter table network.circle_member_sharing_policies force row level security;
alter table network.circle_planning_events enable row level security;
alter table network.circle_planning_events force row level security;
alter table network.circle_audit_events enable row level security;
alter table network.circle_audit_events force row level security;

revoke all on table network.circles from public;
revoke all on table network.circle_members from public;
revoke all on table network.circle_invitations from public;
revoke all on table network.circle_member_sharing_policies from public;
revoke all on table network.circle_planning_events from public;
revoke all on table network.circle_audit_events from public;

do $$
declare v_role text;
declare v_table text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname = v_role) then
      foreach v_table in array array[
        'circles',
        'circle_members',
        'circle_invitations',
        'circle_member_sharing_policies',
        'circle_planning_events',
        'circle_audit_events'
      ] loop
        execute format('revoke all on table network.%I from %I', v_table, v_role);
      end loop;
    end if;
  end loop;
end $$;

comment on table network.circles is
  'Reusable LifeMate Circle primitive. Membership never grants health-data authorization.';
comment on table network.circle_member_sharing_policies is
  'Member-owned Circle contribution policy. Default none; exact Women Health/Fertility consent remains authoritative and cannot be created by Circle membership.';
comment on table network.circle_planning_events is
  'Group planning data only; must never be used as a raw medical-data overlay.';

commit;