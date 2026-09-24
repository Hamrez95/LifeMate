create table if not exists pregnancy.symptom_catalog_releases (
  id uuid primary key default gen_random_uuid(),
  version varchar(64) not null unique,
  status varchar(16) not null check (status in ('draft','published','retired')),
  reviewed_by varchar(160) not null,
  reviewed_at_utc timestamptz not null,
  published_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  check (
    (status = 'published' and published_at_utc is not null)
    or (status <> 'published')
  )
);

create unique index if not exists ux_pregnancy_symptom_catalog_one_published
  on pregnancy.symptom_catalog_releases ((status = 'published'))
  where status = 'published';

create table if not exists pregnancy.symptom_catalog_entries (
  release_id uuid not null references pregnancy.symptom_catalog_releases(id)
    on delete restrict,
  locale varchar(8) not null check (locale in ('en','fa')),
  code varchar(64) not null check (code ~ '^[a-z0-9][a-z0-9._-]{1,63}$'),
  display_label varchar(120) not null check (length(trim(display_label)) > 0),
  sort_order integer not null check (sort_order >= 0),
  primary key (release_id, locale, code)
);

create index if not exists ix_pregnancy_symptom_catalog_entries_release_locale_order
  on pregnancy.symptom_catalog_entries(release_id, locale, sort_order, code);

alter table pregnancy.symptom_catalog_releases enable row level security;
alter table pregnancy.symptom_catalog_releases force row level security;
alter table pregnancy.symptom_catalog_entries enable row level security;
alter table pregnancy.symptom_catalog_entries force row level security;

revoke all on pregnancy.symptom_catalog_releases from public;
revoke all on pregnancy.symptom_catalog_entries from public;

do $catalog_security$
begin
  if to_regrole('anon') is not null then
    revoke all on pregnancy.symptom_catalog_releases from anon;
    revoke all on pregnancy.symptom_catalog_entries from anon;
  end if;
  if to_regrole('authenticated') is not null then
    revoke all on pregnancy.symptom_catalog_releases from authenticated;
    revoke all on pregnancy.symptom_catalog_entries from authenticated;
  end if;
  if to_regrole('service_role') is not null then
    revoke all on pregnancy.symptom_catalog_releases from service_role;
    revoke all on pregnancy.symptom_catalog_entries from service_role;
  end if;

  grant select on pregnancy.symptom_catalog_releases to lifemate_edge_runtime;
  grant select on pregnancy.symptom_catalog_entries to lifemate_edge_runtime;
  grant select on pregnancy.symptom_catalog_releases to lifemate_backup_reader;
  grant select on pregnancy.symptom_catalog_entries to lifemate_backup_reader;

  drop policy if exists lifemate_edge_runtime_access
    on pregnancy.symptom_catalog_releases;
  drop policy if exists lifemate_edge_runtime_access
    on pregnancy.symptom_catalog_entries;
  create policy lifemate_edge_runtime_access
    on pregnancy.symptom_catalog_releases for select to lifemate_edge_runtime
    using (true);
  create policy lifemate_edge_runtime_access
    on pregnancy.symptom_catalog_entries for select to lifemate_edge_runtime
    using (true);
end
$catalog_security$;

comment on table pregnancy.symptom_catalog_releases is
  'Reviewed pregnancy symptom-catalog releases. Flutter receives only the currently published release through the LifeMate API.';
comment on table pregnancy.symptom_catalog_entries is
  'Localized labels for a reviewed pregnancy symptom code. An empty published catalog deliberately disables symptom capture.';
