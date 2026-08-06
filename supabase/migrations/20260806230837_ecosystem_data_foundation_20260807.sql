-- LifeMate ecosystem foundation. Additive/non-destructive by design.
-- Existing API columns remain during compatibility migration.

create extension if not exists pgcrypto;

create schema if not exists identity;
create schema if not exists core;
create schema if not exists ecosystem;
create schema if not exists network;
create schema if not exists security;
create schema if not exists consent;
create schema if not exists commerce;
create schema if not exists integration;
create schema if not exists analytics;
create schema if not exists care;

-- Identity: login principal != data subject.
create table if not exists identity.accounts (
    id uuid primary key,
    legacy_app_user_id uuid unique references lifemate.app_users(id) on delete restrict,
    status character varying(32) not null default 'Active'
        check (status in ('Active','Disabled','DeletionPending','Deleted')),
    home_region character varying(16),
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now()
);

create table if not exists identity.external_identities (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references identity.accounts(id) on delete cascade,
    provider character varying(40) not null,
    issuer character varying(255) not null,
    provider_subject character varying(512) not null,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Unlinked','Disabled')),
    created_at_utc timestamp with time zone not null default now(),
    last_authenticated_at_utc timestamp with time zone,
    unique(provider, issuer, provider_subject)
);
create index if not exists ix_external_identities_account
    on identity.external_identities(account_id, status);

create table if not exists identity.contact_points (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references identity.accounts(id) on delete cascade,
    kind character varying(16) not null check (kind in ('Phone','Email')),
    normalized_value_hash character varying(128) not null,
    encrypted_value bytea,
    status character varying(24) not null default 'Pending'
        check (status in ('Pending','Verified','Revoked')),
    verified_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    unique(kind, normalized_value_hash)
);
create index if not exists ix_contact_points_account_status
    on identity.contact_points(account_id, status);

create table if not exists identity.otp_challenges (
    id uuid primary key default gen_random_uuid(),
    phone_hash character varying(128) not null,
    provider character varying(40) not null,
    verifier_hash bytea not null,
    status character varying(24) not null default 'Pending'
        check (status in ('Pending','Consumed','Expired','Locked')),
    attempt_count smallint not null default 0 check (attempt_count >= 0),
    max_attempts smallint not null default 5 check (max_attempts between 1 and 20),
    expires_at_utc timestamp with time zone not null,
    resend_after_utc timestamp with time zone not null,
    consumed_at_utc timestamp with time zone,
    ip_hash character varying(128),
    device_hash character varying(128),
    created_at_utc timestamp with time zone not null default now()
);
create index if not exists ix_otp_challenges_phone_created
    on identity.otp_challenges(phone_hash, created_at_utc desc);
create index if not exists ix_otp_challenges_expiry
    on identity.otp_challenges(expires_at_utc)
    where status = 'Pending';

create table if not exists identity.account_deletion_requests (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references identity.accounts(id) on delete restrict,
    status character varying(24) not null default 'Requested'
        check (status in ('Requested','Processing','Completed','Rejected')),
    requested_at_utc timestamp with time zone not null default now(),
    processing_started_at_utc timestamp with time zone,
    completed_at_utc timestamp with time zone,
    retention_policy_version character varying(64),
    reason_code character varying(64),
    unique(account_id, status)
);

-- Core person model.
create table if not exists core.persons (
    id uuid primary key,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Inactive','Deceased','Deleted')),
    subject_category character varying(24) not null default 'Unknown'
        check (subject_category in ('Adult','Child','Dependent','Unknown')),
    home_region character varying(16),
    birth_date date,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now()
);

create table if not exists core.person_profiles (
    person_id uuid primary key references core.persons(id) on delete cascade,
    display_name character varying(120) not null,
    locale character varying(16) not null default 'fa',
    time_zone character varying(64) not null default 'Asia/Tehran',
    avatar_key character varying(80),
    profile_photo_path character varying(512),
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now()
);

create table if not exists core.account_person_links (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references identity.accounts(id) on delete cascade,
    person_id uuid not null references core.persons(id) on delete cascade,
    link_type character varying(24) not null
        check (link_type in ('Self','Parent','Guardian','LegalGuardian','Proxy')),
    status character varying(24) not null default 'Active'
        check (status in ('Active','Revoked')),
    created_at_utc timestamp with time zone not null default now(),
    revoked_at_utc timestamp with time zone,
    unique(account_id, person_id, link_type)
);
create unique index if not exists uq_account_person_self_account
    on core.account_person_links(account_id)
    where link_type='Self' and status='Active';
create unique index if not exists uq_account_person_self_person
    on core.account_person_links(person_id)
    where link_type='Self' and status='Active';
create index if not exists ix_account_person_links_person
    on core.account_person_links(person_id, status);

-- Multi-application enrollment.
create table if not exists ecosystem.applications (
    id uuid primary key default gen_random_uuid(),
    code character varying(64) not null unique,
    display_name character varying(120) not null,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Disabled')),
    created_at_utc timestamp with time zone not null default now()
);

