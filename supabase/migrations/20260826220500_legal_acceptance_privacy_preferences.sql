begin;

-- Mandatory registration acceptance and optional privacy preferences are separate
-- contracts. Existing consent/data-use tables remain the source of truth for
-- optional decisions; this migration does not create a parallel consent store.

alter table consent.consent_documents
  add column if not exists content_uri text;

alter table consent.consent_documents
  drop constraint if exists ck_consent_documents_content_uri;
alter table consent.consent_documents
  add constraint ck_consent_documents_content_uri
  check (content_uri is null or content_uri ~ '^https://');

alter table identity.accounts
  add column if not exists registration_completed_at_utc timestamptz,
  add column if not exists registration_policy_version varchar(120);

-- Existing accounts predate the explicit gate and must remain usable. New accounts
-- created after this migration start incomplete until the canonical finalize function
-- confirms every currently-required legal document.
update identity.accounts
set registration_completed_at_utc = coalesce(registration_completed_at_utc, created_at_utc),
    registration_policy_version = coalesce(registration_policy_version, 'legacy-pre-legal-gate')
where registration_completed_at_utc is null;

alter table identity.accounts
  alter column registration_completed_at_utc drop default;

create table if not exists consent.legal_acceptances (
  account_id uuid not null references identity.accounts(id) on delete restrict,
  actor_account_id uuid not null references identity.accounts(id) on delete restrict,
  document_id uuid not null references consent.consent_documents(id) on delete restrict,
  document_hash varchar(160) not null,
  source varchar(64) not null,
  accepted_at_utc timestamptz not null default now(),
  primary key (account_id, document_id),
  check (actor_account_id = account_id),
  check (source ~ '^[a-z][a-z0-9._-]{2,63}$')
);

create table if not exists consent.preference_purposes (
  purpose varchar(80) primary key,
  category varchar(32) not null check (category in ('Promotional','Research','Personalization')),
  channel varchar(16) check (channel is null or channel in ('SMS','Push','Email')),
  policy_version varchar(64) not null,
  default_enabled boolean not null default false,
  user_mutable boolean not null default true,
  status varchar(16) not null default 'Active' check (status in ('Active','Retired')),
  description varchar(240) not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (purpose ~ '^[a-z][a-z0-9._-]{2,79}$')
);

create table if not exists consent.data_use_consent_events (
  id uuid primary key default gen_random_uuid(),
  data_use_consent_id uuid not null references consent.data_use_consents(id) on delete restrict,
  actor_account_id uuid not null references identity.accounts(id) on delete restrict,
  event_type varchar(24) not null check (event_type in ('OptedIn','OptedOut','Revoked','Expired')),
  source varchar(64) not null,
  occurred_at_utc timestamptz not null default now(),
  metadata_json jsonb not null default '{}'::jsonb,
  check (source ~ '^[a-z][a-z0-9._-]{2,63}$')
);

create index if not exists ix_legal_acceptances_account
  on consent.legal_acceptances(account_id, accepted_at_utc desc);
create index if not exists ix_data_use_consent_events_subject
  on consent.data_use_consent_events(data_use_consent_id, occurred_at_utc desc);

insert into consent.preference_purposes(
  purpose, category, channel, policy_version, default_enabled, user_mutable, description
) values
  ('promotional_sms','Promotional','SMS','v1',false,true,'Receive optional LifeMate offers and promotions by SMS.'),
  ('promotional_push','Promotional','Push','v1',false,true,'Receive optional LifeMate offers and promotions by push notification.'),
  ('promotional_email','Promotional','Email','v1',false,true,'Receive optional LifeMate offers and promotions by email.'),
  ('research','Research',null,'v1',false,true,'Allow eligible data use for approved research workflows subject to separate safeguards.'),
  ('personalization','Personalization',null,'v1',false,true,'Allow optional non-clinical product personalization.')
on conflict (purpose) do nothing;

alter table consent.legal_acceptances enable row level security;
alter table consent.preference_purposes enable row level security;
alter table consent.data_use_consent_events enable row level security;
alter table consent.legal_acceptances force row level security;
alter table consent.preference_purposes force row level security;
alter table consent.data_use_consent_events force row level security;

