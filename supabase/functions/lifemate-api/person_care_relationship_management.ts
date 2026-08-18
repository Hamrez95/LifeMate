import { getLifeMateSql } from "./database_client.ts";
import { ApiError, requiredUuid } from "./validation.ts";

type Row = Record<string, any>;

/**
 * Canonical Person membership boundary for relationship inventory, permission
 * ownership and revocation. Legacy AppUser participant IDs remain only for the
 * public compatibility contract and actor/audit provenance during migration.
 */
export function createPersonCareRelationshipManagementStore(
  databaseUrl: string,
) {
  const sql = getLifeMateSql(databaseUrl);

  async function listRelationships(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await requireSelfPerson(sql, appUserId);
    const rows = await sql`
      select r.*,
             patient.display_name as patient_display_name,
             caregiver.display_name as caregiver_display_name
      from lifemate.care_relationships r
      left join core.person_profiles patient
        on patient.person_id = r.patient_person_id
      left join core.person_profiles caregiver
        on caregiver.person_id = r.caregiver_person_id
      where r.patient_person_id = ${personId}::uuid
         or r.caregiver_person_id = ${personId}::uuid
      order by r.created_at_utc desc
      limit 100
    `;
    return rows.map(mapRelationshipRow);
  }

  async function updateRelationshipPermissions(
    patientAppUserId: string,
    relationshipIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    if (typeof body.canViewWomenCalendar !== "boolean") {
      throw new ApiError(
        400,
        "invalid_care_permission",
        "canViewWomenCalendar must be a boolean.",
      );
    }

    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(tx, patientAppUserId);
      const existingRows = await tx`
        select *
        from lifemate.care_relationships
        where id = ${relationshipId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
          and status = 'Active'
        for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw new ApiError(
          404,
          "relationship_not_found",
          "Active owner relationship was not found.",
        );
      }

      const rows = await tx`
        update lifemate.care_relationships
        set can_view_women_calendar = ${body.canViewWomenCalendar},
            updated_at_utc = now()
        where id = ${relationshipId}::uuid
        returning *
      `;
      await insertAudit(
        tx,
        patientAppUserId,
        "care_relationship.permissions_updated",
        "care_relationship",
        relationshipId,
      );
      return await mapRelationship(tx, rows[0]);
    });
  }

  async function revokeRelationship(
    actorAppUserId: string,
    relationshipIdValue: unknown,
  ): Promise<void> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    await sql.begin(async (tx: any) => {
      const actorPersonId = await requireSelfPerson(tx, actorAppUserId);
      const relationships = await tx`
        select *
        from lifemate.care_relationships
        where id = ${relationshipId}::uuid
          and (
            patient_person_id = ${actorPersonId}::uuid
            or caregiver_person_id = ${actorPersonId}::uuid
          )
        for update
      `;
      const relationship = relationships[0];
      if (!relationship) {
        throw new ApiError(
          404,
          "relationship_not_found",
          "Care relationship was not found.",
        );
      }
      if (relationship.status === "Revoked") return;

      await tx`
        update lifemate.care_relationships
        set status = 'Revoked', revoked_by_user_id = ${actorAppUserId}::uuid,
            revoked_at_utc = now(), updated_at_utc = now()
        where id = ${relationshipId}::uuid
      `;
      await insertAudit(
        tx,
        actorAppUserId,
        "care_relationship.revoked",
        "care_relationship",
        relationshipId,
      );
    });
  }

  return {
    listRelationships,
    updateRelationshipPermissions,
    revokeRelationship,
  };
}

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
      as person_id
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

async function mapRelationship(
  connection: any,
  relationship: Row,
): Promise<Record<string, unknown>> {
  const names = await connection`
    select person_id::text, display_name
    from core.person_profiles
    where person_id in (
      ${relationship.patient_person_id}::uuid,
      ${relationship.caregiver_person_id}::uuid
    )
  `;
  const byId = new Map(
    names.map((row: Row) => [String(row.person_id), row.display_name]),
  );
  return mapRelationshipRow({
    ...relationship,
    patient_display_name: byId.get(String(relationship.patient_person_id)),
    caregiver_display_name: byId.get(String(relationship.caregiver_person_id)),
  });
}

function mapRelationshipRow(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: row.patient_user_id,
    patientDisplayName: row.patient_display_name ?? "LifeMate User",
    caregiverUserId: row.caregiver_user_id,
    caregiverDisplayName: row.caregiver_display_name ?? "LifeMate User",
    status: String(row.status).toLowerCase(),
    canViewWomenCalendar: row.can_view_women_calendar === true,
    patientConsentedAtUtc: iso(row.patient_consented_at_utc),
    caregiverConsentedAtUtc: iso(row.caregiver_consented_at_utc),
    revokedAtUtc: row.revoked_at_utc == null ? null : iso(row.revoked_at_utc),
    createdAtUtc: iso(row.created_at_utc),
  };
}

async function insertAudit(
  connection: any,
  actorUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}, ${actorUserId}::uuid, ${action}, ${resourceType},
       ${resourceId}::uuid, null, now())
  `;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
