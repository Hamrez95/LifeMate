import type { AdminSql } from "./database_client.ts";

type RelationshipRow = Record<string, unknown>;
type RelationshipSource = "person_relationship" | "care_relationship";

export type UserRelationshipRecord = {
  relationshipId: string;
  source: RelationshipSource;
  direction: "Incoming" | "Outgoing";
  relationshipType: string;
  status: string;
  counterpartPersonId: string;
  counterpartAccountId: string | null;
  counterpartDisplayName: string | null;
  counterpartUsername: string | null;
  createdAtUtc: string;
  endedAtUtc: string | null;
};

export type UserRelationshipSummaryItem = {
  direction: "Incoming" | "Outgoing";
  relationshipType: string;
  status: string;
  count: number;
  records: UserRelationshipRecord[];
};

function asIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function asNullableIso(value: unknown): string | null {
  return value == null ? null : asIso(value);
}

function asNullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function groupUserRelationshipRows(
  rows: readonly RelationshipRow[],
): UserRelationshipSummaryItem[] {
  const groups = new Map<string, UserRelationshipSummaryItem>();
  for (const raw of rows) {
    const direction = String(raw.direction) as "Incoming" | "Outgoing";
    const relationshipType = String(raw.relationship_type);
    const status = String(raw.status);
    const key = `${direction}\u0000${relationshipType}\u0000${status}`;
    let group = groups.get(key);
    if (!group) {
      group = {
        direction,
        relationshipType,
        status,
        count: 0,
        records: [],
      };
      groups.set(key, group);
    }
    group.count += 1;
    group.records.push({
      relationshipId: String(raw.relationship_id),
      source: String(raw.relationship_source) as RelationshipSource,
      direction,
      relationshipType,
      status,
      counterpartPersonId: String(raw.counterpart_person_id),
      counterpartAccountId: asNullableString(raw.counterpart_account_id),
      counterpartDisplayName: asNullableString(raw.counterpart_display_name),
      counterpartUsername: asNullableString(raw.counterpart_username),
      createdAtUtc: asIso(raw.created_at_utc),
      endedAtUtc: asNullableIso(raw.ended_at_utc),
    });
  }
  return [...groups.values()];
}

/**
 * Relationship records deliberately expose counterpart-safe identity only.
 * Relationship is not Consent or Access Grant, and this query never reads
 * auth.users, contact plaintext or health data.
 */
export async function getUserRelationshipSummary(
  sql: AdminSql,
  personId: string | null,
): Promise<UserRelationshipSummaryItem[]> {
  if (!personId) return [];

  const rows = await sql`
    with relationship_rows as (
      select
        r.id as relationship_id,
        'person_relationship'::text as relationship_source,
        'Outgoing'::text as direction,
        r.relationship_type::text as relationship_type,
        r.status::text as status,
        r.target_person_id as counterpart_person_id,
        r.created_at_utc,
        r.ended_at_utc
      from network.person_relationships r
      where r.source_person_id = ${personId}::uuid

      union all

      select
        r.id as relationship_id,
        'person_relationship'::text as relationship_source,
        'Incoming'::text as direction,
        r.relationship_type::text as relationship_type,
        r.status::text as status,
        r.source_person_id as counterpart_person_id,
        r.created_at_utc,
        r.ended_at_utc
      from network.person_relationships r
      where r.target_person_id = ${personId}::uuid

      union all

      select
        r.id as relationship_id,
        'care_relationship'::text as relationship_source,
        'Outgoing'::text as direction,
        'Caregiver'::text as relationship_type,
        r.status::text as status,
        r.caregiver_person_id as counterpart_person_id,
        r.created_at_utc,
        r.revoked_at_utc as ended_at_utc
      from admin.care_relationship_directory_v1 r
      where r.patient_person_id = ${personId}::uuid

      union all

      select
        r.id as relationship_id,
        'care_relationship'::text as relationship_source,
        'Incoming'::text as direction,
        'CareRecipient'::text as relationship_type,
        r.status::text as status,
        r.patient_person_id as counterpart_person_id,
        r.created_at_utc,
        r.revoked_at_utc as ended_at_utc
      from admin.care_relationship_directory_v1 r
      where r.caregiver_person_id = ${personId}::uuid
    )
    select
      rr.*,
      counterpart.account_id as counterpart_account_id,
      counterpart.display_name as counterpart_display_name,
      counterpart.username as counterpart_username
    from relationship_rows rr
    left join lateral (
      select d.account_id, d.display_name, d.username
      from admin.user_directory_v2 d
      where d.person_id = rr.counterpart_person_id
      order by d.created_at_utc asc, d.account_id asc
      limit 1
    ) counterpart on true
    order by rr.direction asc,
             rr.relationship_type asc,
             rr.status asc,
             rr.created_at_utc desc,
             rr.relationship_id asc
  `;

  return groupUserRelationshipRows(rows as unknown as RelationshipRow[]);
}