create table if not exists ecosystem.app_enrollments (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references identity.accounts(id) on delete cascade,
    application_id uuid not null references ecosystem.applications(id) on delete restrict,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Suspended','Left')),
    enrolled_at_utc timestamp with time zone not null default now(),
    last_active_at_utc timestamp with time zone,
    unique(account_id, application_id)
);
create index if not exists ix_app_enrollments_application
    on ecosystem.app_enrollments(application_id, status);

-- Natural person relationships only; professional roles belong to domain engagements.
create table if not exists network.person_relationships (
    id uuid primary key default gen_random_uuid(),
    source_person_id uuid not null references core.persons(id) on delete restrict,
    target_person_id uuid not null references core.persons(id) on delete restrict,
    relationship_type character varying(32) not null
        check (relationship_type in ('Parent','Child','Spouse','Sibling','Guardian','Dependent')),
    status character varying(24) not null default 'Active'
        check (status in ('Active','Ended','Revoked')),
    created_at_utc timestamp with time zone not null default now(),
    ended_at_utc timestamp with time zone,
    check (source_person_id <> target_person_id),
    unique(source_person_id, target_person_id, relationship_type)
);
create index if not exists ix_person_relationships_target
    on network.person_relationships(target_person_id, status);

-- Authorization scopes and contextual grants.
create table if not exists security.scope_catalog (
    scope character varying(128) primary key,
    domain character varying(40) not null,
    sensitivity character varying(24) not null
        check (sensitivity in ('PERSONAL','SENSITIVE','HEALTH','HIGHLY_SENSITIVE')),
    description character varying(300) not null,
    created_at_utc timestamp with time zone not null default now()
);

create table if not exists security.access_grants (
    id uuid primary key default gen_random_uuid(),
    subject_person_id uuid not null references core.persons(id) on delete cascade,
    grantee_account_id uuid not null references identity.accounts(id) on delete cascade,
    grantor_person_id uuid references core.persons(id) on delete restrict,
    context_type character varying(64),
    context_id uuid,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Revoked','Expired')),
    starts_at_utc timestamp with time zone not null default now(),
    expires_at_utc timestamp with time zone,
    revoked_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    check ((context_type is null) = (context_id is null)),
    unique(subject_person_id, grantee_account_id, context_type, context_id)
);
create index if not exists ix_access_grants_grantee_active
    on security.access_grants(grantee_account_id, subject_person_id, status, expires_at_utc);
create index if not exists ix_access_grants_context
    on security.access_grants(context_type, context_id, status)
    where context_id is not null;

create table if not exists security.access_grant_scopes (
    grant_id uuid not null references security.access_grants(id) on delete cascade,
    scope character varying(128) not null references security.scope_catalog(scope) on delete restrict,
    created_at_utc timestamp with time zone not null default now(),
    primary key(grant_id, scope)
);
create index if not exists ix_access_grant_scopes_scope
    on security.access_grant_scopes(scope, grant_id);

create table if not exists security.retention_policies (
    data_category character varying(80) primary key,
    retention_days integer check (retention_days is null or retention_days >= 0),
    disposition character varying(24) not null check (disposition in ('Delete','Anonymize','Archive','Review')),
    policy_version character varying(64) not null,
    legal_basis character varying(200),
    updated_at_utc timestamp with time zone not null default now()
);

-- Versioned consent evidence.
create table if not exists consent.consent_documents (
    id uuid primary key default gen_random_uuid(),
    purpose character varying(80) not null,
    version character varying(64) not null,
    jurisdiction character varying(16) not null default '*',
    title character varying(200) not null,
    document_hash character varying(128),
    status character varying(24) not null default 'Active'
        check (status in ('Draft','Active','Retired')),
    effective_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    unique(purpose, version, jurisdiction)
);

create table if not exists consent.consent_records (
    id uuid primary key default gen_random_uuid(),
    subject_person_id uuid not null references core.persons(id) on delete restrict,
    actor_account_id uuid references identity.accounts(id) on delete restrict,
    document_id uuid not null references consent.consent_documents(id) on delete restrict,
    purpose character varying(80) not null,
    scope_key character varying(160) not null,
    data_categories character varying(64)[] not null default '{}',
    jurisdiction character varying(16) not null default '*',
    source character varying(40) not null,
    status character varying(24) not null
        check (status in ('Granted','Revoked','Expired','Superseded')),
    granted_at_utc timestamp with time zone,
    revoked_at_utc timestamp with time zone,
    expires_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now()
);
create index if not exists ix_consent_records_subject_purpose
    on consent.consent_records(subject_person_id, purpose, created_at_utc desc);
create index if not exists ix_consent_records_active
    on consent.consent_records(subject_person_id, scope_key, expires_at_utc)
    where status='Granted';