-- The healthcare runtime receives no direct table privileges. It can only execute
-- the narrow SECURITY DEFINER contracts below. Browser roles receive nothing.
revoke all on consent.legal_acceptances from public;
revoke all on consent.preference_purposes from public;
revoke all on consent.data_use_consent_events from public;
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','lifemate_edge_runtime'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on consent.legal_acceptances from %I', v_role);
      execute format('revoke all on consent.preference_purposes from %I', v_role);
      execute format('revoke all on consent.data_use_consent_events from %I', v_role);
    end if;
  end loop;
end
$$;

create or replace function consent.current_registration_legal_documents(
  p_jurisdiction varchar default 'GLOBAL'
) returns table(
  id uuid,
  purpose varchar,
  version varchar,
  jurisdiction varchar,
  title varchar,
  document_hash varchar,
  content_uri text,
  effective_at_utc timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, consent
as $$
  select distinct on (d.purpose)
    d.id, d.purpose, d.version, d.jurisdiction, d.title,
    d.document_hash, d.content_uri, d.effective_at_utc
  from consent.consent_documents d
  where d.purpose in ('legal_terms','privacy_notice')
    and d.status='Active'
    and d.effective_at_utc <= now()
    and d.jurisdiction in (p_jurisdiction, 'GLOBAL')
  order by d.purpose,
    case when d.jurisdiction=p_jurisdiction then 0 else 1 end,
    d.effective_at_utc desc,
    d.created_at_utc desc
$$;

create or replace function consent.finalize_registration_legal_acceptance(
  p_app_user_id uuid,
  p_acceptances jsonb,
  p_source varchar default 'registration',
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, consent, identity, core
as $$
declare
  v_account_id uuid;
  v_required record;
  v_match jsonb;
  v_count integer := 0;
  v_policy_parts text[] := array[]::text[];
begin
  if p_source is null or p_source !~ '^[a-z][a-z0-9._-]{2,63}$' then
    raise exception 'legal_acceptance_source_invalid' using errcode='22023';
  end if;
  if p_acceptances is null or jsonb_typeof(p_acceptances) <> 'array' then
    p_acceptances := '[]'::jsonb;
  end if;

  select identity.account_id_for_legacy_app_user(p_app_user_id) into v_account_id;
  if v_account_id is null then
    raise exception 'account_not_found' using errcode='P0002';
  end if;

  for v_required in
    select * from consent.current_registration_legal_documents(p_jurisdiction)
  loop
    v_count := v_count + 1;
    select elem into v_match
    from jsonb_array_elements(p_acceptances) elem
    where elem->>'documentId'=v_required.id::text
      and elem->>'documentHash'=v_required.document_hash
    limit 1;

    if v_match is null then
      return jsonb_build_object(
        'completed', false,
        'code', 'legal_acceptance_required',
        'missingDocumentId', v_required.id,
        'purpose', v_required.purpose
      );
    end if;

    insert into consent.legal_acceptances(
      account_id, actor_account_id, document_id, document_hash, source
    ) values (
      v_account_id, v_account_id, v_required.id, v_required.document_hash, p_source
    ) on conflict (account_id, document_id) do nothing;

    v_policy_parts := array_append(
      v_policy_parts,
      v_required.purpose || ':' || v_required.version || ':' || v_required.document_hash
    );
  end loop;

  update identity.accounts
  set registration_completed_at_utc=coalesce(registration_completed_at_utc, now()),
      registration_policy_version=case
        when v_count=0 then 'no-active-legal-documents'
        else array_to_string(v_policy_parts, '|')
      end,
      updated_at_utc=now()
  where id=v_account_id;

  return jsonb_build_object(
    'completed', true,
    'requiredDocumentCount', v_count,
    'registrationPolicyVersion', case
      when v_count=0 then 'no-active-legal-documents'
      else array_to_string(v_policy_parts, '|')
    end
  );
end;
$$;

create or replace function consent.registration_status_for_app_user(
  p_app_user_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, consent, identity
as $$
  with account_row as (
    select a.id, a.registration_completed_at_utc, a.registration_policy_version
    from identity.accounts a
    where a.id=identity.account_id_for_legacy_app_user(p_app_user_id)
  ), required_docs as (
    select * from consent.current_registration_legal_documents(p_jurisdiction)
  )
  select jsonb_build_object(
    'completed', ar.registration_completed_at_utc is not null,
    'completedAtUtc', ar.registration_completed_at_utc,
    'registrationPolicyVersion', ar.registration_policy_version,
    'requiredDocuments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'purpose', d.purpose,
        'version', d.version,
        'jurisdiction', d.jurisdiction,
        'title', d.title,
        'documentHash', d.document_hash,
        'contentUri', d.content_uri,
        'effectiveAtUtc', d.effective_at_utc
      ) order by d.purpose)
      from required_docs d
    ), '[]'::jsonb)
  )
  from account_row ar
