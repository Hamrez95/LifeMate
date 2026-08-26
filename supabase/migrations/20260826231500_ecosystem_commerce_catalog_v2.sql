begin;

-- #486 Ecosystem Commerce Catalog v2.
-- Additive extension of the existing canonical commerce foundation.
-- Legacy WellMate/CareMate product rows remain for compatibility; new catalog
-- publication uses the combined wellmate-caremate Product.

alter table commerce.products
  add column if not exists updated_at_utc timestamptz not null default now(),
  add column if not exists lifecycle_status text;

update commerce.products
set lifecycle_status = case status when 'Active' then 'Published' else 'Retired' end
where lifecycle_status is null;

alter table commerce.products
  alter column lifecycle_status set default 'Published',
  alter column lifecycle_status set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='commerce.products'::regclass
      and conname='products_lifecycle_status_check'
  ) then
    alter table commerce.products
      add constraint products_lifecycle_status_check
      check (lifecycle_status in ('Hidden','Published','Retired'));
  end if;
end $$;

create table if not exists commerce.offers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references commerce.products(id) on delete restrict,
  plan_id uuid references commerce.plans(id) on delete restrict,
  code varchar(64) not null,
  display_name varchar(120) not null,
  duration_months smallint not null check (duration_months between 1 and 120),
  status text not null default 'Hidden' check (status in ('Hidden','Published','Retired')),
  gift_eligible boolean not null default true,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  unique(product_id, code)
);
create index if not exists ix_commerce_offers_product_status
  on commerce.offers(product_id,status,duration_months,id);

-- Existing prices remain compatible with plan_id while offer_id establishes the
-- canonical Product -> Offer -> Versioned Price chain for v2 consumers.
alter table commerce.prices
  add column if not exists offer_id uuid references commerce.offers(id) on delete restrict;
create index if not exists ix_commerce_prices_offer_effective
  on commerce.prices(offer_id,status,effective_from_utc desc,id desc)
  where offer_id is not null;

create table if not exists commerce.offer_entitlements (
  offer_id uuid not null references commerce.offers(id) on delete cascade,
  feature_id uuid not null references commerce.features(id) on delete restrict,
  quantity_limit integer check (quantity_limit is null or quantity_limit >= 0),
  policy_key varchar(128),
  created_at_utc timestamptz not null default now(),
  primary key(offer_id, feature_id)
);

create table if not exists commerce.bundles (
  id uuid primary key default gen_random_uuid(),
  code varchar(64) not null unique,
  display_name varchar(120) not null,
  status text not null default 'Hidden' check (status in ('Hidden','Published','Retired')),
  gift_eligible boolean not null default true,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1)
);

create table if not exists commerce.bundle_items (
  bundle_id uuid not null references commerce.bundles(id) on delete cascade,
  offer_id uuid not null references commerce.offers(id) on delete restrict,
  quantity smallint not null default 1 check (quantity between 1 and 32),
  created_at_utc timestamptz not null default now(),
  primary key(bundle_id, offer_id)
);

create table if not exists commerce.catalog_policies (
  product_id uuid not null references commerce.products(id) on delete cascade,
  policy_key varchar(128) not null,
  value_json jsonb not null,
  value_type text not null check (value_type in ('integer','boolean','string','json')),
  status text not null default 'Active' check (status in ('Active','Retired')),
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  primary key(product_id, policy_key),
  check (jsonb_typeof(value_json) is not null)
);
create index if not exists ix_commerce_catalog_policies_product_status
  on commerce.catalog_policies(product_id,status,policy_key);

create table if not exists commerce.bundle_prices (
  id uuid primary key default gen_random_uuid(),
  bundle_id uuid not null references commerce.bundles(id) on delete restrict,
  country_code varchar(2),
  currency varchar(3) not null check (currency ~ '^[A-Z]{3}$'),
  store_provider varchar(40) not null,
  billing_period_months smallint not null check (billing_period_months between 1 and 120),
  amount_minor bigint not null check (amount_minor >= 0),
  status text not null default 'Active' check (status in ('Active','Retired')),
  effective_from_utc timestamptz not null default now(),
  effective_to_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  check (effective_to_utc is null or effective_to_utc > effective_from_utc),
  unique(bundle_id,country_code,currency,store_provider,billing_period_months,effective_from_utc)
);

