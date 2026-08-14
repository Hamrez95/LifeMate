import type { AdminSql } from "./database_client.ts";
import type { RelationshipLedgerQuery } from "./relationship_ledger.ts";
import type { RelationshipOverviewKind } from "./relationships.ts";

type Row = Record<string, unknown>;

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

export type RelationshipLedgerItem = {
  ledgerId: string;
  entityId: string;
  kind: RelationshipOverviewKind;
  eventType: string;
  status: string;
  subjectPersonId: string | null;
  type: string | null;
  purpose: string | null;
  context: string | null;
  scopeCount: number | null;
  occurredAtUtc: string;
  evidence: "event" | "lifecycle_timestamp";
};

function mapItem(row: Row): RelationshipLedgerItem {
  return {
    ledgerId: String(row.ledger_id),
    entityId: String(row.entity_id),
    kind: String(row.kind) as RelationshipOverviewKind,
    eventType: String(row.event_type),
    status: String(row.status),
    subjectPersonId: typeof row.subject_person_id === "string"
      ? row.subject_person_id
      : null,
    type: typeof row.item_type === "string" ? row.item_type : null,
    purpose: typeof row.purpose === "string" ? row.purpose : null,
    context: typeof row.context === "string" ? row.context : null,
    scopeCount: row.scope_count == null ? null : Number(row.scope_count),
    occurredAtUtc: iso(row.occurred_at_utc),
    evidence: String(row.evidence) as RelationshipLedgerItem["evidence"],
  };
}

const LEDGER_CTE = `
  with grant_scope_counts as (
    select grant_id, count(*)::integer as scope_count
    from security.access_grant_scopes
    group by grant_id
  ), ledger as (
    select concat(r.id::text, ':created') as ledger_id,
           r.id::text as entity_id,
           'relationship'::text as kind,
           'relationship_created'::text as event_type,
           'Active'::text as status,
           r.source_person_id as subject_person_id,
           r.relationship_type::text as item_type,
           null::text as purpose,
           null::text as context,
           null::integer as scope_count,
           r.created_at_utc as occurred_at_utc,
           'lifecycle_timestamp'::text as evidence
    from network.person_relationships r

    union all

    select concat(r.id::text, ':ended') as ledger_id,
           r.id::text as entity_id,
           'relationship'::text as kind,
           'relationship_ended'::text as event_type,
           r.status::text as status,
           r.source_person_id as subject_person_id,
           r.relationship_type::text as item_type,
           null::text as purpose,
           null::text as context,
           null::integer as scope_count,
           r.ended_at_utc as occurred_at_utc,
           'lifecycle_timestamp'::text as evidence
    from network.person_relationships r
    where r.ended_at_utc is not null

    union all

    select e.id::text as ledger_id,
           c.id::text as entity_id,
           'consent'::text as kind,
           lower(e.event_type::text) as event_type,
           e.event_type::text as status,
           c.subject_person_id,
           null::text as item_type,
           c.purpose::text,
           c.scope_key::text as context,
           null::integer as scope_count,
           e.occurred_at_utc,
           'event'::text as evidence
    from consent.consent_events e
    join consent.consent_records c on c.id = e.consent_record_id

    union all

    select concat(g.id::text, ':created') as ledger_id,
           g.id::text as entity_id,
           'access_grant'::text as kind,
           'grant_created'::text as event_type,
           'Active'::text as status,
           g.subject_person_id,
           null::text as item_type,
           null::text as purpose,
           g.context_type::text as context,
           coalesce(sc.scope_count, 0)::integer as scope_count,
           g.created_at_utc as occurred_at_utc,
           'lifecycle_timestamp'::text as evidence
    from security.access_grants g
    left join grant_scope_counts sc on sc.grant_id = g.id

    union all

    select concat(g.id::text, ':revoked') as ledger_id,
           g.id::text as entity_id,
           'access_grant'::text as kind,
           'grant_revoked'::text as event_type,
           'Revoked'::text as status,
           g.subject_person_id,
           null::text as item_type,
           null::text as purpose,
           g.context_type::text as context,
           coalesce(sc.scope_count, 0)::integer as scope_count,
           g.revoked_at_utc as occurred_at_utc,
           'lifecycle_timestamp'::text as evidence
    from security.access_grants g
    left join grant_scope_counts sc on sc.grant_id = g.id
    where g.revoked_at_utc is not null

    union all

    select concat(g.id::text, ':expired') as ledger_id,
           g.id::text as entity_id,
           'access_grant'::text as kind,
           'grant_expired'::text as event_type,
           'Expired'::text as status,
           g.subject_person_id,
           null::text as item_type,
           null::text as purpose,
           g.context_type::text as context,
           coalesce(sc.scope_count, 0)::integer as scope_count,
           g.expires_at_utc as occurred_at_utc,
           'lifecycle_timestamp'::text as evidence
    from security.access_grants g
    left join grant_scope_counts sc on sc.grant_id = g.id
    where g.status = 'Expired' and g.expires_at_utc is not null
  )
`;

export async function getRelationshipLedger(
  sql: AdminSql,
  query: RelationshipLedgerQuery,
) {
  const offset = (query.page - 1) * query.pageSize;
  const startUtc = `${query.from} 00:00:00`;
  const endExclusiveUtc = `${query.to} 23:59:59.999999`;

  const countRows = await sql.unsafe(
    `${LEDGER_CTE}
     select count(*)::integer as total
     from ledger
     where occurred_at_utc >= ($1::timestamp at time zone 'Asia/Tehran')
       and occurred_at_utc <= ($2::timestamp at time zone 'Asia/Tehran')
       and ($3::text is null or kind = $3)
       and ($4::text is null or lower(status) = lower($4))`,
    [startUtc, endExclusiveUtc, query.kind, query.status],
  );

  const itemRows = await sql.unsafe(
    `${LEDGER_CTE}
     select ledger_id, entity_id, kind, event_type, status, subject_person_id,
            item_type, purpose, context, scope_count, occurred_at_utc, evidence
     from ledger
     where occurred_at_utc >= ($1::timestamp at time zone 'Asia/Tehran')
       and occurred_at_utc <= ($2::timestamp at time zone 'Asia/Tehran')
       and ($3::text is null or kind = $3)
       and ($4::text is null or lower(status) = lower($4))
     order by occurred_at_utc desc, kind asc, ledger_id desc
     limit $5 offset $6`,
    [startUtc, endExclusiveUtc, query.kind, query.status, query.pageSize, offset],
  );

  return {
    items: (itemRows as unknown as Row[]).map(mapItem),
    total: Number(countRows[0]?.total ?? 0),
  };
}
