import { getLifeMateSql } from "./database_client.ts";

export function createMedicationScheduleAuditWriter(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function record(input: {
    actorAppUserId: string;
    action: string;
    resourceType: string;
    resourceId?: string | null;
    metadata: Record<string, unknown>;
  }): Promise<void> {
    const resourceId = input.resourceId ?? null;
    await sql`
      insert into lifemate.audit_logs
        (id, actor_user_id, action, resource_type, resource_id,
         metadata_json, created_at_utc)
      values
        (${crypto.randomUUID()}::uuid, ${input.actorAppUserId}::uuid,
         ${input.action}, ${input.resourceType}, ${resourceId}::uuid,
         ${JSON.stringify(input.metadata)}::jsonb, now())
    `;
  }

  return { record };
}