create table if not exists consent.consent_events (
    id uuid primary key default gen_random_uuid(),
    consent_record_id uuid not null references consent.consent_records(id) on delete cascade,
    actor_account_id uuid references identity.accounts(id) on delete restrict,
    event_type character varying(24) not null
        check (event_type in ('Granted','Revoked','Expired','Superseded')),
    occurred_at_utc timestamp with time zone not null default now(),
    metadata_json jsonb
);
create index if not exists ix_consent_events_record_time
    on consent.consent_events(consent_record_id, occurred_at_utc);

create table if not exists consent.data_use_consents (
    id uuid primary key default gen_random_uuid(),
    subject_person_id uuid not null references core.persons(id) on delete restrict,
    actor_account_id uuid references identity.accounts(id) on delete restrict,
    purpose character varying(80) not null,
    data_categories character varying(64)[] not null default '{}',
    jurisdiction character varying(16) not null,
    policy_version character varying(64) not null,
    source character varying(40) not null,
    status character varying(24) not null default 'OptedOut'
        check (status in ('OptedIn','OptedOut','Revoked','Expired')),
    granted_at_utc timestamp with time zone,
    revoked_at_utc timestamp with time zone,
    expires_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    unique(subject_person_id, purpose, jurisdiction, policy_version)
);
create index if not exists ix_data_use_consents_eligible
    on consent.data_use_consents(subject_person_id, purpose, expires_at_utc)
    where status='OptedIn';

-- Commercial product/capability foundation.
create table if not exists commerce.products (
    id uuid primary key default gen_random_uuid(),
    code character varying(64) not null unique,
    display_name character varying(120) not null,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Retired')),
    created_at_utc timestamp with time zone not null default now()
);

create table if not exists commerce.plans (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references commerce.products(id) on delete restrict,
    code character varying(64) not null,
    display_name character varying(120) not null,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Retired')),
    created_at_utc timestamp with time zone not null default now(),
    unique(product_id, code)
);

create table if not exists commerce.features (
    id uuid primary key default gen_random_uuid(),
    code character varying(128) not null unique,
    description character varying(300) not null,
    created_at_utc timestamp with time zone not null default now()
);

create table if not exists commerce.product_features (
    product_id uuid not null references commerce.products(id) on delete cascade,
    feature_id uuid not null references commerce.features(id) on delete cascade,
    minimum_plan_code character varying(64),
    primary key(product_id, feature_id)
);

create table if not exists commerce.prices (
    id uuid primary key default gen_random_uuid(),
    plan_id uuid not null references commerce.plans(id) on delete cascade,
    country_code character varying(2),
    currency character varying(3) not null,
    store_provider character varying(40) not null,
    billing_period_months smallint not null check (billing_period_months between 1 and 120),
    amount_minor bigint not null check (amount_minor >= 0),
    status character varying(24) not null default 'Active'
        check (status in ('Active','Retired')),
    effective_from_utc timestamp with time zone not null default now(),
    effective_to_utc timestamp with time zone,
    unique(plan_id, country_code, currency, store_provider, billing_period_months, effective_from_utc)
);

create table if not exists commerce.subscriptions (
    id uuid primary key default gen_random_uuid(),
    payer_account_id uuid not null references identity.accounts(id) on delete restrict,
    owner_account_id uuid references identity.accounts(id) on delete restrict,
    beneficiary_person_id uuid references core.persons(id) on delete restrict,
    product_id uuid not null references commerce.products(id) on delete restrict,
    plan_id uuid not null references commerce.plans(id) on delete restrict,
    provider character varying(40) not null,
    provider_reference_hash character varying(128),
    status character varying(24) not null
        check (status in ('Trial','Active','PastDue','Cancelled','Expired','Refunded')),
    starts_at_utc timestamp with time zone not null,
    current_period_end_utc timestamp with time zone,
    cancelled_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now()
);
create index if not exists ix_subscriptions_payer_status
    on commerce.subscriptions(payer_account_id, status, current_period_end_utc);
create index if not exists ix_subscriptions_beneficiary
    on commerce.subscriptions(beneficiary_person_id, status)
    where beneficiary_person_id is not null;

create table if not exists commerce.entitlements (
    id uuid primary key default gen_random_uuid(),
    grantee_account_id uuid references identity.accounts(id) on delete cascade,
    beneficiary_person_id uuid references core.persons(id) on delete cascade,
    feature_id uuid not null references commerce.features(id) on delete restrict,
    source character varying(32) not null
        check (source in ('FREE','SUBSCRIPTION','TRIAL','PROMOTION','GIFT','FAMILY_PLAN','ORGANIZATION','CLINIC','ADMIN_GRANT','LIFETIME_PURCHASE')),
    source_key character varying(160) not null,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Revoked','Expired')),
    starts_at_utc timestamp with time zone not null default now(),
    expires_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    check (grantee_account_id is not null or beneficiary_person_id is not null),
    unique(grantee_account_id, beneficiary_person_id, feature_id, source, source_key)
);
create index if not exists ix_entitlements_account_feature
    on commerce.entitlements(grantee_account_id, feature_id, status, expires_at_utc)
    where grantee_account_id is not null;
create index if not exists ix_entitlements_person_feature
    on commerce.entitlements(beneficiary_person_id, feature_id, status, expires_at_utc)
    where beneficiary_person_id is not null;

