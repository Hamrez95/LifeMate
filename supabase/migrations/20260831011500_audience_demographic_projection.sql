create or replace function audience.demographic_projection(
  p_as_of_utc timestamptz default now()
)
returns table (
  person_id uuid,
  locale character varying,
  age_years integer,
  age_bucket character varying,
  birthday_month integer,
  birthday_day integer,
  birthday_upcoming_days integer,
  gender_identity character varying
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with base as (
    select
      p.id as person_id,
      pp.locale,
      p.birth_date,
      case pp.gender_identity
        when 'Woman' then 'woman'
        when 'Man' then 'man'
        when 'NonBinary' then 'non_binary'
        when 'SelfDescribe' then 'self_describe'
        when 'PreferNotToSay' then 'prefer_not_to_say'
        else null
      end::varchar as gender_identity,
      (p_as_of_utc at time zone coalesce(nullif(pp.time_zone,''),'UTC'))::date as local_today
    from core.persons p
    join core.person_profiles pp on pp.person_id=p.id
    where p.status='Active'
  ), derived as (
    select
      b.*,
      case
        when b.birth_date is null then null
        else extract(year from age(b.local_today,b.birth_date))::integer
      end as age_years,
      case
        when b.birth_date is null then null
        else make_date(
          extract(year from b.local_today)::integer,
          extract(month from b.birth_date)::integer,
          least(
            extract(day from b.birth_date)::integer,
            extract(day from (
              date_trunc('month',make_date(
                extract(year from b.local_today)::integer,
                extract(month from b.birth_date)::integer,
                1
              )) + interval '1 month' - interval '1 day'
            ))::integer
          )
        )
      end as birthday_this_year
    from base b
  ), next_birthday as (
    select
      d.*,
      case
        when d.birth_date is null then null
        when d.birthday_this_year >= d.local_today then d.birthday_this_year
        else make_date(
          extract(year from d.local_today)::integer + 1,
          extract(month from d.birth_date)::integer,
          least(
            extract(day from d.birth_date)::integer,
            extract(day from (
              date_trunc('month',make_date(
                extract(year from d.local_today)::integer + 1,
                extract(month from d.birth_date)::integer,
                1
              )) + interval '1 month' - interval '1 day'
            ))::integer
          )
        )
      end as next_birthday
    from derived d
  )
  select
    n.person_id,
    n.locale,
    n.age_years,
    case
      when n.age_years is null then null
      when n.age_years < 18 then 'under_18'
      when n.age_years <= 24 then '18_24'
      when n.age_years <= 34 then '25_34'
      when n.age_years <= 44 then '35_44'
      when n.age_years <= 54 then '45_54'
      when n.age_years <= 64 then '55_64'
      else '65_plus'
    end::varchar as age_bucket,
    case when n.birth_date is null then null else extract(month from n.birth_date)::integer end,
    case when n.birth_date is null then null else extract(day from n.birth_date)::integer end,
    case when n.next_birthday is null then null else (n.next_birthday-n.local_today)::integer end,
    n.gender_identity
  from next_birthday n
$$;

revoke all on function audience.demographic_projection(timestamptz) from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on function audience.demographic_projection(timestamptz) from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on function audience.demographic_projection(timestamptz) from authenticated';
  end if;
end $$;
grant execute on function audience.demographic_projection(timestamptz) to lifemate_admin_runtime;

comment on function audience.demographic_projection(timestamptz) is
  'Purpose-limited campaign audience projection. Returns derived age/birthday fields and consent-aware demographic gender only; never exposes birth_date, contact endpoints, health, treatment, or cycle data.';