$$;

create or replace function consent.account_privacy_preferences(
  p_app_user_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, consent, identity, core
as $$
  with account_row as (
    select identity.account_id_for_legacy_app_user(p_app_user_id) as account_id
  ), person_row as (
    select l.person_id
    from core.account_person_links l, account_row a
    where l.account_id=a.account_id and l.link_type='Self' and l.status='Active'
    order by l.created_at_utc
    limit 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'purpose', p.purpose,
    'category', p.category,
    'channel', p.channel,
    'policyVersion', p.policy_version,
    'enabled', coalesce(c.status='OptedIn', p.default_enabled),
    'explicit', c.id is not null,
    'userMutable', p.user_mutable,
    'description', p.description,
    'updatedAtUtc', c.updated_at_utc
  ) order by p.category,p.purpose), '[]'::jsonb)
  from consent.preference_purposes p
  left join person_row pr on true
  left join consent.data_use_consents c
    on c.subject_person_id=pr.person_id
   and c.purpose=p.purpose
   and c.jurisdiction=p_jurisdiction
   and c.policy_version=p.policy_version
  where p.status='Active'
$$;

create or replace function consent.set_account_privacy_preference(
  p_app_user_id uuid,
  p_purpose varchar,
  p_enabled boolean,
  p_source varchar default 'privacy_center',
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, consent, identity, core
as $$
declare
  v_account_id uuid;
  v_person_id uuid;
  v_catalog consent.preference_purposes%rowtype;
  v_consent consent.data_use_consents%rowtype;
  v_status varchar := case when p_enabled then 'OptedIn' else 'OptedOut' end;
begin
  select * into v_catalog from consent.preference_purposes
  where purpose=p_purpose and status='Active' and user_mutable=true;
  if not found then
    raise exception 'privacy_preference_unknown' using errcode='22023';
  end if;
  if p_source is null or p_source !~ '^[a-z][a-z0-9._-]{2,63}$' then
    raise exception 'privacy_preference_source_invalid' using errcode='22023';
  end if;

  select identity.account_id_for_legacy_app_user(p_app_user_id) into v_account_id;
  select l.person_id into v_person_id
  from core.account_person_links l
  where l.account_id=v_account_id and l.link_type='Self' and l.status='Active'
  order by l.created_at_utc
  limit 1;
  if v_account_id is null or v_person_id is null then
    raise exception 'privacy_preference_identity_missing' using errcode='P0002';
  end if;

  insert into consent.data_use_consents(
    id, subject_person_id, actor_account_id, purpose, data_categories,
    jurisdiction, policy_version, source, status, granted_at_utc,
    revoked_at_utc, expires_at_utc, created_at_utc, updated_at_utc
  ) values (
    gen_random_uuid(), v_person_id, v_account_id, p_purpose, array[]::varchar[],
    p_jurisdiction, v_catalog.policy_version, p_source, v_status,
    case when p_enabled then now() else null end,
    case when p_enabled then null else now() end,
    null, now(), now()
  )
  on conflict (subject_person_id,purpose,jurisdiction,policy_version)
  do update set
    actor_account_id=excluded.actor_account_id,
    source=excluded.source,
    status=excluded.status,
    granted_at_utc=case when excluded.status='OptedIn' then now() else consent.data_use_consents.granted_at_utc end,
    revoked_at_utc=case when excluded.status='OptedIn' then null else now() end,
    updated_at_utc=now()
  returning * into v_consent;

  insert into consent.data_use_consent_events(
    data_use_consent_id, actor_account_id, event_type, source, metadata_json
  ) values (
    v_consent.id, v_account_id, v_status, p_source,
    jsonb_build_object('purpose',p_purpose,'policyVersion',v_catalog.policy_version)
  );

  return jsonb_build_object(
    'purpose',p_purpose,
    'policyVersion',v_catalog.policy_version,
    'enabled',p_enabled,
    'updatedAtUtc',v_consent.updated_at_utc
  );
end;
$$;

create or replace function consent.account_allows_optional_purpose(
  p_account_id uuid,
  p_purpose varchar,
  p_jurisdiction varchar default 'GLOBAL'
) returns boolean
language sql
stable
security definer
set search_path = pg_catalog, consent, core
as $$
  select coalesce((
    select case when c.id is null then p.default_enabled else c.status='OptedIn' end
    from consent.preference_purposes p
    left join core.account_person_links l
      on l.account_id=p_account_id and l.link_type='Self' and l.status='Active'
    left join consent.data_use_consents c
      on c.subject_person_id=l.person_id
     and c.purpose=p.purpose
     and c.jurisdiction=p_jurisdiction
     and c.policy_version=p.policy_version
    where p.purpose=p_purpose and p.status='Active'
    limit 1
  ), false)
$$;

revoke all on function consent.current_registration_legal_documents(varchar) from public;
revoke all on function consent.finalize_registration_legal_acceptance(uuid,jsonb,varchar,varchar) from public;
revoke all on function consent.registration_status_for_app_user(uuid,varchar) from public;
revoke all on function consent.account_privacy_preferences(uuid,varchar) from public;
revoke all on function consent.set_account_privacy_preference(uuid,varchar,boolean,varchar,varchar) from public;
revoke all on function consent.account_allows_optional_purpose(uuid,varchar,varchar) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function consent.current_registration_legal_documents(varchar) from anon;
    revoke all on function consent.finalize_registration_legal_acceptance(uuid,jsonb,varchar,varchar) from anon;
    revoke all on function consent.registration_status_for_app_user(uuid,varchar) from anon;
    revoke all on function consent.account_privacy_preferences(uuid,varchar) from anon;
    revoke all on function consent.set_account_privacy_preference(uuid,varchar,boolean,varchar,varchar) from anon;
    revoke all on function consent.account_allows_optional_purpose(uuid,varchar,varchar) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function consent.current_registration_legal_documents(varchar) from authenticated;
    revoke all on function consent.finalize_registration_legal_acceptance(uuid,jsonb,varchar,varchar) from authenticated;
    revoke all on function consent.registration_status_for_app_user(uuid,varchar) from authenticated;
    revoke all on function consent.account_privacy_preferences(uuid,varchar) from authenticated;
    revoke all on function consent.set_account_privacy_preference(uuid,varchar,boolean,varchar,varchar) from authenticated;
    revoke all on function consent.account_allows_optional_purpose(uuid,varchar,varchar) from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant execute on function consent.current_registration_legal_documents(varchar) to lifemate_edge_runtime;
    grant execute on function consent.finalize_registration_legal_acceptance(uuid,jsonb,varchar,varchar) to lifemate_edge_runtime;
    grant execute on function consent.registration_status_for_app_user(uuid,varchar) to lifemate_edge_runtime;
    grant execute on function consent.account_privacy_preferences(uuid,varchar) to lifemate_edge_runtime;
    grant execute on function consent.set_account_privacy_preference(uuid,varchar,boolean,varchar,varchar) to lifemate_edge_runtime;
    grant execute on function consent.account_allows_optional_purpose(uuid,varchar,varchar) to lifemate_edge_runtime;
  end if;
end
$$;

comment on table consent.legal_acceptances is
  'Immutable evidence that an Account explicitly accepted a specific required legal document version/hash. Admin acceptance on behalf of a user is structurally prohibited.';
comment on table consent.preference_purposes is
  'Catalog of optional privacy/communication purposes. User decisions remain in consent.data_use_consents.';
comment on table consent.data_use_consent_events is
  'Append-oriented history for optional data-use/privacy preference changes; no raw health payloads.';

commit;