create table if not exists commerce.entitlement_events (
    id uuid primary key default gen_random_uuid(),
    entitlement_id uuid not null references commerce.entitlements(id) on delete cascade,
    event_type character varying(32) not null
        check (event_type in ('Granted','Renewed','Expired','Cancelled','Revoked','Refunded','Chargeback','TrialStarted','TrialConverted')),
    provider_event_key character varying(160),
    occurred_at_utc timestamp with time zone not null,
    recorded_at_utc timestamp with time zone not null default now(),
    metadata_json jsonb,
    unique(provider_event_key)
);

-- Transactional outbox and rebuildable read model foundation.
create table if not exists integration.outbox_messages (
    id uuid primary key default gen_random_uuid(),
    aggregate_type character varying(80) not null,
    aggregate_id uuid,
    event_type character varying(120) not null,
    idempotency_key character varying(180) not null unique,
    payload_json jsonb not null default '{}'::jsonb,
    status character varying(24) not null default 'Pending'
        check (status in ('Pending','Processing','Processed','Failed','DeadLetter')),
    available_at_utc timestamp with time zone not null default now(),
    attempt_count integer not null default 0 check (attempt_count >= 0),
    processed_at_utc timestamp with time zone,
    last_error_code character varying(80),
    created_at_utc timestamp with time zone not null default now()
);
create index if not exists ix_outbox_dispatch
    on integration.outbox_messages(status, available_at_utc, created_at_utc)
    where status in ('Pending','Failed');

create table if not exists care.daily_adherence_summary (
    person_id uuid not null references core.persons(id) on delete cascade,
    summary_date date not null,
    scheduled_count integer not null default 0 check (scheduled_count >= 0),
    taken_count integer not null default 0 check (taken_count >= 0),
    missed_count integer not null default 0 check (missed_count >= 0),
    late_count integer not null default 0 check (late_count >= 0),
    projection_version bigint not null default 0,
    rebuilt_at_utc timestamp with time zone not null default now(),
    primary key(person_id, summary_date)
);

-- Analytics boundary: default deny and auditable policy checks.
create table if not exists analytics.source_policies (
    source_category character varying(40) primary key,
    restricted boolean not null default false,
    commercial_allowed boolean not null default false,
    research_allowed boolean not null default false,
    reason character varying(300) not null,
    updated_at_utc timestamp with time zone not null default now()
);

create table if not exists analytics.export_policies (
    purpose character varying(80) primary key,
    enabled boolean not null default false,
    minimum_cohort_size integer not null default 20 check (minimum_cohort_size >= 1),
    requires_consent boolean not null default true,
    requires_legal_review boolean not null default true,
    requires_policy_review boolean not null default true,
    requires_jurisdiction_review boolean not null default true,
    updated_at_utc timestamp with time zone not null default now()
);

create table if not exists analytics.export_audit (
    id uuid primary key default gen_random_uuid(),
    purpose character varying(80) not null,
    requested_by_account_id uuid references identity.accounts(id) on delete set null,
    metric_key character varying(120) not null,
    outcome character varying(24) not null check (outcome in ('Allowed','Denied','Completed','Failed')),
    reason_code character varying(80) not null,
    cohort_size integer,
    created_at_utc timestamp with time zone not null default now()
);
create index if not exists ix_export_audit_time
    on analytics.export_audit(created_at_utc desc);

create or replace function analytics.commercial_export_allowed(
    p_source_category character varying,
    p_subject_category character varying,
    p_consent_active boolean,
    p_jurisdiction_approved boolean
) returns boolean
language sql
stable
set search_path = analytics, pg_temp
as $$
    select coalesce((
      select ep.enabled
             and ep.requires_legal_review
             and ep.requires_policy_review
             and ep.requires_jurisdiction_review
             and p_consent_active
             and p_jurisdiction_approved
             and coalesce(sp.commercial_allowed, false)
             and not coalesce(sp.restricted, true)
             and p_source_category <> 'HealthConnect'
             and p_subject_category not in ('Child','Dependent')
      from analytics.export_policies ep
      left join analytics.source_policies sp
        on sp.source_category = p_source_category
      where ep.purpose = 'commercial_aggregated_analytics'
    ), false)
$$;

-- Scope catalog.
insert into security.scope_catalog(scope, domain, sensitivity, description) values
('treatment.medication.read','treatment','HEALTH','Read medication catalog for the subject'),
('treatment.medication.write','treatment','HEALTH','Create or edit medication catalog for the subject'),
('treatment.plan.read','treatment','HEALTH','Read treatment plans for the subject'),
('treatment.plan.write','treatment','HEALTH','Create or edit treatment plans for the subject'),
('treatment.adherence.read','treatment','HEALTH','Read dose/adherence state for the subject'),
('care.events.read','care','HEALTH','Read appointments and care events for the subject'),
('care.events.write','care','HEALTH','Create or edit care events for the subject'),
('women_health.summary.read','women_health','HIGHLY_SENSITIVE','Read explicitly shareable women-health summary'),
('women_health.daily.read','women_health','HIGHLY_SENSITIVE','Read granular women-health daily data when separately allowed'),
('women_health.support.write','women_health','HIGHLY_SENSITIVE','Record a support action without private note access')
on conflict (scope) do update set
  domain=excluded.domain, sensitivity=excluded.sensitivity, description=excluded.description;

