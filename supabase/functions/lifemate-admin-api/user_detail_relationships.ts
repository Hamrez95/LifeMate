import type { AdminSql } from "./database_client.ts";

export async function getUserRelationshipSummary(
  sql: AdminSql,
  personId: string | null,
) {
  if (!personId) return [];

  const rows = await sql`
    select direction, relationship_type, status, count(*)::integer as total
    from (
      select 'Outgoing'::text as direction, relationship_type, status
      from network.person_relationships
      where source_person_id = ${personId}::uuid

      union all

      select 'Incoming'::text as direction, relationship_type, status
      from network.person_relationships
      where target_person_id = ${personId}::uuid
    ) relationship_summary
    group by direction, relationship_type, status
    order by direction asc, relationship_type asc, status asc
  `;

  return rows.map((row) => ({
    direction: String(row.direction) as "Incoming" | "Outgoing",
    relationshipType: String(row.relationship_type),
    status: String(row.status),
    count: Number(row.total ?? 0),
  }));
}
