import { getLifeMateSql } from "./database_client.ts";
import { ApiError, limitedOptional, requiredText } from "./validation.ts";

type Row = Record<string, unknown>;

function iso(value: unknown): string {
  if (value instanceof Date) return value.toISOString();
  return new Date(String(value)).toISOString();
}

function mapMedication(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    name: row.name,
    strengthText: row.strength_text,
    form: row.form,
    notes: row.notes,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  return personId;
}

async function insertAudit(
  connection: any,
  actorAppUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id, metadata_json, created_at_utc)
    values (${crypto.randomUUID()}, ${actorAppUserId}::uuid, ${action}, ${resourceType}, ${resourceId}::uuid, null, now())
  `;
}

export function createPersonMedicationStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function createMedication(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const name = requiredText(body.name, "name", 120);
    const strength = limitedOptional(body.strengthText, "strengthText", 80);
    const form = limitedOptional(body.form, "form", 50);
    const notes = limitedOptional(body.notes, "notes", 500);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, appUserId);
      const countRows =
        await tx`select count(*)::integer as count from lifemate.medications where owner_person_id=${personId}::uuid`;
      try {
        await tx`select commerce.assert_free_quota(${appUserId}::uuid,'free.medications.max',${
          Number(countRows[0]?.count ?? 0)
        }::integer)`;
      } catch (error) {
        if (
          String((error as Record<string, unknown>)?.message ?? "").includes(
            "premium_required_quota_reached",
          )
        ) {
          throw new ApiError(
            403,
            "premium_required_quota_reached",
            "Premium is required to add another active medication.",
          );
        }
        throw error;
      }
      const rows = await tx`
        insert into lifemate.medications
          (id,owner_person_id,name,strength_text,form,notes,version,created_at_utc,updated_at_utc)
        values (${crypto.randomUUID()}::uuid,${personId}::uuid,${name},${strength},${form},${notes},1,${now},${now}) returning *
      `;
      await insertAudit(
        tx,
        appUserId,
        "medication.created",
        "medication",
        String(rows[0].id),
      );
      return mapMedication(rows[0]);
    });
  }

  async function listMedications(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await requireSelfPerson(sql, appUserId);
    const rows =
      await sql`select * from lifemate.medications where owner_person_id=${personId}::uuid order by name,id limit 100`;
    return rows.map(mapMedication);
  }
  return { createMedication, listMedications };
}