insert into ecosystem.applications(code, display_name) values
('wellmate','WellMate'),('caremate','CareMate'),('women_health','Women Health')
on conflict (code) do update set display_name=excluded.display_name;

insert into commerce.products(code, display_name) values
('wellmate','WellMate'),('caremate','CareMate'),('women_health','Women Health')
on conflict (code) do update set display_name=excluded.display_name;

insert into commerce.plans(product_id, code, display_name)
select id, 'free', 'Free' from commerce.products
on conflict (product_id, code) do update set display_name=excluded.display_name;

insert into commerce.features(code, description) values
('treatment.basic','Core medication, treatment plan and adherence capabilities'),
('care.basic','Core family/caregiver connection and permitted monitoring'),
('women_health.basic_tracking','Basic owner women-health tracking')
on conflict (code) do update set description=excluded.description;

insert into commerce.product_features(product_id, feature_id, minimum_plan_code)
select p.id, f.id, 'free'
from (values
 ('wellmate','treatment.basic'),
 ('caremate','care.basic'),
 ('women_health','women_health.basic_tracking')
) x(product_code, feature_code)
join commerce.products p on p.code=x.product_code
join commerce.features f on f.code=x.feature_code
on conflict (product_id, feature_id) do update set minimum_plan_code=excluded.minimum_plan_code;

insert into analytics.source_policies(source_category, restricted, commercial_allowed, research_allowed, reason) values
('FirstPartyUserInput',false,true,true,'Eligible only after purpose/consent/jurisdiction policy gates'),
('CaregiverInput',false,false,true,'Third-party entered health data requires stricter review'),
('ClinicianInput',false,false,true,'Professional data requires provenance and contractual review'),
('DeviceSensor',true,false,false,'Restricted by default pending device/platform policy review'),
('HealthConnect',true,false,false,'Hard blocked from commercial/pharmaceutical secondary use'),
('ImportedProvider',true,false,false,'Provider terms and provenance review required'),
('PartnerIntegration',true,false,false,'Partner terms and provenance review required'),
('SystemGenerated',false,false,true,'Derived records require linkage to eligible source data')
on conflict (source_category) do update set
  restricted=excluded.restricted,
  commercial_allowed=excluded.commercial_allowed,
  research_allowed=excluded.research_allowed,
  reason=excluded.reason,
  updated_at_utc=now();

insert into analytics.export_policies(
 purpose, enabled, minimum_cohort_size, requires_consent,
 requires_legal_review, requires_policy_review, requires_jurisdiction_review)
values ('commercial_aggregated_analytics', false, 20, true, true, true, true)
on conflict (purpose) do update set enabled=false, minimum_cohort_size=greatest(analytics.export_policies.minimum_cohort_size,20), updated_at_utc=now();

insert into security.retention_policies(data_category, retention_days, disposition, policy_version, legal_basis) values
('otp_attempts',30,'Delete','retention-v1','Security troubleshooting and abuse prevention'),
('notification_attempts',90,'Delete','retention-v1','Operational delivery troubleshooting'),
('auth_logs',90,'Review','retention-v1','Security and incident response'),
('audit_logs',730,'Archive','retention-v1','Security/accountability; jurisdiction may override'),
('health_events',null,'Review','retention-v1','User health history; deletion and legal obligations evaluated per jurisdiction'),
('analytics_datasets',180,'Delete','retention-v1','Purpose-limited derived data')
on conflict (data_category) do update set
 retention_days=excluded.retention_days, disposition=excluded.disposition,
 policy_version=excluded.policy_version, legal_basis=excluded.legal_basis, updated_at_utc=now();

-- Preserve IDs while separating Account and Person.
insert into identity.accounts(id, legacy_app_user_id, status, created_at_utc, updated_at_utc)
select id, id,
       case when status='Active' then 'Active' else 'Disabled' end,
       created_at_utc, updated_at_utc
from lifemate.app_users
on conflict (id) do update set
 legacy_app_user_id=excluded.legacy_app_user_id,
 updated_at_utc=greatest(identity.accounts.updated_at_utc, excluded.updated_at_utc);

insert into identity.external_identities(account_id, provider, issuer, provider_subject, status, created_at_utc, last_authenticated_at_utc)
select id, 'supabase_auth', 'supabase', auth_subject, 'Active', created_at_utc, updated_at_utc
from lifemate.app_users
on conflict (provider, issuer, provider_subject) do update set
 account_id=excluded.account_id,
 last_authenticated_at_utc=greatest(identity.external_identities.last_authenticated_at_utc, excluded.last_authenticated_at_utc);

