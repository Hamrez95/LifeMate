begin;

create table if not exists marketing.ai_content_generations (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references marketing.campaigns(id) on delete cascade,
  requested_by_admin_account_id uuid not null,
  goal varchar(40) not null,
  tone varchar(40) not null,
  language varchar(8) not null,
  key_message varchar(500),
  call_to_action varchar(240),
  variants_json jsonb not null,
  generation_mode varchar(40) not null default 'deterministic_fallback',
  model_status varchar(40) not null default 'not_configured',
  request_hash varchar(64) not null,
  idempotency_key varchar(180) not null,
  created_at_utc timestamptz not null default now(),
  constraint marketing_ai_content_goal_check check (
    goal in ('awareness','launch','education','engagement','retention')
  ),
  constraint marketing_ai_content_tone_check check (
    tone in ('warm','clear','energetic','professional')
  ),
  constraint marketing_ai_content_language_check check (language in ('fa','en')),
  constraint marketing_ai_content_mode_check check (
    generation_mode in ('deterministic_fallback','model')
  ),
  constraint marketing_ai_content_model_status_check check (
    model_status in ('not_configured','available','unavailable')
  ),
  constraint marketing_ai_content_request_hash_check check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint marketing_ai_content_idempotency_key_check check (
    idempotency_key ~ '^[A-Za-z0-9._:-]{8,180}$'
  ),
  constraint marketing_ai_content_variants_shape_check check (
    jsonb_typeof(variants_json)='array' and jsonb_array_length(variants_json) between 1 and 5
  ),
  unique(requested_by_admin_account_id,idempotency_key)
);

create index if not exists ix_marketing_ai_content_generations_campaign_created
  on marketing.ai_content_generations(campaign_id,created_at_utc desc,id desc);

create table if not exists marketing.ai_content_generation_events (
  id bigint generated always as identity primary key,
  generation_id uuid not null references marketing.ai_content_generations(id) on delete cascade,
  event_type varchar(40) not null,
  actor_admin_account_id uuid not null,
  event_at_utc timestamptz not null default now(),
  evidence_json jsonb not null default '{}'::jsonb
);

create or replace function marketing.reject_ai_content_event_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'marketing.ai_content_generation_events is append-only';
end
$$;

drop trigger if exists trg_marketing_ai_content_generation_events_immutable
  on marketing.ai_content_generation_events;
create trigger trg_marketing_ai_content_generation_events_immutable
before update or delete on marketing.ai_content_generation_events
for each row execute function marketing.reject_ai_content_event_mutation();

alter table marketing.ai_content_generations enable row level security;
alter table marketing.ai_content_generation_events enable row level security;

create or replace view admin.marketing_ai_content_generations_v1
with (security_invoker=false)
as
select
  g.id,
  g.campaign_id,
  g.requested_by_admin_account_id,
  g.goal,
  g.tone,
  g.language,
  g.key_message,
  g.call_to_action,
  g.variants_json,
  g.generation_mode,
  g.model_status,
  g.created_at_utc
from marketing.ai_content_generations g;

revoke all on admin.marketing_ai_content_generations_v1 from public;
grant select on admin.marketing_ai_content_generations_v1 to lifemate_admin_runtime;

create or replace function admin.record_marketing_ai_content_generation(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_goal varchar,
  p_tone varchar,
  p_language varchar,
  p_key_message varchar,
  p_call_to_action varchar,
  p_variants_json jsonb,
  p_generation_mode varchar,
  p_model_status varchar,
  p_idempotency_key varchar,
  p_request_hash varchar
)
returns jsonb
language plpgsql
security definer
set search_path=admin,marketing,pg_temp
as $$
declare
  v_existing marketing.ai_content_generations%rowtype;
  v_id uuid;
begin
  if not exists(select 1 from marketing.campaigns where id=p_campaign_id) then
    return jsonb_build_object(
      'httpStatus',404,'code','marketing_campaign_not_found','replayed',false
    );
  end if;

  if p_goal not in ('awareness','launch','education','engagement','retention')
     or p_tone not in ('warm','clear','energetic','professional')
     or p_language not in ('fa','en')
     or p_generation_mode not in ('deterministic_fallback','model')
     or p_model_status not in ('not_configured','available','unavailable')
     or p_request_hash !~ '^[0-9a-f]{64}$'
     or p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,180}$'
     or jsonb_typeof(p_variants_json) <> 'array'
     or jsonb_array_length(p_variants_json) not between 1 and 5 then
    return jsonb_build_object(
      'httpStatus',400,'code','marketing_ai_content_invalid','replayed',false
    );
  end if;

  select * into v_existing
  from marketing.ai_content_generations
  where requested_by_admin_account_id=p_actor_account_id
    and idempotency_key=p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object(
        'httpStatus',409,
        'code','idempotency_conflict',
        'generationId',v_existing.id,
        'replayed',false
      );
    end if;
    return jsonb_build_object(
      'httpStatus',200,
      'code','ok',
      'generationId',v_existing.id,
      'replayed',true
    );
  end if;

  insert into marketing.ai_content_generations(
    campaign_id,requested_by_admin_account_id,goal,tone,language,key_message,
    call_to_action,variants_json,generation_mode,model_status,request_hash,idempotency_key
  ) values (
    p_campaign_id,p_actor_account_id,p_goal,p_tone,p_language,p_key_message,
    p_call_to_action,p_variants_json,p_generation_mode,p_model_status,p_request_hash,p_idempotency_key
  ) returning id into v_id;

  insert into marketing.ai_content_generation_events(
    generation_id,event_type,actor_admin_account_id,evidence_json
  ) values (
    v_id,
    'Generated',
    p_actor_account_id,
    jsonb_build_object(
      'campaignId',p_campaign_id,
      'goal',p_goal,
      'tone',p_tone,
      'language',p_language,
      'generationMode',p_generation_mode,
      'modelStatus',p_model_status,
      'requestHash',p_request_hash
    )
  );

  return jsonb_build_object(
    'httpStatus',201,'code','created','generationId',v_id,'replayed',false
  );
exception
  when unique_violation then
    select * into v_existing
    from marketing.ai_content_generations
    where requested_by_admin_account_id=p_actor_account_id
      and idempotency_key=p_idempotency_key;
    if v_existing.request_hash=p_request_hash then
      return jsonb_build_object(
        'httpStatus',200,'code','ok','generationId',v_existing.id,'replayed',true
      );
    end if;
    return jsonb_build_object(
      'httpStatus',409,'code','idempotency_conflict','replayed',false
    );
end
$$;

revoke all on function admin.record_marketing_ai_content_generation(
  uuid,uuid,varchar,varchar,varchar,varchar,varchar,jsonb,varchar,varchar,varchar,varchar
) from public;
grant execute on function admin.record_marketing_ai_content_generation(
  uuid,uuid,varchar,varchar,varchar,varchar,varchar,jsonb,varchar,varchar,varchar,varchar
) to lifemate_admin_runtime;

commit;
