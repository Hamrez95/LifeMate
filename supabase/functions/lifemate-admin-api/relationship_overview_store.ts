import type { AdminSql } from "./database_client.ts";
import type { RelationshipOverviewQuery } from "./relationships.ts";

function iso(value: unknown): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

type Row = Record<string, unknown>;

export type RelationshipOverviewItem = {
  id: string;
  kind: "relationship" | "consent" | "access_grant";
  status: string;
  subjectPersonId: string | null;
  type: string | null;
  purpose: string | null;
  context: string | null;
  scopeCount: number | null;
  version: number | null;
  scopes: string[] | null;
  startedAtUtc: string | null;
  endedAtUtc: string | null;
  occurredAtUtc: string;
};

function mapItem(row: Row): RelationshipOverviewItem {
  return {
    id: String(row.id),
    kind: String(row.kind) as RelationshipOverviewItem["kind"],
    status: String(row.status),
    subjectPersonId: typeof row.subject_person_id === "string" ? row.subject_person_id : null,
    type: typeof row.item_type === "string" ? row.item_type : null,
    purpose: typeof row.purpose === "string" ? row.purpose : null,
    context: typeof row.context === "string" ? row.context : null,
    scopeCount: row.scope_count == null ? null : Number(row.scope_count),
    version: row.version == null ? null : Number(row.version),
    scopes: Array.isArray(row.scopes) && row.scopes.every((scope) => typeof scope === "string") ? row.scopes as string[] : null,
    startedAtUtc: iso(row.started_at_utc),
    endedAtUtc: iso(row.ended_at_utc),
    occurredAtUtc: iso(row.occurred_at_utc) ?? new Date(0).toISOString(),
  };
}

export async function getRelationshipOverview(sql: AdminSql, query: RelationshipOverviewQuery) {
  const offset = (query.page - 1) * query.pageSize;
  const summaryRows = await sql`
    with overview as (
      select 'relationship'::text as kind, status::text as status from network.person_relationships
      union all
      select 'relationship'::text as kind, status::text as status from admin.care_relationship_directory_v1
      union all
      select 'consent'::text as kind, status::text as status from consent.consent_records
      union all
      select 'access_grant'::text as kind, status::text as status from security.access_grants
    )
    select kind, status, count(*)::integer as total
    from overview
    group by kind, status
    order by kind asc, status asc
  `;

  const countRows = await sql`
    with grant_scope_values as (
      select grant_id, count(*)::integer as scope_count,
             array_agg(scope::text order by scope::text)::text[] as scopes
      from security.access_grant_scopes group by grant_id
    ), overview as (
      select r.id, 'relationship'::text as kind, r.status::text as status,
             r.source_person_id as subject_person_id, r.relationship_type::text as item_type,
             null::text as purpose, null::text as context, null::integer as scope_count,
             null::integer as version, null::text[] as scopes,
             r.created_at_utc as started_at_utc, r.ended_at_utc, r.created_at_utc as occurred_at_utc
      from network.person_relationships r
      union all
      select c.id, 'relationship'::text as kind, c.status::text as status,
             c.patient_person_id as subject_person_id, 'Caregiver'::text as item_type,
             null::text as purpose, null::text as context, null::integer as scope_count,
             null::integer as version, null::text[] as scopes,
             c.created_at_utc as started_at_utc, c.revoked_at_utc as ended_at_utc, c.created_at_utc as occurred_at_utc
      from admin.care_relationship_directory_v1 c
      union all
      select c.id, 'consent'::text as kind, c.status::text as status,
             c.subject_person_id, null::text as item_type, c.purpose::text,
             c.scope_key::text as context, null::integer as scope_count,
             null::integer as version, null::text[] as scopes,
             c.granted_at_utc as started_at_utc, coalesce(c.revoked_at_utc, c.expires_at_utc) as ended_at_utc,
             c.created_at_utc as occurred_at_utc
      from consent.consent_records c
      union all
      select g.id, 'access_grant'::text as kind, g.status::text as status,
             g.subject_person_id, null::text as item_type, null::text as purpose,
             g.context_type::text as context, coalesce(sc.scope_count, 0)::integer as scope_count,
             null::integer as version, coalesce(sc.scopes, array[]::text[]) as scopes,
             g.starts_at_utc as started_at_utc, coalesce(g.revoked_at_utc, g.expires_at_utc) as ended_at_utc,
             g.created_at_utc as occurred_at_utc
      from security.access_grants g
      left join grant_scope_values sc on sc.grant_id = g.id
    )
    select count(*)::integer as total from overview
    where (${query.kind}::text is null or kind = ${query.kind})
      and (${query.status}::text is null or lower(status) = lower(${query.status}))
  `;

  const itemRows = await sql`
    with grant_scope_values as (
      select grant_id, count(*)::integer as scope_count,
             array_agg(scope::text order by scope::text)::text[] as scopes
      from security.access_grant_scopes group by grant_id
    ), overview as (
      select r.id, 'relationship'::text as kind, r.status::text as status,
             r.source_person_id as subject_person_id, r.relationship_type::text as item_type,
             null::text as purpose, null::text as context, null::integer as scope_count,
             null::integer as version, null::text[] as scopes,
             r.created_at_utc as started_at_utc, r.ended_at_utc, r.created_at_utc as occurred_at_utc
      from network.person_relationships r
      union all
      select c.id, 'relationship'::text as kind, c.status::text as status,
             c.patient_person_id as subject_person_id, 'Caregiver'::text as item_type,
             null::text as purpose, null::text as context, null::integer as scope_count,
             null::integer as version, null::text[] as scopes,
             c.created_at_utc as started_at_utc, c.revoked_at_utc as ended_at_utc, c.created_at_utc as occurred_at_utc
      from admin.care_relationship_directory_v1 c
      union all
      select c.id, 'consent'::text as kind, c.status::text as status,
             c.subject_person_id, null::text as item_type, c.purpose::text,
             c.scope_key::text as context, null::integer as scope_count,
             null::integer as version, null::text[] as scopes,
             c.granted_at_utc as started_at_utc, coalesce(c.revoked_at_utc, c.expires_at_utc) as ended_at_utc,
             c.created_at_utc as occurred_at_utc
      from consent.consent_records c
      union all
      select g.id, 'access_grant'::text as kind, g.status::text as status,
             g.subject_person_id, null::text as item_type, null::text as purpose,
             g.context_type::text as context, coalesce(sc.scope_count, 0)::integer as scope_count,
             null::integer as version, coalesce(sc.scopes, array[]::text[]) as scopes,
             g.starts_at_utc as started_at_utc, coalesce(g.revoked_at_utc, g.expires_at_utc) as ended_at_utc,
             g.created_at_utc as occurred_at_utc
      from security.access_grants g
      left join grant_scope_values sc on sc.grant_id = g.id
    )
    select id, kind, status, subject_person_id, item_type, purpose, context,
           scope_count, version, scopes, started_at_utc, ended_at_utc, occurred_at_utc
    from overview
    where (${query.kind}::text is null or kind = ${query.kind})
      and (${query.status}::text is null or lower(status) = lower(${query.status}))
    order by occurred_at_utc desc, kind asc, id desc
    limit ${query.pageSize} offset ${offset}
  `;

  return {
    summary: summaryRows.map((row) => ({ kind: String(row.kind) as RelationshipOverviewItem["kind"], status: String(row.status), total: Number(row.total ?? 0) })),
    items: (itemRows as unknown as Row[]).map(mapItem),
    total: Number(countRows[0]?.total ?? 0),
  };
}