insert into core.persons(id, status, subject_category, created_at_utc, updated_at_utc)
select id, 'Active', 'Unknown', created_at_utc, updated_at_utc
from lifemate.app_users
on conflict (id) do update set updated_at_utc=greatest(core.persons.updated_at_utc,excluded.updated_at_utc);

insert into core.person_profiles(person_id, display_name, locale, time_zone, avatar_key, profile_photo_path, created_at_utc, updated_at_utc)
select p.user_id, p.display_name, p.locale, p.time_zone, p.avatar_key, p.profile_photo_path, p.created_at_utc, p.updated_at_utc
from lifemate.user_profiles p
on conflict (person_id) do update set
 display_name=excluded.display_name, locale=excluded.locale, time_zone=excluded.time_zone,
 avatar_key=excluded.avatar_key, profile_photo_path=excluded.profile_photo_path,
 updated_at_utc=greatest(core.person_profiles.updated_at_utc,excluded.updated_at_utc);

insert into core.account_person_links(account_id, person_id, link_type, status, created_at_utc)
select id, id, 'Self', 'Active', created_at_utc from identity.accounts
on conflict (account_id, person_id, link_type) do update set status='Active', revoked_at_utc=null;

insert into ecosystem.app_enrollments(account_id, application_id, status, enrolled_at_utc)
select a.id, app.id, 'Active', a.created_at_utc
from identity.accounts a cross join ecosystem.applications app
where app.code in ('wellmate','caremate')
on conflict (account_id, application_id) do nothing;

-- Current free users follow the same entitlement path future paid users will use.
insert into commerce.entitlements(grantee_account_id, beneficiary_person_id, feature_id, source, source_key, status, starts_at_utc)
select a.id, l.person_id, f.id, 'FREE', 'free:v1:'||f.code, 'Active', a.created_at_utc
from identity.accounts a
join core.account_person_links l on l.account_id=a.id and l.link_type='Self' and l.status='Active'
cross join commerce.features f
where f.code in ('treatment.basic','care.basic','women_health.basic_tracking')
on conflict (grantee_account_id, beneficiary_person_id, feature_id, source, source_key) do update set status='Active';

-- Backfill contextual grants from current active caregiver relationships.
insert into security.access_grants(
 subject_person_id, grantee_account_id, grantor_person_id,
 context_type, context_id, status, starts_at_utc, created_at_utc, updated_at_utc)
select r.patient_user_id, r.caregiver_user_id, r.patient_user_id,
       'care_relationship', r.id, 'Active', r.created_at_utc, r.created_at_utc, r.updated_at_utc
from lifemate.care_relationships r
where r.status='Active'
on conflict (subject_person_id, grantee_account_id, context_type, context_id)
do update set status='Active', revoked_at_utc=null, updated_at_utc=excluded.updated_at_utc;

insert into security.access_grant_scopes(grant_id, scope)
select g.id, s.scope
from security.access_grants g
cross join (values
 ('treatment.medication.read'),
 ('treatment.plan.read'),
 ('treatment.adherence.read'),
 ('care.events.read')
) s(scope)
where g.context_type='care_relationship' and g.status='Active'
on conflict do nothing;

insert into security.access_grant_scopes(grant_id, scope)
select g.id, 'women_health.summary.read'
from security.access_grants g
join lifemate.care_relationships r on r.id=g.context_id
where g.context_type='care_relationship'
  and g.status='Active'
  and r.status='Active'
  and coalesce(r.can_view_women_calendar,false)=true
on conflict do nothing;

-- Versioned evidence from the existing care relationship consent fields.
insert into consent.consent_documents(purpose, version, jurisdiction, title, status, effective_at_utc)
select distinct 'care_sharing', r.patient_consent_version, '*', 'Legacy patient care-sharing consent', 'Active', min(r.patient_consented_at_utc)
from lifemate.care_relationships r
group by r.patient_consent_version
on conflict (purpose, version, jurisdiction) do nothing;

insert into consent.consent_records(
 subject_person_id, actor_account_id, document_id, purpose, scope_key,
 data_categories, jurisdiction, source, status, granted_at_utc,
 revoked_at_utc, created_at_utc, updated_at_utc)
select r.patient_user_id, r.patient_user_id, d.id, 'care_sharing',
       'care_relationship:'||r.id::text,
       array['treatment','care_events','women_health_summary']::character varying[],
       '*', 'legacy_care_relationship',
       case when r.status='Active' then 'Granted' else 'Revoked' end,
       r.patient_consented_at_utc, r.revoked_at_utc,
       r.created_at_utc, r.updated_at_utc
from lifemate.care_relationships r
join consent.consent_documents d
  on d.purpose='care_sharing' and d.version=r.patient_consent_version and d.jurisdiction='*'
where not exists (
 select 1 from consent.consent_records c
 where c.scope_key='care_relationship:'||r.id::text and c.purpose='care_sharing'
);

insert into consent.consent_events(consent_record_id, actor_account_id, event_type, occurred_at_utc)
select c.id, c.actor_account_id,
       case when c.status='Granted' then 'Granted' else 'Revoked' end,
       coalesce(c.revoked_at_utc,c.granted_at_utc,c.created_at_utc)
