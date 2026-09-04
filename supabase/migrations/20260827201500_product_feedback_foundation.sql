begin;
create schema if not exists feedback;
revoke all on schema feedback from public;
do $$ begin
 if to_regrole('anon') is not null then execute 'revoke all on schema feedback from anon'; end if;
 if to_regrole('authenticated') is not null then execute 'revoke all on schema feedback from authenticated'; end if;
end $$;
do $$ begin create type feedback.item_kind as enum ('Feedback','Nps','BugReport','FeatureRequest','Advocacy'); exception when duplicate_object then null; end $$;
do $$ begin create type feedback.item_status as enum ('Submitted','Acknowledged','Triaged','Resolved'); exception when duplicate_object then null; end $$;
create table if not exists feedback.items (
 id uuid primary key default gen_random_uuid(), app_user_id uuid not null, kind feedback.item_kind not null, status feedback.item_status not null default 'Submitted',
 product_code text not null check (product_code ~ '^[a-z][a-z0-9_-]{1,39}$'), app_version text null, build_number text null,
 nps_score smallint null check (nps_score between 0 and 10), message text null check (message is null or char_length(message) between 1 and 2000), advocacy_opt_in boolean not null default false,
 idempotency_key text not null check (char_length(idempotency_key) between 8 and 128), linked_support_ticket_id uuid null, linked_product_issue_ref text null check (linked_product_issue_ref is null or char_length(linked_product_issue_ref) <= 160),
 acknowledged_at timestamptz null, triaged_at timestamptz null, resolved_at timestamptz null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint feedback_nps_shape check ((kind = 'Nps') = (nps_score is not null)), constraint feedback_message_shape check (kind = 'Nps' or message is not null), constraint feedback_advocacy_shape check (kind <> 'Advocacy' or advocacy_opt_in), constraint feedback_idempotency_unique unique (app_user_id,idempotency_key));
create index if not exists feedback_items_queue_idx on feedback.items(status,kind,created_at desc);
alter table feedback.items enable row level security; alter table feedback.items force row level security; revoke all on feedback.items from public;
do $$ begin
 if to_regrole('anon') is not null then execute 'revoke all on feedback.items from anon'; end if;
 if to_regrole('authenticated') is not null then execute 'revoke all on feedback.items from authenticated'; end if;
end $$;
create or replace function feedback.submit_item(p_app_user_id uuid,p_kind feedback.item_kind,p_product_code text,p_app_version text,p_build_number text,p_nps_score smallint,p_message text,p_advocacy_opt_in boolean,p_idempotency_key text) returns jsonb language plpgsql security definer set search_path=pg_catalog,feedback as $$ declare v feedback.items%rowtype; begin
 if p_app_user_id is null then raise exception 'app_user_required' using errcode='22023'; end if;
 if p_product_code !~ '^[a-z][a-z0-9_-]{1,39}$' then raise exception 'product_invalid' using errcode='22023'; end if;
 if p_idempotency_key is null or char_length(btrim(p_idempotency_key)) not between 8 and 128 then raise exception 'idempotency_key_invalid' using errcode='22023'; end if;
 if p_kind <> 'Nps' and nullif(btrim(p_message),'') is null then raise exception 'message_required' using errcode='22023'; end if;
 if p_kind='Nps' and (p_nps_score is null or p_nps_score not between 0 and 10) then raise exception 'nps_score_invalid' using errcode='22023'; end if;
 if p_kind<>'Nps' and p_nps_score is not null then raise exception 'nps_score_forbidden' using errcode='22023'; end if;
 if p_kind='Advocacy' and not coalesce(p_advocacy_opt_in,false) then raise exception 'advocacy_opt_in_required' using errcode='22023'; end if;
 insert into feedback.items(app_user_id,kind,product_code,app_version,build_number,nps_score,message,advocacy_opt_in,idempotency_key) values(p_app_user_id,p_kind,lower(p_product_code),nullif(btrim(p_app_version),''),nullif(btrim(p_build_number),''),p_nps_score,nullif(btrim(p_message),''),coalesce(p_advocacy_opt_in,false),btrim(p_idempotency_key)) on conflict(app_user_id,idempotency_key) do nothing returning * into v;
 if v.id is null then select * into v from feedback.items where app_user_id=p_app_user_id and idempotency_key=btrim(p_idempotency_key); if v.kind<>p_kind or v.product_code<>lower(p_product_code) or coalesce(v.message,'')<>coalesce(nullif(btrim(p_message),''),'') or v.nps_score is distinct from p_nps_score then raise exception 'idempotency_conflict' using errcode='23505'; end if; end if;
 return jsonb_build_object('id',v.id,'kind',v.kind,'status',v.status,'productCode',v.product_code,'appVersion',v.app_version,'buildNumber',v.build_number,'npsScore',v.nps_score,'message',v.message,'advocacyOptIn',v.advocacy_opt_in,'createdAt',v.created_at); end $$;
revoke all on function feedback.submit_item(uuid,feedback.item_kind,text,text,text,smallint,text,boolean,text) from public;
do $$ begin
 if to_regrole('anon') is not null then execute 'revoke all on function feedback.submit_item(uuid,feedback.item_kind,text,text,text,smallint,text,boolean,text) from anon'; end if;
 if to_regrole('authenticated') is not null then execute 'revoke all on function feedback.submit_item(uuid,feedback.item_kind,text,text,text,smallint,text,boolean,text) from authenticated'; end if;
end $$;
grant usage on schema feedback to lifemate_edge_runtime; grant execute on function feedback.submit_item(uuid,feedback.item_kind,text,text,text,smallint,text,boolean,text) to lifemate_edge_runtime;
commit;