create table if not exists commerce.discount_rules (
  id uuid primary key default gen_random_uuid(),
  code varchar(64) not null unique,
  scope text not null check (scope in ('Item','Bundle','Cart')),
  rule_json jsonb not null check (jsonb_typeof(rule_json)='object'),
  discount_type text not null check (discount_type in ('Percentage','FixedAmount')),
  percentage_basis_points integer check (percentage_basis_points between 1 and 10000),
  fixed_amount_minor bigint check (fixed_amount_minor > 0),
  currency varchar(3),
  status text not null default 'Draft' check (status in ('Draft','Active','Paused','Retired')),
  starts_at_utc timestamptz,
  ends_at_utc timestamptz,
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (ends_at_utc is null or starts_at_utc is null or ends_at_utc > starts_at_utc),
  check (
    (discount_type='Percentage' and percentage_basis_points is not null and fixed_amount_minor is null and currency is null)
    or
    (discount_type='FixedAmount' and percentage_basis_points is null and fixed_amount_minor is not null and currency ~ '^[A-Z]{3}$')
  )
);

alter table commerce.offers enable row level security;
alter table commerce.offer_entitlements enable row level security;
alter table commerce.bundles enable row level security;
alter table commerce.bundle_items enable row level security;
alter table commerce.catalog_policies enable row level security;
alter table commerce.bundle_prices enable row level security;
alter table commerce.discount_rules enable row level security;
alter table commerce.promotions enable row level security;
alter table commerce.discount_codes enable row level security;

revoke all on commerce.offers, commerce.offer_entitlements, commerce.bundles,
  commerce.bundle_items, commerce.catalog_policies, commerce.bundle_prices,
  commerce.discount_rules from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on commerce.offers, commerce.offer_entitlements, commerce.bundles, commerce.bundle_items, commerce.catalog_policies, commerce.bundle_prices, commerce.discount_rules from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on commerce.offers, commerce.offer_entitlements, commerce.bundles, commerce.bundle_items, commerce.catalog_policies, commerce.bundle_prices, commerce.discount_rules from authenticated';
  end if;
end $$;

grant select on commerce.offers, commerce.offer_entitlements, commerce.bundles,
  commerce.bundle_items, commerce.catalog_policies, commerce.bundle_prices,
  commerce.discount_rules to lifemate_admin_runtime;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'offers','offer_entitlements','bundles','bundle_items','catalog_policies',
    'bundle_prices','discount_rules','promotions','discount_codes'
  ] loop
    if not exists (
      select 1 from pg_policies
      where schemaname='commerce' and tablename=v_table
        and policyname='lifemate_admin_runtime_read'
    ) then
      execute format(
        'create policy lifemate_admin_runtime_read on commerce.%I for select to lifemate_admin_runtime using (true)',
        v_table
      );
    end if;
  end loop;
end $$;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('commerce.catalog.write','commerce','HIGH_RISK',true,'Manage ecosystem products, offers, bundles and configurable free-tier catalog policy through audited server workflows')
on conflict (code) do update set description=excluded.description, updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'commerce.catalog.write'
from admin.roles r
where r.code in ('founder','super_admin','product')
on conflict do nothing;

insert into commerce.products(code,display_name,status,lifecycle_status,created_at_utc,updated_at_utc) values
('wellmate-caremate','WellMate + CareMate','Active','Published',now(),now()),
('period-calendar','Period Calendar','Active','Published',now(),now()),
('cocoonmate','CocoonMate','Active','Hidden',now(),now()),
('fitmate','FitMate','Active','Hidden',now(),now())
on conflict (code) do update set
  display_name=excluded.display_name,
  lifecycle_status=case when commerce.products.lifecycle_status='Retired' then commerce.products.lifecycle_status else excluded.lifecycle_status end,
  updated_at_utc=now();

update commerce.products
set lifecycle_status='Hidden', updated_at_utc=now()
where code in ('wellmate','caremate','women_health') and lifecycle_status <> 'Retired';

insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version)
select p.id,'free.medications.max','3'::jsonb,'integer','Active',1
from commerce.products p where p.code='wellmate-caremate'
on conflict (product_id,policy_key) do nothing;
insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version)
select p.id,'free.visits.max','1'::jsonb,'integer','Active',1
from commerce.products p where p.code='wellmate-caremate'
on conflict (product_id,policy_key) do nothing;

commit;