from consent.consent_records c
where c.source='legacy_care_relationship'
  and not exists (select 1 from consent.consent_events e where e.consent_record_id=c.id);

-- Add Person ownership/provenance without breaking current writers.
alter table lifemate.medications add column if not exists owner_person_id uuid;
alter table lifemate.medications add column if not exists provenance_source character varying(40) not null default 'FirstPartyUserInput';
alter table lifemate.medications add column if not exists provenance_restricted boolean not null default false;
update lifemate.medications set owner_person_id=owner_user_id where owner_person_id is null;

alter table lifemate.treatment_plans add column if not exists patient_person_id uuid;
alter table lifemate.treatment_plans add column if not exists provenance_source character varying(40) not null default 'FirstPartyUserInput';
alter table lifemate.treatment_plans add column if not exists provenance_restricted boolean not null default false;
update lifemate.treatment_plans set patient_person_id=patient_user_id where patient_person_id is null;

alter table lifemate.dose_occurrences add column if not exists patient_person_id uuid;
alter table lifemate.dose_occurrences add column if not exists provenance_source character varying(40) not null default 'SystemGenerated';
alter table lifemate.dose_occurrences add column if not exists provenance_restricted boolean not null default false;
update lifemate.dose_occurrences set patient_person_id=patient_user_id where patient_person_id is null;

alter table lifemate.dose_adherence_events add column if not exists provenance_source character varying(40) not null default 'FirstPartyUserInput';
alter table lifemate.dose_adherence_events add column if not exists provenance_restricted boolean not null default false;

alter table lifemate.care_events add column if not exists patient_person_id uuid;
alter table lifemate.care_events add column if not exists provenance_source character varying(40) not null default 'FirstPartyUserInput';
alter table lifemate.care_events add column if not exists provenance_restricted boolean not null default false;
update lifemate.care_events set patient_person_id=patient_user_id where patient_person_id is null;

alter table lifemate.women_calendar_profiles add column if not exists owner_person_id uuid;
update lifemate.women_calendar_profiles set owner_person_id=owner_user_id where owner_person_id is null;
alter table lifemate.women_calendar_episodes add column if not exists owner_person_id uuid;
alter table lifemate.women_calendar_episodes add column if not exists provenance_source character varying(40) not null default 'FirstPartyUserInput';
alter table lifemate.women_calendar_episodes add column if not exists provenance_restricted boolean not null default false;
update lifemate.women_calendar_episodes set owner_person_id=owner_user_id where owner_person_id is null;
alter table lifemate.women_calendar_daily_logs add column if not exists owner_person_id uuid;
alter table lifemate.women_calendar_daily_logs add column if not exists provenance_source character varying(40) not null default 'FirstPartyUserInput';
alter table lifemate.women_calendar_daily_logs add column if not exists provenance_restricted boolean not null default false;
update lifemate.women_calendar_daily_logs set owner_person_id=owner_user_id where owner_person_id is null;
alter table lifemate.women_calendar_support_actions add column if not exists patient_person_id uuid;
update lifemate.women_calendar_support_actions set patient_person_id=patient_user_id where patient_person_id is null;

-- Add FKs only after deterministic backfill. Columns stay nullable so old deployed API remains compatible.
do $migration$
begin
  if not exists (select 1 from pg_constraint where conname='fk_medications_owner_person') then
    alter table lifemate.medications add constraint fk_medications_owner_person foreign key(owner_person_id) references core.persons(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='fk_treatment_plans_patient_person') then
    alter table lifemate.treatment_plans add constraint fk_treatment_plans_patient_person foreign key(patient_person_id) references core.persons(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='fk_dose_occurrences_patient_person') then
    alter table lifemate.dose_occurrences add constraint fk_dose_occurrences_patient_person foreign key(patient_person_id) references core.persons(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='fk_care_events_patient_person') then
    alter table lifemate.care_events add constraint fk_care_events_patient_person foreign key(patient_person_id) references core.persons(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='fk_women_profiles_owner_person') then
    alter table lifemate.women_calendar_profiles add constraint fk_women_profiles_owner_person foreign key(owner_person_id) references core.persons(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='fk_women_episodes_owner_person') then
    alter table lifemate.women_calendar_episodes add constraint fk_women_episodes_owner_person foreign key(owner_person_id) references core.persons(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='fk_women_daily_logs_owner_person') then
    alter table lifemate.women_calendar_daily_logs add constraint fk_women_daily_logs_owner_person foreign key(owner_person_id) references core.persons(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='fk_women_support_patient_person') then
    alter table lifemate.women_calendar_support_actions add constraint fk_women_support_patient_person foreign key(patient_person_id) references core.persons(id) on delete restrict;
  end if;
end
$migration$;

-- Explicitly close the historical missing-FK gap. Fail rather than delete data if an orphan exists.
do $migration$
begin
  if exists (
    select 1 from lifemate.dose_occurrences o
    left join lifemate.treatment_schedules s on s.id=o.treatment_schedule_id
    where s.id is null
  ) then
    raise exception 'Cannot add dose occurrence schedule FK: orphan treatment_schedule_id exists';
  end if;
  if not exists (select 1 from pg_constraint where conname='FK_dose_occurrences_treatment_schedules_treatment_schedule_id') then
    alter table lifemate.dose_occurrences
      add constraint "FK_dose_occurrences_treatment_schedules_treatment_schedule_id"
      foreign key(treatment_schedule_id) references lifemate.treatment_schedules(id) on delete restrict;
  end if;
end
$migration$;

create index if not exists ix_medications_owner_person_name
  on lifemate.medications(owner_person_id,name);
create index if not exists ix_treatment_plans_person_status
  on lifemate.treatment_plans(patient_person_id,status);
create index if not exists ix_dose_occurrences_person_time
  on lifemate.dose_occurrences(patient_person_id,scheduled_at_utc,id);
create index if not exists ix_care_events_person_schedule
  on lifemate.care_events(patient_person_id,scheduled_local_date,scheduled_local_time,id);
create index if not exists ix_women_support_caregiver
  on lifemate.women_calendar_support_actions(caregiver_user_id,performed_at_utc desc);
create index if not exists ix_women_support_relationship
  on lifemate.women_calendar_support_actions(relationship_id,performed_at_utc desc);
create index if not exists ix_audit_actor_created_desc
  on lifemate.audit_logs(actor_user_id,created_at_utc desc);
create index if not exists ix_audit_resource_created_desc
  on lifemate.audit_logs(resource_type,resource_id,created_at_utc desc);

-- Remove plaintext PII lookup indexes; contact lookup moves to keyed hashes.
drop index if exists lifemate."IX_user_profiles_phone_number";
drop index if exists lifemate."IX_user_profiles_email";

-- Health-source constraints: restricted flag must be true for HealthConnect.
do $migration$
begin
  if not exists (select 1 from pg_constraint where conname='ck_medication_healthconnect_restricted') then
    alter table lifemate.medications add constraint ck_medication_healthconnect_restricted
      check (provenance_source <> 'HealthConnect' or provenance_restricted=true);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_plan_healthconnect_restricted') then
    alter table lifemate.treatment_plans add constraint ck_plan_healthconnect_restricted
      check (provenance_source <> 'HealthConnect' or provenance_restricted=true);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_occurrence_healthconnect_restricted') then
    alter table lifemate.dose_occurrences add constraint ck_occurrence_healthconnect_restricted
      check (provenance_source <> 'HealthConnect' or provenance_restricted=true);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_adherence_healthconnect_restricted') then
    alter table lifemate.dose_adherence_events add constraint ck_adherence_healthconnect_restricted
      check (provenance_source <> 'HealthConnect' or provenance_restricted=true);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_careevent_healthconnect_restricted') then
    alter table lifemate.care_events add constraint ck_careevent_healthconnect_restricted
      check (provenance_source <> 'HealthConnect' or provenance_restricted=true);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_women_episode_healthconnect_restricted') then
    alter table lifemate.women_calendar_episodes add constraint ck_women_episode_healthconnect_restricted
      check (provenance_source <> 'HealthConnect' or provenance_restricted=true);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_women_daily_healthconnect_restricted') then
    alter table lifemate.women_calendar_daily_logs add constraint ck_women_daily_healthconnect_restricted
      check (provenance_source <> 'HealthConnect' or provenance_restricted=true);
  end if;
end
$migration$;

-- Default-deny privileges for client-facing Supabase roles. The server DB role remains explicit.
do $migration$
declare schema_name text; role_name text;
begin
  foreach schema_name in array array['identity','core','ecosystem','network','security','consent','commerce','integration','analytics','care'] loop
    execute format('revoke all on schema %I from public',schema_name);
    foreach role_name in array array['anon','authenticated','service_role'] loop
      if exists (select 1 from pg_roles where rolname=role_name) then
        execute format('revoke all on schema %I from %I',schema_name,role_name);
        execute format('revoke all privileges on all tables in schema %I from %I',schema_name,role_name);
        execute format('revoke all privileges on all sequences in schema %I from %I',schema_name,role_name);
      end if;
    end loop;
  end loop;
end
$migration$;

comment on schema identity is 'Authentication principal/contact boundary. No health domain should depend on raw contact identifiers.';
comment on schema core is 'Person/data-subject foundation independent from login accounts.';
comment on schema security is 'Contextual scoped authorization and retention policy metadata.';
comment on schema consent is 'Versioned consent evidence; revocation preserves history.';
comment on schema commerce is 'Product, plan, subscription and entitlement state isolated from health data.';
comment on schema analytics is 'Policy gate only. Commercial export remains disabled by default.';
comment on function analytics.commercial_export_allowed(character varying,character varying,boolean,boolean) is
'Defense-in-depth policy helper. Returns false for HealthConnect, child/dependent subjects, missing consent/jurisdiction approval, unknown source, or while commercial exports are disabled.';
